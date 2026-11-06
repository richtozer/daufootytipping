import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/claims.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/linked_caller.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// `register-device-token`: moves a push token to the signed-in tipper.
///
/// A token belongs to one device, so it belongs to one tipper. Writing the
/// caller's entry atomically is not enough: two callers that both scanned
/// before either wrote would each add it. Ownership is therefore settled by a
/// compare-and-set on `/TokenOwners/{token}`, which the last writer wins:
///
/// 1. Make the caller the owner.
/// 2. Remove the token from every other tipper. This also clears holders that
///    registered directly (a 1.4.x client does not know the index).
/// 3. Write the caller's entry.
/// 4. Read the owner again. If it is no longer the caller, a later registration
///    took the token, so remove the caller's own entry.
///
/// The result is that two callers registering the same token at once end with
/// exactly one holder, the last to claim ownership.
///
/// **Accepted limitation:** knowing a push token does not prove the caller
/// controls that device. A signed-in tipper who learned another's token could
/// register it and receive that tipper's notifications. This is no weaker than
/// before (a 1.4.x client can write the token directly) and the effect is
/// limited to notifications.
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

  final ownerRef = database.ref('${paths.tokenOwnersPath}/$token');
  await ownerRef.atomicUpdate(
    (current) => current == tipperId ? keepCurrentValue : tipperId,
  );
  await checkpoint?.call('token:owner');

  final others = await _otherHolders(database, token, tipperId);
  if (others.isNotEmpty) {
    await database.ref('/').update(<Object?, Object?>{
      for (final other in others)
        '${_root(paths.tokensPath)}/$other/$token': null,
    });
  }
  await checkpoint?.call('token:others-removed');

  final entryRef = database.ref('${paths.tokensPath}/$tipperId/$token');
  await entryRef.set(
    DateTime.fromMillisecondsSinceEpoch(clock(), isUtc: true).toIso8601String(),
  );
  await checkpoint?.call('token:entry');

  if ((await ownerRef.once()).value != tipperId) {
    await entryRef.remove();
  }
  return RegisterDeviceTokenResult(tipperId: tipperId);
}

/// `unregister-device-token`: removes a push token from the signed-in tipper.
///
/// It only ever touches the caller's own entry, and gives up the ownership
/// record only if it still names the caller. A delayed unregister from a
/// former owner therefore cannot disturb whoever registered the token since.
/// (A client that sends its own unregister and register for one token out of
/// order defeats itself; the client is expected to serialise those.)
Future<UnregisterDeviceTokenResult> unregisterDeviceToken({
  required RestDatabase database,
  required CallerToken caller,
  required DeviceTokenRequest request,
  Checkpoint? checkpoint,
}) async {
  final token = _validToken(request.token);
  final tipperId = await requireLinkedTipper(database, caller.uid);

  await release(database.ref('${paths.tokenOwnersPath}/$token'), tipperId);
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

String _root(String path) => path.substring(1);
