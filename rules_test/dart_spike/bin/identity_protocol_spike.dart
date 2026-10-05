// Phase 1 spike (second part) for DESIGN-database-rules.md D2/D3/D7.
//
// Proves, against the RTDB emulator using firebase_dart's runTransaction:
//  1. conditional replacement of an exact audited placeholder authuid
//     (a null-to-UID claim cannot do this);
//  2. crash injection after every step of link and create, followed by a
//     retry: the bidirectional invariant is restored and nothing is orphaned;
//  3. partial states fail closed: a different uid cannot take over a record
//     that is mid-link;
//  4. an abandoned create is detected by the audit and reaped after its
//     intent expires, freeing the alias;
//  5. lease acquisition with expiry, including contended takeover of a stale
//     lease;
//  6. a version-guarded aggregator write: an older computation finishing last
//     cannot overwrite a newer one.
import 'dart:io';
import 'dart:math';

import 'package:firebase_dart/standalone_database.dart';

// ---------------------------------------------------------------- primitives

const Object keep = Object();

/// Run [decide] inside a transaction at [ref]. [decide] returns the new value,
/// `null` to delete, or [keep] to leave the location unchanged. Returns true
/// when the change was applied (the handler can run several times; only the
/// last run counts).
Future<bool> update(DatabaseReference ref, Object? Function(Object? current) decide) async {
  var applied = false;
  await ref.runTransaction((mutableData) async {
    final next = decide(mutableData.value);
    applied = !identical(next, keep);
    if (applied) {
      mutableData.value = next;
    }
    return mutableData;
  });
  return applied;
}

/// Single-location claim: null to [value], idempotent for the same value.
Future<bool> claim(DatabaseReference ref, String value) =>
    update(ref, (cur) => cur == null || cur == value ? value : keep);

Future<void> release(DatabaseReference ref, String value) =>
    update(ref, (cur) => cur == value ? null : keep);

class Crash implements Exception {
  Crash(this.step);
  final int step;
}

// ---------------------------------------------------------------- the model

class Model {
  Model(this.root);
  final DatabaseReference root;

  DatabaseReference at(String path) =>
      path.split('/').fold<DatabaseReference>(root, (r, s) => r.child(s));

  DatabaseReference authuid(String id) => at('AllTippers/$id/authuid');
  DatabaseReference index(String uid) => at('AuthIndex/$uid');
  DatabaseReference alias(String a) => at('AliasIndex/$a');
  DatabaseReference logon(String l) => at('LogonIndex/$l');
  DatabaseReference intent(String uid) => at('CreateIntents/$uid');
  DatabaseReference placeholder(String id) => at('Placeholders/$id');
  DatabaseReference lease(String id) => at('IdentityLocks/$id');

  static bool isUid(Object? v) => v is String && v.startsWith('uid');

  // ------------------------------------------------------------------ link

  /// Link [uid] to the existing record [tipperId].
  /// The only value that may be replaced is null, the same uid, or the exact
  /// audited placeholder recorded for this record in step 0 of the rollout.
  Future<bool> link(String uid, String tipperId, {int? crashAfter}) async {
    final audited = await placeholder(tipperId).get() as String?;
    final before = await authuid(tipperId).get() as String?;

    final took = await update(
      authuid(tipperId),
      (cur) => cur == null || cur == uid || (audited != null && cur == audited) ? uid : keep,
    );
    if (!took) return false;
    if (crashAfter == 0) throw Crash(0);

    final indexed = await claim(index(uid), tipperId);
    if (!indexed) {
      // The uid is already mapped elsewhere: compensate by restoring the record.
      await update(authuid(tipperId), (cur) => cur == uid ? before : keep);
      return false;
    }
    if (crashAfter == 1) throw Crash(1);
    return true;
  }

  // ---------------------------------------------------------------- create

  /// Create a record for [uid]. A crash can be injected after steps 0..4.
  Future<bool> create(
    String uid,
    String aliasKey,
    String logonKey, {
    required int nowMs,
    int? crashAfter,
  }) async {
    // step 0: a durable intent so a retry reuses the same tipperId.
    final fresh = 'tip${Random().nextInt(1 << 30)}|$nowMs';
    await claim(intent(uid), fresh);
    final intentValue = await intent(uid).get() as String;
    final id = intentValue.split('|').first;
    if (crashAfter == 0) throw Crash(0);

    Future<void> rollback({bool alias = false, bool logon = false, bool record = false}) async {
      if (record) await update(at('AllTippers/$id'), (cur) => cur is Map && cur['authuid'] == uid ? null : keep);
      if (logon) await release(this.logon(logonKey), id);
      if (alias) await release(this.alias(aliasKey), id);
      await release(intent(uid), intentValue);
    }

    // step 1: alias
    if (!await claim(alias(aliasKey), id)) {
      await rollback();
      return false;
    }
    if (crashAfter == 1) throw Crash(1);

    // step 2: logon
    if (!await claim(logon(logonKey), id)) {
      await rollback(alias: true);
      return false;
    }
    if (crashAfter == 2) throw Crash(2);

    // step 3: the record (only if absent, or already ours)
    final wrote = await update(
      at('AllTippers/$id'),
      (cur) => cur == null
          ? <String, Object?>{'authuid': uid, 'name': aliasKey}
          : (cur is Map && cur['authuid'] == uid ? cur : keep),
    );
    if (!wrote) {
      await rollback(alias: true, logon: true);
      return false;
    }
    if (crashAfter == 3) throw Crash(3);

    // step 4: the commit
    if (!await claim(index(uid), id)) {
      await rollback(alias: true, logon: true, record: true);
      return false;
    }
    if (crashAfter == 4) throw Crash(4);

    await release(intent(uid), intentValue);
    return true;
  }

  // ----------------------------------------------------------------- audit

  Future<Set<String>> audit() async {
    final out = <String>{};
    final tippers = (await at('AllTippers').get() as Map?) ?? const {};
    final auth = (await at('AuthIndex').get() as Map?) ?? const {};
    final aliases = (await at('AliasIndex').get() as Map?) ?? const {};
    final logons = (await at('LogonIndex').get() as Map?) ?? const {};
    final intents = (await at('CreateIntents').get() as Map?) ?? const {};

    auth.forEach((uid, id) {
      final rec = tippers[id];
      if (rec is! Map || rec['authuid'] != uid) out.add('index-dangling:$uid');
    });
    tippers.forEach((id, rec) {
      final a = (rec as Map)['authuid'];
      if (isUid(a) && auth[a] != id) out.add('record-unindexed:$id');
    });
    aliases.forEach((k, id) {
      if (!tippers.containsKey(id)) out.add('alias-dangling:$k');
    });
    logons.forEach((k, id) {
      if (!tippers.containsKey(id)) out.add('logon-dangling:$k');
    });
    if (intents.isNotEmpty) out.add('intent-pending');
    return out;
  }

  /// Reap creates whose intent is older than [ttlMs] and whose record never
  /// reached the index: free their claims so the alias is usable again.
  Future<int> reap({required int nowMs, required int ttlMs}) async {
    var reaped = 0;
    final intents = (await at('CreateIntents').get() as Map?) ?? const {};
    for (final entry in intents.entries.toList()) {
      final uid = entry.key as String;
      final value = entry.value as String;
      final id = value.split('|').first;
      final at0 = int.parse(value.split('|').last);
      if (nowMs - at0 < ttlMs) continue;
      if (await index(uid).get() == id) {
        await release(intent(uid), value);
        continue;
      }
      final aliases = (await at('AliasIndex').get() as Map?) ?? const {};
      for (final a in aliases.entries) {
        if (a.value == id) await release(alias(a.key as String), id);
      }
      final logons = (await at('LogonIndex').get() as Map?) ?? const {};
      for (final l in logons.entries) {
        if (l.value == id) await release(logon(l.key as String), id);
      }
      await update(at('AllTippers/$id'), (cur) => cur is Map && cur['authuid'] == uid ? null : keep);
      await release(intent(uid), value);
      reaped++;
    }
    return reaped;
  }

  // ----------------------------------------------------------------- lease

  /// Acquire a lease; takes over only an expired lease, by exact-value CAS.
  Future<bool> acquireLease(String id, String owner, int nowMs, int ttlMs) => update(lease(id), (cur) {
        if (cur == null) return '$owner|${nowMs + ttlMs}';
        final parts = (cur as String).split('|');
        final expired = int.parse(parts.last) < nowMs;
        return expired || parts.first == owner ? '$owner|${nowMs + ttlMs}' : keep;
      });

  // ------------------------------------------------------------ aggregator

  /// Write [current] only if it is based on strictly more history than what
  /// is stored. `basedOnCount` is monotonic because history is append-only.
  Future<bool> writeCurrentIfNewer(String game, Map<String, Object?> computed) =>
      update(at('LS/$game/current'), (cur) {
        final existing = cur is Map ? (cur['basedOnCount'] as int? ?? 0) : 0;
        return (computed['basedOnCount'] as int) > existing ? computed : keep;
      });
}

// ------------------------------------------------------------------- harness

var failures = 0;
void check(bool condition, String message) {
  if (condition) {
    stdout.writeln('ok:   $message');
  } else {
    failures++;
    stderr.writeln('FAIL: $message');
  }
}

Future<void> main() async {
  final host = Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'] ?? '127.0.0.1:8000';
  final db = StandaloneFirebaseDatabase('http://$host/?ns=demo-dau-rules');
  await db.authenticate('owner');
  final base = db.reference().child('IdSpike');

  Future<Model> fresh() async {
    await base.remove();
    return Model(base);
  }

  // ---- 1. exact audited placeholder replacement
  var m = await fresh();
  await m.at('AllTippers/t1/authuid').set('old.sheet@example.com');
  await m.placeholder('t1').set('old.sheet@example.com');
  check(await m.link('uidA', 't1'), 'placeholder: link replaces the exact audited placeholder');
  check(await m.authuid('t1').get() == 'uidA' && await m.index('uidA').get() == 't1',
      'placeholder: record and index agree after link');
  check((await m.audit()).isEmpty, 'placeholder: audit clean');

  m = await fresh();
  await m.at('AllTippers/t1/authuid').set('someone.else@example.com'); // differs from the audit
  await m.placeholder('t1').set('old.sheet@example.com');
  check(!await m.link('uidA', 't1'), 'placeholder: a value that is not the audited one is refused');
  check(await m.authuid('t1').get() == 'someone.else@example.com', 'placeholder: record left untouched');

  m = await fresh();
  await m.at('AllTippers/t1/authuid').set('uidB'); // already a real uid
  check(!await m.link('uidA', 't1'), 'placeholder: a real uid is never replaced (no takeover)');

  m = await fresh();
  await m.at('AllTippers/t1/authuid').set('old.sheet@example.com');
  await m.placeholder('t1').set('old.sheet@example.com');
  final race = await Future.wait(['uidA', 'uidB', 'uidC'].map((u) => m.link(u, 't1')));
  check(race.where((r) => r).length == 1, 'placeholder: exactly one of 3 racing uids links the record');
  check((await m.audit()).isEmpty, 'placeholder: audit clean after the race');

  m = await fresh();
  await m.at('AllTippers/t1/authuid').set('old.sheet@example.com');
  await m.placeholder('t1').set('old.sheet@example.com');
  await m.index('uidA').set('t_other'); // uidA is already mapped to a different record
  await m.at('AllTippers/t_other/authuid').set('uidA');
  check(!await m.link('uidA', 't1'), 'placeholder: uid already mapped elsewhere is refused');
  check(await m.authuid('t1').get() == 'old.sheet@example.com',
      'placeholder: compensation restores the original placeholder');

  // ---- 2/3. link crash injection and fail-closed partial state
  for (final step in [0, 1]) {
    m = await fresh();
    await m.at('AllTippers/t1/authuid').set('old.sheet@example.com');
    await m.placeholder('t1').set('old.sheet@example.com');
    try {
      await m.link('uidA', 't1', crashAfter: step);
      check(false, 'link crash after step $step should throw');
    } on Crash {
      // expected
    }
    final during = await m.audit();
    if (step == 0) {
      check(during.contains('record-unindexed:t1'), 'link crash@0: audit flags the half-linked record');
      check(!await m.link('uidB', 't1'), 'link crash@0: a different uid cannot take over a half-linked record');
    }
    check(await m.link('uidA', 't1'), 'link crash@$step: retry by the same uid completes');
    check((await m.audit()).isEmpty, 'link crash@$step: audit clean after retry');
  }

  // ---- 2. create crash injection at every step, then retry
  for (final step in [0, 1, 2, 3, 4]) {
    m = await fresh();
    try {
      await m.create('uidA', 'bigfan', 'hash1', nowMs: 1000, crashAfter: step);
      check(false, 'create crash after step $step should throw');
    } on Crash {
      // expected
    }
    check(await m.create('uidA', 'bigfan', 'hash1', nowMs: 2000), 'create crash@$step: retry completes');
    final tippers = (await m.at('AllTippers').get() as Map?) ?? const {};
    check(tippers.length == 1, 'create crash@$step: exactly one record after retry (${tippers.length})');
    check((await m.audit()).isEmpty, 'create crash@$step: audit clean after retry');
  }

  // ---- 2. create conflicts roll back cleanly
  m = await fresh();
  check(await m.create('uidA', 'bigfan', 'hash1', nowMs: 1000), 'create: first registration succeeds');
  check(!await m.create('uidB', 'bigfan', 'hash2', nowMs: 1001), 'create: duplicate alias refused');
  check(!await m.create('uidC', 'other', 'hash1', nowMs: 1002), 'create: duplicate email refused');
  check((await m.audit()).isEmpty, 'create: refused attempts leave no claims, records or intents');

  m = await fresh();
  final creates = await Future.wait(
    ['uidA', 'uidB', 'uidC', 'uidD'].map((u) => m.create(u, 'samealias', 'h-$u', nowMs: 1000)),
  );
  check(creates.where((r) => r).length == 1, 'create: exactly one of 4 concurrent same-alias creates wins');
  check((await m.audit()).isEmpty, 'create: audit clean after the same-alias race');

  m = await fresh();
  final sameUid = await Future.wait(List.generate(5, (_) => m.create('uidA', 'dbltap', 'hdt', nowMs: 1000)));
  final recs = (await m.at('AllTippers').get() as Map?) ?? const {};
  check(recs.length == 1, 'create: five concurrent taps by one uid create one record (${recs.length})');
  check(sameUid.every((r) => r) || sameUid.any((r) => r), 'create: at least one tap succeeded');
  check((await m.audit()).isEmpty, 'create: audit clean after concurrent taps');

  // ---- 4. abandoned create is detected, reaped after the intent expires
  m = await fresh();
  try {
    await m.create('uidA', 'ghost', 'hghost', nowMs: 1000, crashAfter: 2);
  } on Crash {
    // abandoned: alias and logon claimed, no record
  }
  check((await m.audit()).isNotEmpty, 'abandon: audit flags the orphaned claims');
  check(!await m.create('uidB', 'ghost', 'hother', nowMs: 1500), 'abandon: alias stays reserved while the intent is live');
  check(await m.reap(nowMs: 1500, ttlMs: 60000) == 0, 'abandon: reaper leaves a live intent alone');
  check(await m.reap(nowMs: 100000, ttlMs: 60000) == 1, 'abandon: reaper clears an expired intent');
  check((await m.audit()).isEmpty, 'abandon: audit clean after reaping');
  check(await m.create('uidB', 'ghost', 'hother', nowMs: 100001), 'abandon: alias is usable again after reaping');

  // ---- 5. leases
  m = await fresh();
  check(await m.acquireLease('t1', 'op1', 1000, 5000), 'lease: first holder acquires');
  check(!await m.acquireLease('t1', 'op2', 2000, 5000), 'lease: live lease refused to another owner');
  check(await m.acquireLease('t1', 'op1', 2000, 5000), 'lease: same owner may renew');
  final takeovers = await Future.wait(
    List.generate(6, (i) => m.acquireLease('t1', 'contender$i', 20000, 5000)),
  );
  check(takeovers.where((r) => r).length == 1, 'lease: exactly one of 6 contenders takes over an expired lease');

  // ---- 6. aggregator: older computation finishing last
  m = await fresh();
  Map<String, Object?> computed(int n) => {'homeInterimScore': n, 'basedOnCount': n};
  check(await m.writeCurrentIfNewer('g1', computed(5)), 'aggregator: newer computation written');
  check(!await m.writeCurrentIfNewer('g1', computed(3)), 'aggregator: an older computation finishing last is refused');
  check((await m.at('LS/g1/current/basedOnCount').get()) == 5, 'aggregator: current still reflects 5 entries');

  m = await fresh();
  final order = List.generate(30, (i) => i + 1)..shuffle(Random(7));
  await Future.wait(order.map((n) async {
    await Future<void>.delayed(Duration(milliseconds: Random(n).nextInt(40)));
    await m.writeCurrentIfNewer('g2', computed(n));
  }));
  check((await m.at('LS/g2/current/basedOnCount').get()) == 30,
      'aggregator: 30 computations completing in random order leave the latest');

  await base.remove();
  await db.delete();
  stdout.writeln(failures == 0 ? '\nALL CHECKS PASSED' : '\n$failures CHECK(S) FAILED');
  exitCode = failures == 0 ? 0 : 1;
}
