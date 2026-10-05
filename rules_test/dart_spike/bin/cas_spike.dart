// Phase 1 spike for DESIGN-database-rules.md D3: prove that a single-location
// compare-and-set "claim" built on firebase_dart's runTransaction is atomic
// under contention, idempotent for the same owner, and releasable.
import 'dart:io';

import 'package:firebase_dart/standalone_database.dart';

/// Claim [ref] for [value]. Succeeds only if empty or already equal.
Future<bool> claim(DatabaseReference ref, String value) async {
  final result = await ref.runTransaction((mutableData) async {
    final current = mutableData.value;
    if (current == null || current == value) {
      mutableData.value = value;
    }
    return mutableData;
  });
  return result.committed && result.dataSnapshot?.value == value;
}

Future<void> release(DatabaseReference ref, String value) async {
  await ref.runTransaction((mutableData) async {
    if (mutableData.value == value) {
      mutableData.value = null;
    }
    return mutableData;
  });
}

void check(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAIL: $message');
    exitCode = 1;
  } else {
    stdout.writeln('ok:   $message');
  }
}

Future<void> main() async {
  final host = Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'] ?? '127.0.0.1:8000';
  final db = StandaloneFirebaseDatabase('http://$host/?ns=demo-dau-rules');
  await db.authenticate('owner'); // emulator admin; production uses the service account
  final root = db.reference().child('CasSpike');
  await root.remove();

  // 1. Contended claim: 25 contenders, exactly one winner.
  final slot = root.child('AuthIndex').child('uid-1');
  final outcomes = await Future.wait(
    List.generate(25, (i) => claim(slot, 'tipper-$i')),
  );
  final winners = outcomes.where((won) => won).length;
  check(winners == 1, 'exactly one of 25 concurrent claims wins (winners=$winners)');
  final owner = await slot.get();
  check(owner is String && owner.startsWith('tipper-'), 'slot holds the winner ($owner)');

  // 2. Idempotent for the same owner (a retried callable).
  check(await claim(slot, owner as String), 'same owner re-claim is idempotent');
  check(!await claim(slot, 'someone-else'), 'different owner is refused');

  // 3. Release only by the owner.
  await release(slot, 'someone-else');
  check(await slot.get() == owner, 'non-owner release is a no-op');
  await release(slot, owner);
  check(await slot.get() == null, 'owner release clears the slot');
  check(await claim(slot, 'tipper-after'), 'slot can be claimed again after release');

  // 4. Two independent slots claimed by contending pairs: link protocol.
  //    record.authuid then AuthIndex[uid]; two uids race for one record.
  final record = root.child('AllTippers').child('t1').child('authuid');
  final index = root.child('AuthIndex');
  Future<bool> link(String uid) async {
    if (!await claim(record, uid)) return false; // step 1: claim the record
    if (!await claim(index.child(uid), 't1')) {
      await release(record, uid); // compensate
      return false;
    }
    return true;
  }

  final linkResults = await Future.wait([link('uidA'), link('uidB'), link('uidC')]);
  check(linkResults.where((r) => r).length == 1, 'only one uid links a contested record');
  final recordOwner = await record.get();
  final indexSnap = await index.get() as Map?;
  check(indexSnap?[recordOwner] == 't1', 'index agrees with the record owner ($recordOwner)');
  check(
    indexSnap!.keys.where((k) => k == 'uidA' || k == 'uidB' || k == 'uidC').length == 1,
    'losers left no index entry',
  );

  await root.remove();
  await db.delete();
}
