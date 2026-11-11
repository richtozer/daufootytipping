import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/claim_moves.dart';
import 'package:dart_functions/identity/claims.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/tipper_shapes.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// `unlink-my-account`: detaches the signed-in account from its tipper record and
/// **anonymises** the record, so the sign-in account can then be deleted without
/// leaving the person's details behind. The tips, scores and competition
/// standing stay (so nobody else's results change); what says who the person was
/// goes.
///
/// Why it exists: the app's "delete account" removes only the sign-in account.
/// Left alone, the tipper record keeps pointing at an account that no longer
/// exists, still holding the person's name, login email and photo, and linking
/// never checks whether an old account is still alive (it treats any other owner
/// as a claim to respect), so signing up again with the same email would be
/// refused. The client calls this first, then deletes the account.
///
/// What is removed: the private `email` and `logon`, the public `photoURL` and
/// legacy `email` and `logon`; the public name becomes [deletedTipperName]; the
/// claims on the old name and login in the alias and login indexes are released
/// (so the same email signs up as a new tipper, and the name can be taken again).
/// The private record gains `accountDeletedUTC` so that an administrator can see
/// what happened. What stays: the tips, the paid competitions, the role, the
/// account's creation and last sign-in times, and the Firestore tip log, which
/// is not touched here.
///
/// The records are found from the verified uid alone, never from the request,
/// and from **both sides**: the account's `/AuthIndex` entry and every record
/// whose private or public half names it. Only a record that **names this
/// account** is anonymised; one that was linked to someone else in the meantime
/// is never touched. That makes a retry able to finish a call that was cut short
/// at any step, because the account id is removed **last**: until then the record
/// still names the account and is found again.
///
/// For each record, under its tipper lease, in this order:
///
/// 1. release the `/AuthIndex` entry (only if it points at this record). This is
///    what grants access, so access ends first;
/// 2. release the alias and login claims, while the record still holds the name
///    and login they are made from (each only if it is held by this record);
/// 3. remove the private `email` and `logon`, and set `accountDeletedUTC` (once:
///    a retry keeps the first time);
/// 4. rename the public record and remove its photo and legacy contact fields;
/// 5. the private link goes: **removed**, because only a missing value is free;
/// 6. the public copy is **blanked**, never removed: the 1.4.x client needs a
///    string. After the purge the public record has no such field, and this step
///    does nothing.
///
/// Every step is idempotent or a compare-and-set on the value it expects. An
/// account with nothing attached is not an error: the result says
/// `unlinked: false`.
Future<UnlinkMyAccountResult> unlinkMyAccount({
  required RestDatabase database,
  required CallerToken caller,
  required Admission admission,
  int Function()? nowMs,
  Checkpoint? checkpoint,
}) async {
  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final uid = caller.uid;
  if (!isValidRtdbKey(uid)) {
    throw InvalidArgumentError('This account cannot be used.');
  }

  final tipperIds = await _recordsAttachedTo(database, uid);
  for (final tipperId in tipperIds) {
    await withTipperLease(
      database,
      tipperId: tipperId,
      operationId: admission.operationId,
      nowMs: clock,
      body: () async {
        // Finish what a crashed earlier request left on this record first.
        await finishPendingClaimMove(
          database,
          tipperId,
          admission.config,
          checkpoint,
        );
        await _detach(database, tipperId, uid, clock(), checkpoint);
      },
    );
  }
  return UnlinkMyAccountResult(unlinked: tipperIds.isNotEmpty);
}

/// The ids of every record this account is attached to: its index entry, and
/// any record whose private or public half names it.
Future<List<String>> _recordsAttachedTo(
  RestDatabase database,
  String uid,
) async {
  final indexed =
      (await database.ref('${paths.authIndexPath}/$uid').once()).value;
  final publicRecords = (await database.ref(paths.tippersPath).once()).value;
  final privateRecords =
      (await database.ref(paths.tipperPrivatePath).once()).value;

  final ids = <String>{
    if (indexed is String && indexed.isNotEmpty) indexed,
    ..._idsNaming(publicRecords, uid),
    ..._idsNaming(privateRecords, uid),
  };
  return ids.toList()..sort();
}

Iterable<String> _idsNaming(Object? records, String uid) sync* {
  if (records is! Map) {
    return;
  }
  for (final entry in records.entries) {
    final record = entry.value;
    if (record is Map && record['authuid'] == uid) {
      yield entry.key.toString();
    }
  }
}

Future<void> _detach(
  RestDatabase database,
  String tipperId,
  String uid,
  int nowMs,
  Checkpoint? checkpoint,
) async {
  // 1. Access ends first.
  await release(database.ref('${paths.authIndexPath}/$uid'), tipperId);
  await checkpoint?.call('unlink:index');

  final publicRef = database.ref('${paths.tippersPath}/$tipperId');
  final privateRef = database.ref('${paths.tipperPrivatePath}/$tipperId');
  final publicRecord = (await publicRef.once()).value;
  final privateRecord = (await privateRef.once()).value;

  // Only a record that names this account is the person's to anonymise. The
  // index entry alone does not make it theirs: the record may since have been
  // linked to someone else.
  if (_names(privateRecord, uid) || _names(publicRecord, uid)) {
    // 2. The claims go while the record still holds what they are made from.
    await _releaseClaims(database, tipperId, publicRecord, privateRecord);
    await checkpoint?.call('unlink:claims');

    // 3. What says who the person was leaves the private record, and what
    // happened is written down for the administrators.
    // (Only a record that exists: nothing is created here.)
    if (privateRecord is Map) {
      await privateRef.child('email').remove();
      await privateRef.child('logon').remove();
      await privateRef
          .child(tipperAccountDeletedField)
          .atomicUpdate(
            (current) => current == null ? stampOf(nowMs) : keepCurrentValue,
          );
    }
    await checkpoint?.call('unlink:private-identity');

    // 4. The public record keeps only what the competition needs: a name that
    // says nothing, and the paid competitions.
    if (publicRecord is Map) {
      await publicRef.child('name').set(deletedTipperName);
      await publicRef.child('photoURL').remove();
      await publicRef.child('email').remove();
      await publicRef.child('logon').remove();
    }
    await checkpoint?.call('unlink:public-identity');
  }

  // 5. The private link goes: removed, because only a missing value is free.
  await privateRef
      .child('authuid')
      .atomicUpdate((current) => current == uid ? null : keepCurrentValue);
  await checkpoint?.call('unlink:private');

  // 6. The public copy is blanked, never removed: the 1.4.x client needs a string.
  await publicRef
      .child('authuid')
      .atomicUpdate((current) => current == uid ? '' : keepCurrentValue);
}

bool _names(Object? record, String uid) =>
    record is Map && record['authuid'] == uid;

/// Releases the alias claim (from the public name) and the login claims (from
/// the private, then the public, login and email) that [tipperId] holds. Each
/// release is owner-checked, so a claim held by anyone else is not touched, and a
/// value that cannot be a key is skipped.
Future<void> _releaseClaims(
  RestDatabase database,
  String tipperId,
  Object? publicRecord,
  Object? privateRecord,
) async {
  final name = publicRecord is Map ? publicRecord['name'] : null;
  if (name is String && isValidAlias(name)) {
    await release(
      database.ref('${paths.aliasIndexPath}/${aliasIndexKey(name)}'),
      tipperId,
    );
  }
  final addresses = <String>{
    for (final record in <Object?>[privateRecord, publicRecord])
      if (record is Map)
        for (final field in const <String>['logon', 'email'])
          if (record[field] is String &&
              (record[field] as String).trim().isNotEmpty)
            logonIndexKey(record[field] as String),
  };
  for (final key in addresses) {
    await release(database.ref('${paths.logonIndexPath}/$key'), tipperId);
  }
}
