import 'dart:math';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/linked_caller.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// `register-device-token`: moves a push token to the signed-in tipper.
///
/// A token belongs to one device, so it belongs to one tipper. Two callers can
/// register one token at once, and a caller can be paused for any length of
/// time between steps, so ownership is ordered, not just written:
///
/// * `/TokenOwners/{token}` holds `{owner, seq}`. Taking the token is a
///   compare-and-set that gives the caller the next `seq` for that token, so
///   `seq` is the order in which registrations were made.
/// * A tipper's entry `/AllTippersTokens/{tipper}/{token}` has as its value the
///   time of the registration that wrote it, to the microsecond, in UTC. That is
///   still an ordinary ISO time (the 30-day stale-token cleanup parses it) and
///   it *is* the `seq`, so an entry says which registration it belongs to.
///
/// With that order, every step is safe whatever the others are doing:
///
/// 1. Take the token (compare-and-set), getting `seq`.
/// 2. Remove the token from every other tipper, **but only an entry that is not
///    newer than this registration**. An entry written by a later registration
///    is left alone: a caller that was paused after step 1 must not delete the
///    entry of the registration that has since won.
/// 3. Write the caller's own entry, again only if no newer one is there.
/// 4. Read the ownership again. If its `seq` is no longer this registration's,
///    a later registration took the token, so remove this caller's own entry
///    (only if it still holds this registration's value).
///
/// So two callers registering one token at once end with exactly one holder, the
/// later registration, however their steps interleave. Entries written directly
/// by a 1.4.x client (a local time with no `Z`) carry no order and are always
/// replaceable.
///
/// **Accepted limitation:** knowing a push token does not prove the caller
/// controls that device. The token still identifies the original device, so a
/// signed-in tipper who learned another's token cannot make notifications arrive
/// anywhere new. What they can do is change which account that device is sent
/// notifications for: the device's owner could stop receiving their reminders,
/// and the device could be sent the other account's. This is no weaker than
/// before (a 1.4.x client can write the token directly) and is limited to
/// notifications.
Future<RegisterDeviceTokenResult> registerDeviceToken({
  required RestDatabase database,
  required CallerToken caller,
  required DeviceTokenRequest request,
  int Function()? nowMs,
  Checkpoint? checkpoint,
}) async {
  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final token = _validToken(request.token);
  final tipperId = await requireLinkedTipper(database, caller.uid);

  // 1. Take the token and learn this registration's place in the order.
  final ownerRef = database.ref('${paths.tokenOwnersPath}/$token');
  var seq = 0;
  await ownerRef.atomicUpdate((current) {
    seq = max(clock() * 1000, _seqOf(current) + 1);
    return <String, Object?>{'owner': tipperId, 'seq': seq};
  });
  final value = _entryValue(seq);
  await checkpoint?.call('token:owner');

  // 2. Clear the older holders. A newer entry is not ours to remove.
  for (final other in await _otherHolders(database, token, tipperId)) {
    await database
        .ref('${paths.tokensPath}/$other/$token')
        .atomicUpdate(
          (current) => current == null || _entrySeq(current) > seq
              ? keepCurrentValue
              : null,
        );
  }
  await checkpoint?.call('token:others-removed');

  // 3. Write the caller's entry, unless a newer registration of its own is there.
  final entryRef = database.ref('${paths.tokensPath}/$tipperId/$token');
  await entryRef.atomicUpdate(
    (current) => _entrySeq(current) > seq ? keepCurrentValue : value,
  );
  await checkpoint?.call('token:entry');

  // 4. A later registration may have taken the token meanwhile.
  if (_seqOf((await ownerRef.once()).value) != seq) {
    await entryRef.atomicUpdate(
      (current) => current == value ? null : keepCurrentValue,
    );
  }
  return RegisterDeviceTokenResult(tipperId: tipperId);
}

/// `unregister-device-token`: removes a push token from the signed-in tipper.
///
/// It only ever touches the caller's own entry, and gives up the ownership
/// record only if it still names the caller. The record keeps its `seq` (as a
/// tombstone with no owner), so the order of registrations survives. A delayed
/// unregister from a former owner therefore cannot disturb whoever registered
/// the token since. (A client that sends its own unregister and register for
/// one token out of order defeats itself; the client is expected to serialise
/// those.)
Future<UnregisterDeviceTokenResult> unregisterDeviceToken({
  required RestDatabase database,
  required CallerToken caller,
  required DeviceTokenRequest request,
  Checkpoint? checkpoint,
}) async {
  final token = _validToken(request.token);
  final tipperId = await requireLinkedTipper(database, caller.uid);

  await database.ref('${paths.tokenOwnersPath}/$token').atomicUpdate((current) {
    if (current is Map && current['owner'] == tipperId) {
      return <String, Object?>{'seq': _seqOf(current)};
    }
    return keepCurrentValue;
  });
  await checkpoint?.call('untoken:released');

  final result = await database
      .ref('${paths.tokensPath}/$tipperId/$token')
      .atomicUpdate((current) => current == null ? keepCurrentValue : null);
  return UnregisterDeviceTokenResult(removed: result.applied);
}

/// A token is used as a database key, so it must be one.
String _validToken(String token) {
  if (!isValidRtdbKey(token) || token.length > maxDeviceTokenLength) {
    throw InvalidArgumentError(
      'That device token cannot be used.',
      reason: identityReasonInvalidToken,
    );
  }
  return token;
}

/// The order of the registration an ownership record last recorded, or 0.
int _seqOf(Object? ownership) {
  if (ownership is Map && ownership['seq'] is num) {
    return (ownership['seq'] as num).toInt();
  }
  return 0;
}

/// The value of a token entry for the registration with this [seq]: its time,
/// to the microsecond, in UTC.
String _entryValue(int seq) =>
    DateTime.fromMicrosecondsSinceEpoch(seq, isUtc: true).toIso8601String();

/// The order an entry carries, or 0 if it carries none: a value written by a
/// callable is a UTC time (it ends in `Z`); one written directly by a 1.4.x
/// client is a local time with no zone.
int _entrySeq(Object? entryValue) {
  if (entryValue is String && entryValue.endsWith('Z')) {
    return DateTime.tryParse(entryValue)?.microsecondsSinceEpoch ?? 0;
  }
  return 0;
}

/// The tippers other than [tipperId] that hold [token]. One read of the whole
/// token tree (about sixty tippers).
Future<List<String>> _otherHolders(
  RestDatabase database,
  String token,
  String tipperId,
) async {
  final all = (await database.ref(paths.tokensPath).once()).value;
  if (all is! Map) {
    return const <String>[];
  }
  return <String>[
    for (final entry in all.entries)
      if (entry.key.toString() != tipperId &&
          entry.value is Map &&
          (entry.value as Map).containsKey(token))
        entry.key.toString(),
  ]..sort();
}
