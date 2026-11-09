import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/claim_moves.dart';
import 'package:dart_functions/identity/claims.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// `unlink-my-account`: detaches the signed-in account from its tipper record,
/// keeping the record and everything on it (name, tips, login address), so the
/// sign-in account can be deleted and the person can later sign up again and be
/// linked back to the same record.
///
/// Why it exists: the app's "delete account" removes only the sign-in account.
/// Left alone, the tipper record keeps pointing at an account that no longer
/// exists, and linking never checks whether an old account is still alive (it
/// treats any other owner as a claim to respect), so signing up again with the
/// same email would be refused. The client calls this first, then deletes the
/// account.
///
/// The records are found from the verified uid alone, never from the request,
/// and from **both sides**: the account's `/AuthIndex` entry and every record
/// whose private or public `authuid` names it. That makes a retry able to
/// finish a call that was cut short at any step: after the index entry has gone
/// the account can no longer be resolved by the index, but the record still
/// names it.
///
/// For each record, under its tipper lease, in this order:
///
/// 1. release the `/AuthIndex` entry (only if it points at this record). This is
///    what grants access, so access ends first;
/// 2. **remove** the private `authuid` (only if it is this account). Linking
///    treats only a *missing* `authuid` as free to take, so it must be removed,
///    not blanked;
/// 3. **blank** the public `authuid` (only if it is this account). It is set to
///    an empty string and never removed, because the 1.4.x client reads it as a
///    non-null string and would fail to parse the tipper list without it. After
///    the purge the public record has no such field, and this step does nothing.
///
/// Every step is a compare-and-set on the value it expects, so a record that was
/// meanwhile linked to someone else is never touched. An account with nothing
/// attached is not an error: the result says `unlinked: false`.
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
        await _detach(database, tipperId, uid, checkpoint);
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
  Checkpoint? checkpoint,
) async {
  // 1. Access ends first.
  await release(database.ref('${paths.authIndexPath}/$uid'), tipperId);
  await checkpoint?.call('unlink:index');

  // 2. The private link goes: removed, because only a missing value is free.
  await database
      .ref('${paths.tipperPrivatePath}/$tipperId/authuid')
      .atomicUpdate((current) => current == uid ? null : keepCurrentValue);
  await checkpoint?.call('unlink:private');

  // 3. The public copy is blanked, never removed: the 1.4.x client needs a string.
  await database
      .ref('${paths.tippersPath}/$tipperId/authuid')
      .atomicUpdate((current) => current == uid ? '' : keepCurrentValue);
}
