import 'dart:convert';

import 'package:dart_functions/identity/keys.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// A Firebase Auth user, reduced to what the backfill needs.
class AuthUser {
  const AuthUser({required this.uid, this.email, this.emailVerified = false});

  final String uid;
  final String? email;
  final bool emailVerified;
}

/// What the backfill reads. Everything is already in memory: the tool never
/// touches the network.
class BackfillInput {
  const BackfillInput({
    required this.database,
    required this.authUsers,
    required this.adminAllowlist,
    this.approvedLinks = const <String, String>{},
    this.approvedAliasOwners = const <String>{},
  });

  /// The whole database as one JSON object (a `firebase database:get /` export).
  final Map<String, Object?> database;

  /// Firebase Auth users by uid. Firebase Auth is the authority on whether an
  /// `authuid` is a real account or a placeholder.
  final Map<String, AuthUser> authUsers;

  /// The Auth uids allowed to administer today (`config/admin-auth-uids.json`).
  final Set<String> adminAllowlist;

  /// Owner-reviewed links from a tipper record to the Firebase account that is
  /// that person, for records whose stored `authuid` is only a placeholder.
  /// Without an entry here a candidate is never linked.
  final Map<String, String> approvedLinks;

  /// Owner-reviewed choices of which record owns a shared alias, as tipper
  /// ids. Without one, the ranking proposes an owner (and a claim already in
  /// the database is kept), but a proposal is not an approval.
  final Set<String> approvedAliasOwners;
}

/// What a finding is about. Each one lists tipper ids (or index keys) only, never names or addresses.
///
/// Two different questions are asked of a plan. Is it safe to apply and is the
/// backfill in place? Only [blocking] findings say no. Are the identities ready
/// for the R2 cutover? [blocksCutover] findings say not yet: they are accepted
/// during the backfill, because nothing is lost by leaving them for now, but
/// they must be resolved before real people depend on the new rules.
enum FindingKind {
  /// Two records hold the same real account. Neither is indexed.
  duplicateAccountUid(blocking: false, blocksCutover: true),

  /// Two or more records share a normalised alias. One record claims it.
  aliasShared(blocking: false, blocksCutover: true),

  /// A record's name cannot be an alias (blank, too long, or only symbols).
  aliasUnusable(blocking: false),

  /// Two or more records share a login email. Nobody claims it. A missing
  /// claim is not by itself a refusal: the link callable must find every
  /// candidate by scanning and reject an ambiguous match (section 6b, M4b).
  logonShared(blocking: false, blocksCutover: true),

  /// Two or more records share a contact email.
  emailShared(blocking: false, blocksCutover: true),

  /// One record's login email is another record's contact email, so a person
  /// arriving with that address matches two records.
  loginMatchesOtherEmail(blocking: false, blocksCutover: true),

  /// A record has an admin role but its account is not on the allowlist, is
  /// not an account at all, or is shared. Under the AuthIndex rules it would
  /// become an administrator, so this must be settled first.
  adminNotOnAllowlist(blocking: true),

  /// An allowlisted account has no admin record to match.
  allowlistedUidWithoutAdminRecord(blocking: true),

  /// An approved link is not usable: the account does not exist, the record
  /// already holds a different real account, or another record (or another
  /// approved link) already holds that account, which would make a duplicate.
  approvedLinkRejected(blocking: true),

  /// An approved link names a record that does not exist.
  approvedLinkUnknownTipper(blocking: true),

  /// An approved alias owner is not a record that shares an alias, or two
  /// records of one shared alias were both approved.
  approvedAliasRejected(blocking: true),

  /// An entry already in the database is not what the data now calls for
  /// (the drift report, or a pass-1 re-run).
  existingDiffers(blocking: true),

  /// An index or private entry exists that no record calls for any more.
  unexpectedEntry(blocking: true),

  /// A record that is not an account or a placeholder: it has no `authuid`.
  noAuthuid(blocking: false);

  const FindingKind({required this.blocking, this.blocksCutover = false});

  /// Whether the patch must not be applied until this is settled.
  final bool blocking;

  /// Whether this must be resolved before the R2 cutover, though it does not
  /// stop the backfill.
  final bool blocksCutover;
}

/// One class of problem and where it was found.
class Finding {
  const Finding(this.kind, this.subjects);

  final FindingKind kind;

  /// Tipper ids, groups of tipper ids joined with a comma, or database paths.
  final List<String> subjects;
}

/// The result of planning.
class BackfillPlan {
  const BackfillPlan({
    required this.writes,
    required this.findings,
    required this.counts,
  });

  /// A multi-path update (`path -> value`) that makes the database match the
  /// plan. It only ever fills empty places, with one exception: the `authuid`
  /// of an owner-approved link. Keys are sorted so that two plans of the same
  /// data are byte-identical.
  final Map<String, Object?> writes;

  final List<Finding> findings;

  /// Summary figures, by name.
  final Map<String, int> counts;

  bool get hasBlockingFindings =>
      findings.any((finding) => finding.kind.blocking);

  /// True when the database already matches the plan and nothing blocks it.
  /// This is the backfill check. It says nothing about readiness for R2:
  /// findings that [FindingKind.blocksCutover] can remain.
  bool get isClean => writes.isEmpty && !hasBlockingFindings;

  /// Findings that must be resolved before the R2 cutover (and that do not
  /// block the backfill).
  bool get hasCutoverBlockers =>
      findings.any((finding) => finding.kind.blocksCutover);

  /// The stricter check for the cutover: the backfill is in place and every
  /// duplicate and ambiguity has been resolved.
  bool get isCutoverReady => isClean && !hasCutoverBlockers;
}

/// Plans the identity backfill, or checks it: the same function does both.
///
/// It computes the full set of entries the current records call for (the
/// private record, the `AuthIndex`, `AliasIndex` and `LogonIndex` claims and the
/// audited placeholders), then compares that with what the database holds. A
/// place that is empty becomes a write. A place that holds something else is a
/// finding and is never overwritten. So the first run is the backfill; a run
/// after it is the verifier, and a later run is the drift report.
BackfillPlan planIdentityBackfill(BackfillInput input) {
  final tippers = _objectAt(input.database, tippersPathKey);
  final currentComp = _textAt(input.database, ['AppConfig', 'currentDAUComp']);
  final currentTips = currentComp == null
      ? const <String, Object?>{}
      : _objectAt(
          _objectAt(input.database, _root(paths.tipsPathRoot)),
          currentComp,
        );

  final findings = <FindingKind, List<String>>{};
  void note(FindingKind kind, String subject) =>
      (findings[kind] ??= <String>[]).add(subject);

  final records = <String, _Record>{};
  for (final id in tippers.keys.toList()..sort()) {
    final raw = tippers[id];
    if (raw is! Map) {
      continue;
    }
    records[id] = _Record(
      id,
      Map<String, Object?>.from(raw),
      tipCount: _objectAt(currentTips, id).length,
    );
  }

  // Owner-approved links first, because they decide which uid a record holds.
  // A link may never create a duplicate: the account must not already be held
  // by another record, nor be the target of another approved link.
  final storedHolders = <String, List<String>>{};
  for (final record in records.values) {
    final stored = record.storedAuthuid;
    if (stored != null) {
      (storedHolders[stored] ??= <String>[]).add(record.id);
    }
  }
  final publicWrites = <String, Object?>{};
  for (final entry in input.approvedLinks.entries) {
    final record = records[entry.key];
    if (record == null) {
      note(FindingKind.approvedLinkUnknownTipper, entry.key);
      continue;
    }
    final stored = record.storedAuthuid;
    final account = input.authUsers[entry.value];
    final storedIsOtherAccount =
        stored != null &&
        stored != entry.value &&
        input.authUsers.containsKey(stored);
    final heldByAnotherRecord = (storedHolders[entry.value] ?? const <String>[])
        .any((holder) => holder != record.id);
    final targetedTwice =
        input.approvedLinks.values.where((uid) => uid == entry.value).length >
        1;
    if (account == null ||
        storedIsOtherAccount ||
        heldByAnotherRecord ||
        targetedTwice) {
      note(FindingKind.approvedLinkRejected, entry.key);
      continue;
    }
    record.linkedUid = entry.value;
    if (stored != entry.value) {
      publicWrites['$tippersPathKey/${record.id}/authuid'] = entry.value;
    }
  }

  // What is each record's uid: a real account, a placeholder, or nothing.
  final accountHolders = <String, List<_Record>>{};
  for (final record in records.values) {
    final uid = record.effectiveAuthuid;
    if (uid == null) {
      note(FindingKind.noAuthuid, record.id);
    } else if (input.authUsers.containsKey(uid)) {
      record.isAccount = true;
      (accountHolders[uid] ??= <_Record>[]).add(record);
    }
  }
  final indexedUids = <String, String>{};
  for (final entry in accountHolders.entries) {
    if (entry.value.length > 1) {
      note(
        FindingKind.duplicateAccountUid,
        (entry.value.map((record) => record.id).toList()..sort()).join(','),
      );
      continue;
    }
    final record = entry.value.single;
    if (isValidRtdbKey(entry.key) && !record.isAnonymous) {
      indexedUids[entry.key] = record.id;
    }
  }

  // Administrators must match the allowlist both ways.
  final allowlistedWithRecord = <String>{};
  for (final record in records.values.where((record) => record.isAdmin)) {
    final uid = record.effectiveAuthuid;
    final soleAccount = uid != null && indexedUids[uid] == record.id;
    if (soleAccount && input.adminAllowlist.contains(uid)) {
      allowlistedWithRecord.add(uid);
    } else {
      note(FindingKind.adminNotOnAllowlist, record.id);
    }
  }
  for (final uid in input.adminAllowlist.toList()..sort()) {
    if (!allowlistedWithRecord.contains(uid)) {
      note(FindingKind.allowlistedUidWithoutAdminRecord, uid);
    }
  }

  // Alias claims: one ranked winner per normalised alias; the rest are listed.
  final aliasClaims = <String, String>{};
  final aliasGroups = <String, List<_Record>>{};
  for (final record in records.values) {
    final name = record.name;
    if (record.isAnonymous || name == null) {
      continue;
    }
    if (!isValidAlias(name)) {
      note(FindingKind.aliasUnusable, record.id);
      continue;
    }
    (aliasGroups[aliasIndexKey(name)] ??= <_Record>[]).add(record);
  }
  final sharedAliasMembers = <String>{};
  for (final entry in aliasGroups.entries) {
    final group = entry.value..sort(_byClaimPriority);
    if (group.length > 1) {
      sharedAliasMembers.addAll(group.map((record) => record.id));
    }
    final approved = group
        .where((record) => input.approvedAliasOwners.contains(record.id))
        .toList();
    final existing = _valueAtPath(
      input.database,
      '$aliasIndexPathKey/${entry.key}',
    );
    final _Record winner;
    final String basis;
    if (approved.length > 1) {
      note(
        FindingKind.approvedAliasRejected,
        approved.map((record) => record.id).join(','),
      );
      winner = group.first;
      basis = 'ranking';
    } else if (approved.length == 1) {
      winner = approved.single;
      basis = 'approved';
    } else if (existing is String &&
        group.any((record) => record.id == existing)) {
      // A claim already made is kept, so the tip counts changing later cannot
      // flip an owner the owner has seen.
      winner = group.firstWhere((record) => record.id == existing);
      basis = 'existing claim';
    } else {
      winner = group.first;
      basis = 'ranking';
    }
    aliasClaims[entry.key] = winner.id;
    if (group.length > 1) {
      final ordered = [
        winner,
        ...group.where((record) => record.id != winner.id),
      ];
      note(
        FindingKind.aliasShared,
        '${ordered.map((record) => record.id).join(',')} [$basis]',
      );
    }
  }
  for (final id in input.approvedAliasOwners.toList()..sort()) {
    if (!sharedAliasMembers.contains(id)) {
      note(FindingKind.approvedAliasRejected, id);
    }
  }

  // Login email claims: only an unshared one is claimed.
  final logonClaims = <String, String>{};
  final logonGroups = <String, List<_Record>>{};
  for (final record in records.values) {
    final logon = record.logon;
    if (record.isAnonymous || logon == null || normaliseEmail(logon).isEmpty) {
      continue;
    }
    (logonGroups[logonIndexKey(logon)] ??= <_Record>[]).add(record);
  }
  for (final entry in logonGroups.entries) {
    final group = entry.value..sort((a, b) => a.id.compareTo(b.id));
    if (group.length == 1) {
      logonClaims[entry.key] = group.single.id;
    } else {
      note(FindingKind.logonShared, group.map((record) => record.id).join(','));
    }
  }

  // Contact emails: a shared one, or a login that is another record's contact,
  // makes a person arriving with that address match more than one record.
  final emailGroups = <String, List<_Record>>{};
  for (final record in records.values) {
    final email = record.email;
    if (record.isAnonymous || email == null || normaliseEmail(email).isEmpty) {
      continue;
    }
    (emailGroups[normaliseEmail(email)] ??= <_Record>[]).add(record);
  }
  for (final group in emailGroups.values.where((group) => group.length > 1)) {
    note(FindingKind.emailShared, group.map((record) => record.id).join(','));
  }
  final loginMatches = <String>{};
  for (final record in records.values) {
    final logon = record.logon;
    if (record.isAnonymous || logon == null) {
      continue;
    }
    final others = (emailGroups[normaliseEmail(logon)] ?? const <_Record>[])
        .where((other) => other.id != record.id);
    if (others.isNotEmpty) {
      loginMatches.add(
        ([record.id, ...others.map((other) => other.id)]..sort()).join(','),
      );
    }
  }
  for (final group in loginMatches) {
    note(FindingKind.loginMatchesOtherEmail, group);
  }

  // The desired entries, then the comparison with what is there.
  final desired = <String, Object?>{};
  for (final record in records.values) {
    desired['$tipperPrivatePathKey/${record.id}'] = record.privateFields();
    final placeholder = record.placeholder;
    if (placeholder != null && !record.isAccount) {
      desired['$placeholdersPathKey/${record.id}'] = placeholder;
    }
  }
  for (final entry in indexedUids.entries) {
    desired['$authIndexPathKey/${entry.key}'] = entry.value;
  }
  for (final entry in aliasClaims.entries) {
    desired['$aliasIndexPathKey/${entry.key}'] = entry.value;
  }
  for (final entry in logonClaims.entries) {
    desired['$logonIndexPathKey/${entry.key}'] = entry.value;
  }

  final writes = <String, Object?>{...publicWrites};
  var alreadyPresent = 0;
  for (final entry in desired.entries) {
    final actual = _valueAtPath(input.database, entry.key);
    if (actual == null) {
      writes[entry.key] = entry.value;
    } else if (_sameValue(actual, entry.value)) {
      alreadyPresent += 1;
    } else {
      note(FindingKind.existingDiffers, entry.key);
    }
  }
  for (final root in [
    tipperPrivatePathKey,
    authIndexPathKey,
    aliasIndexPathKey,
    logonIndexPathKey,
    placeholdersPathKey,
  ]) {
    for (final key in _objectAt(input.database, root).keys) {
      if (!desired.containsKey('$root/$key')) {
        note(FindingKind.unexpectedEntry, '$root/$key');
      }
    }
  }

  final sortedWrites = <String, Object?>{
    for (final key in writes.keys.toList()..sort()) key: writes[key],
  };
  return BackfillPlan(
    writes: sortedWrites,
    findings: [
      for (final kind in FindingKind.values)
        if (findings[kind] != null) Finding(kind, findings[kind]!..sort()),
    ],
    counts: {
      'tippers': records.length,
      'accounts': records.values.where((record) => record.isAccount).length,
      'placeholders': records.values
          .where((record) => !record.isAccount && record.placeholder != null)
          .length,
      'authIndexClaims': indexedUids.length,
      'aliasClaims': aliasClaims.length,
      'logonClaims': logonClaims.length,
      'writes': sortedWrites.length,
      'alreadyPresent': alreadyPresent,
      'approvedLinks': publicWrites.length,
    },
  );
}

/// The root names used in the multi-path updates (the shared paths without
/// their leading slash).
final String tippersPathKey = _root(paths.tippersPath);
final String tipperPrivatePathKey = _root(paths.tipperPrivatePath);
final String authIndexPathKey = _root(paths.authIndexPath);
final String aliasIndexPathKey = _root(paths.aliasIndexPath);
final String logonIndexPathKey = _root(paths.logonIndexPath);
final String placeholdersPathKey = _root(paths.placeholdersPath);

String _root(String path) => path.substring(1);

/// Who should hold a shared alias: a real account first, then the tipper with
/// the most tips in the current comp, then the most paid comps, then the lowest
/// id (so the answer never depends on the order of the data).
int _byClaimPriority(_Record a, _Record b) {
  if (a.isAccount != b.isAccount) {
    return a.isAccount ? -1 : 1;
  }
  if (a.tipCount != b.tipCount) {
    return b.tipCount.compareTo(a.tipCount);
  }
  if (a.paidCompCount != b.paidCompCount) {
    return b.paidCompCount.compareTo(a.paidCompCount);
  }
  return a.id.compareTo(b.id);
}

class _Record {
  _Record(this.id, this.fields, {required this.tipCount});

  final String id;
  final Map<String, Object?> fields;
  final int tipCount;
  String? linkedUid;
  bool isAccount = false;

  String? get storedAuthuid => _text(fields['authuid']);

  /// The approved uid if the owner linked this record, else what is stored.
  String? get effectiveAuthuid => linkedUid ?? storedAuthuid;

  /// The stored `authuid` when it is not an account, kept exactly as written.
  String? get placeholder => linkedUid == null ? storedAuthuid : null;

  String? get name =>
      fields['name'] is String ? fields['name'] as String : null;
  String? get logon => _text(fields['logon']);
  String? get email => _text(fields['email']);
  bool get isAnonymous => fields['isAnonymous'] == true;
  bool get isAdmin => fields['tipperRole'] == TipperRole.admin.name;

  int get paidCompCount {
    final comps = fields['compsParticipatedIn'];
    if (comps is List) {
      return comps.length;
    }
    return comps is Map ? comps.length : 0;
  }

  /// The seven private fields exactly as stored, with the approved uid in
  /// place of a placeholder.
  Map<String, Object?> privateFields() {
    return <String, Object?>{
      for (final field in tipperPrivateFieldNames)
        if (field == 'authuid' && linkedUid != null)
          field: linkedUid
        else if (fields.containsKey(field))
          field: fields[field],
    };
  }
}

String? _text(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

Map<String, Object?> _objectAt(Map<String, Object?> parent, String key) {
  final value = parent[key];
  return value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
}

String? _textAt(Map<String, Object?> root, List<String> path) {
  Object? node = root;
  for (final segment in path) {
    node = node is Map ? node[segment] : null;
  }
  return node is String && node.isNotEmpty ? node : null;
}

Object? _valueAtPath(Map<String, Object?> root, String path) {
  Object? node = root;
  for (final segment in path.split('/')) {
    node = node is Map ? node[segment] : null;
  }
  return node;
}

/// Equality of two stored values regardless of key order.
bool _sameValue(Object? a, Object? b) => _canonical(a) == _canonical(b);

String _canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final key in (value.keys.map((k) => k.toString()).toList()..sort()))
        key: _sorted(value[key]),
    };
  }
  if (value is List) {
    return value.map(_sorted).toList();
  }
  return value;
}
