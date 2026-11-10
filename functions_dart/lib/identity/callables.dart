import 'dart:convert';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admin_merge_tippers.dart';
import 'package:dart_functions/identity/admin_update_tipper.dart';
import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/device_tokens.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/handler_deadline.dart';
import 'package:dart_functions/identity/link_or_create.dart';
import 'package:dart_functions/identity/unlink_account.dart';
import 'package:dart_functions/identity/update_alias.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:firebase_functions/firebase_functions.dart'
    show
        CallableOptions,
        CallableRequest,
        CallableResult,
        EnforceAppCheck,
        Firebase,
        Region,
        SupportedRegion,
        TimeoutSeconds;

/// Options of the four identity callables: App Check is enforced (a request
/// from anything but the app is refused before the handler runs), and the
/// 60-second timeout is the one the admission wrapper's drain assumes
/// (`mutatingCallableTimeout`).
const CallableOptions identityCallableOptions = CallableOptions(
  region: Region(SupportedRegion.asiaSoutheast1),
  timeoutSeconds: TimeoutSeconds(60),
  enforceAppCheck: EnforceAppCheck(true),
);

/// Opens the database a request works on. Called once per request: each
/// request has its own handle, so the writes the admission wrapper waits for
/// before clearing its marker are that request's own and nobody else's.
typedef IdentityDatabaseOpener = Future<RestDatabase> Function();

/// Registers `link-or-create-tipper`, `update-tipper-alias`,
/// `register-device-token`, `unregister-device-token`, `unlink-my-account`,
/// `admin-update-tipper` and `admin-merge-tippers` (DESIGN-database-rules-phase4.md, sections 6f and 6h).
/// The admin callables accept the validated administrators ([requireAdmin]).
///
/// Every one of them:
///
/// 1. refuses a caller with no verified sign-in (App Check and the ID token
///    are checked by the runtime before this code runs, so `request.auth` is
///    null only for a call that sent no ID token);
/// 2. reads the request strictly, refusing a malformed one before touching the
///    database;
/// 3. runs as an admitted mutating request, so the server mode (off, pilot,
///    freeze and the rest) is honoured and a mode change can drain it;
/// 4. gives the handler a deadline, [handlerDeadline], after which it stops at
///    its next step.
///
/// The target tipper is never taken from the request. It comes from the
/// verified ID token alone.
///
/// The endpoint ids are the deployed service names that the client calls, so
/// they are the shared constants and are spelled out verbatim here.
void registerIdentityCallables(
  Firebase firebase, {
  required IdentityDatabaseOpener openDatabase,
  Duration handlerDeadline = handlerSoftDeadline,
}) {
  firebase.https.onCall(
    name: linkOrCreateTipperEndpoint,
    options: identityCallableOptions,
    (request, response) => _serve<LinkOrCreateTipperRequest>(
      request,
      callable: linkOrCreateTipperEndpoint,
      openDatabase: openDatabase,
      deadline: handlerDeadline,
      parse: LinkOrCreateTipperRequest.fromJson,
      handle: (call) async => (await linkOrCreateTipper(
        database: call.database,
        caller: call.caller,
        request: call.request,
        admission: call.admission,
        checkpoint: call.checkpoint,
      )).toJson(),
    ),
  );

  firebase.https.onCall(
    name: updateTipperAliasEndpoint,
    options: identityCallableOptions,
    (request, response) => _serve<UpdateTipperAliasRequest>(
      request,
      callable: updateTipperAliasEndpoint,
      openDatabase: openDatabase,
      deadline: handlerDeadline,
      parse: UpdateTipperAliasRequest.fromJson,
      badRequestReason: identityReasonInvalidAlias,
      handle: (call) async => (await updateTipperAlias(
        database: call.database,
        caller: call.caller,
        request: call.request,
        admission: call.admission,
        checkpoint: call.checkpoint,
      )).toJson(),
    ),
  );

  firebase.https.onCall(
    name: registerDeviceTokenEndpoint,
    options: identityCallableOptions,
    (request, response) => _serve<DeviceTokenRequest>(
      request,
      callable: registerDeviceTokenEndpoint,
      openDatabase: openDatabase,
      deadline: handlerDeadline,
      parse: DeviceTokenRequest.fromJson,
      badRequestReason: identityReasonInvalidToken,
      handle: (call) async => (await registerDeviceToken(
        database: call.database,
        caller: call.caller,
        request: call.request,
        checkpoint: call.checkpoint,
      )).toJson(),
    ),
  );

  firebase.https.onCall(
    name: unregisterDeviceTokenEndpoint,
    options: identityCallableOptions,
    (request, response) => _serve<DeviceTokenRequest>(
      request,
      callable: unregisterDeviceTokenEndpoint,
      openDatabase: openDatabase,
      deadline: handlerDeadline,
      parse: DeviceTokenRequest.fromJson,
      badRequestReason: identityReasonInvalidToken,
      handle: (call) async => (await unregisterDeviceToken(
        database: call.database,
        caller: call.caller,
        request: call.request,
        checkpoint: call.checkpoint,
      )).toJson(),
    ),
  );

  firebase.https.onCall(
    name: unlinkMyAccountEndpoint,
    options: identityCallableOptions,
    (request, response) => _serve<UnlinkMyAccountRequest>(
      request,
      callable: unlinkMyAccountEndpoint,
      openDatabase: openDatabase,
      deadline: handlerDeadline,
      parse: UnlinkMyAccountRequest.fromJson,
      handle: (call) async => (await unlinkMyAccount(
        database: call.database,
        caller: call.caller,
        admission: call.admission,
        checkpoint: call.checkpoint,
      )).toJson(),
    ),
  );

  firebase.https.onCall(
    name: adminUpdateTipperEndpoint,
    options: identityCallableOptions,
    (request, response) => _serve<AdminUpdateTipperRequest>(
      request,
      callable: adminUpdateTipperEndpoint,
      openDatabase: openDatabase,
      deadline: handlerDeadline,
      parse: AdminUpdateTipperRequest.fromJson,
      handle: (call) async => (await adminUpdateTipper(
        database: call.database,
        caller: call.caller,
        request: call.request,
        admission: call.admission,
        checkpoint: call.checkpoint,
      )).toJson(),
    ),
  );

  firebase.https.onCall(
    name: adminMergeTippersEndpoint,
    options: identityCallableOptions,
    (request, response) => _serve<AdminMergeTippersRequest>(
      request,
      callable: adminMergeTippersEndpoint,
      openDatabase: openDatabase,
      deadline: handlerDeadline,
      parse: AdminMergeTippersRequest.fromJson,
      handle: (call) async => (await adminMergeTippers(
        database: call.database,
        caller: call.caller,
        request: call.request,
        admission: call.admission,
        checkpoint: call.checkpoint,
      )).toJson(),
    ),
  );
}

/// What a callable's handler is given once the request has been accepted.
class _Call<Request> {
  const _Call({
    required this.database,
    required this.caller,
    required this.request,
    required this.admission,
    required this.checkpoint,
  });

  final RestDatabase database;
  final CallerToken caller;
  final Request request;
  final Admission admission;
  final Checkpoint checkpoint;
}

Future<CallableResult<Map<String, Object?>>> _serve<Request>(
  CallableRequest<Object?> call, {
  required String callable,
  required IdentityDatabaseOpener openDatabase,
  required Duration deadline,
  required Request Function(Object? data) parse,
  required Future<Map<String, Object?>> Function(_Call<Request> call) handle,
  String? badRequestReason,
}) async {
  final auth = call.auth;
  if (auth == null) {
    throw UnauthenticatedError('Please sign in first.');
  }
  final caller = CallerToken.fromClaims(
    auth.uid,
    withSignInProvider(auth.token, auth.rawToken),
  );

  final Request request;
  try {
    request = parse(call.data);
  } on FormatException catch (error) {
    throw InvalidArgumentError(error.message, reason: badRequestReason);
  }

  final RestDatabase database;
  try {
    database = await openDatabase();
  } on Object {
    throw UnavailableError(
      'Please try again shortly.',
      reason: identityReasonUnavailable,
    );
  }

  final limit = HandlerDeadline(limit: deadline);
  final result = await runAdmitted<Map<String, Object?>>(
    database: database,
    callable: callable,
    uid: caller.uid,
    body: (admission) => handle(
      _Call<Request>(
        database: database,
        caller: caller,
        request: request,
        admission: admission,
        checkpoint: limit.check,
      ),
    ),
  );
  return CallableResult<Map<String, Object?>>(result);
}

/// The claims the runtime hands a callable, plus the `firebase` claim.
///
/// The runtime copies only the custom claims and a fixed set of standard ones
/// out of the ID token it verified; `firebase`, which says how the user signed
/// in (`password`, `google.com`, `anonymous`), is not among them. The provider
/// is read from the same token's payload instead. That is safe because the
/// runtime has already checked the token's signature before any handler runs;
/// a token it refused never gets here. Anything unreadable leaves the claims as
/// they were, which treats the caller as not anonymous: the verified-email rule
/// still refuses an anonymous account.
Map<String, dynamic>? withSignInProvider(
  Map<String, dynamic>? claims,
  String? rawToken,
) {
  if (claims == null || claims.containsKey('firebase') || rawToken == null) {
    return claims;
  }
  try {
    final parts = rawToken.split('.');
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final firebase = payload is Map ? payload['firebase'] : null;
    return firebase is Map
        ? <String, dynamic>{...claims, 'firebase': firebase}
        : claims;
  } on Object {
    return claims;
  }
}
