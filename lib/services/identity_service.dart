import 'dart:async';

import 'package:dau_shared/constants/function_endpoints.dart' as endpoints;
import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/dau_shared.dart';

/// The address pattern of the identity callables. They are deployed as Cloud Run
/// services, so each lives at `https://{name}-<project hash>-<region>.a.run.app`;
/// the hash is fixed for the life of the project (the admin callables' addresses
/// in `AppConfig` have the same shape). `{name}` stands for the endpoint id.
const String defaultIdentityUrlPattern =
    'https://{name}-rjp4ue2oxa-as.a.run.app';

/// Where the identity callables are. The pattern can be overridden from
/// `AppConfig` (see [identityFunctionsUrlPatternKey]) without a release.
class IdentityEndpoints {
  IdentityEndpoints({String pattern = defaultIdentityUrlPattern})
    : pattern = _checked(pattern);

  final String pattern;

  static String _checked(String pattern) {
    final uri = Uri.tryParse(pattern.replaceAll('{name}', 'x'));
    if (!pattern.contains('{name}') ||
        uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(
        pattern,
        'pattern',
        'must be an http(s) address containing {name}',
      );
    }
    return pattern;
  }

  /// The address of [endpoint].
  String urlFor(String endpoint) => pattern.replaceAll('{name}', endpoint);
}

/// The `AppConfig` key that may hold a replacement [IdentityEndpoints.pattern].
/// Absent in production today: the default is used.
const String identityFunctionsUrlPatternKey = 'identityFunctionsURLPattern';

/// How a call to an identity callable failed.
enum IdentityFailureKind {
  /// The server understood and refused: [IdentityFailure.reason] says why when it
  /// gave a reason. Retrying the same request will not change the answer.
  refused,

  /// Not now: the server is busy, in a migration step, or unreachable. The same
  /// request may well succeed shortly.
  transient,

  /// The caller is not signed in, or the session is not accepted.
  unauthenticated,

  /// Something that should not happen: an answer of the wrong shape, an internal
  /// error.
  unexpected,
}

/// A failed call to an identity callable, with what the client needs to decide
/// what to show: the [kind], the server's machine-readable [reason] (one of the
/// `identityReason*` constants) and its [message].
class IdentityFailure implements Exception {
  const IdentityFailure({
    required this.kind,
    required this.code,
    required this.message,
    this.reason,
  });

  final IdentityFailureKind kind;

  /// The callable error code (`failed-precondition`, `unavailable`, ...), or
  /// `network` for a failure before any answer.
  final String code;

  final String message;

  /// The server's reason, when it gave one.
  final String? reason;

  /// Another change to this tipper is in progress.
  bool get isBusy => reason == reasons.identityReasonBusy;

  /// The identity callables are switched off or this user is not a pilot user.
  bool get isNotAvailable => reason == reasons.identityReasonNotAvailable;

  /// Whether trying again shortly is reasonable.
  bool get isRetryable => kind == IdentityFailureKind.transient;

  /// Reads a failure from the pieces of a callable error: the plugin's error
  /// `code`, its `message`, and its `details` (the server sends a list holding an
  /// `ErrorInfo` with a `reason`).
  factory IdentityFailure.fromFunctionsError({
    required String code,
    required String? message,
    Object? details,
  }) {
    final reason = _reasonFrom(details);
    final text = (message == null || message.isEmpty) ? code : message;
    final IdentityFailureKind kind;
    if (reason == reasons.identityReasonBusy ||
        reason == reasons.identityReasonUnavailable) {
      kind = IdentityFailureKind.transient;
    } else if (code == 'unauthenticated') {
      kind = IdentityFailureKind.unauthenticated;
    } else if (code == 'unavailable' ||
        code == 'deadline-exceeded' ||
        code == 'aborted' ||
        code == 'resource-exhausted') {
      kind = IdentityFailureKind.transient;
    } else if (reason != null ||
        code == 'invalid-argument' ||
        code == 'failed-precondition' ||
        code == 'permission-denied' ||
        code == 'already-exists' ||
        code == 'not-found') {
      kind = IdentityFailureKind.refused;
    } else {
      kind = IdentityFailureKind.unexpected;
    }
    return IdentityFailure(
      kind: kind,
      code: code,
      message: text,
      reason: reason,
    );
  }

  /// A failure before any answer: no connection, a timeout.
  factory IdentityFailure.network(Object error) => IdentityFailure(
    kind: IdentityFailureKind.transient,
    code: 'network',
    message: 'Could not reach the server: $error',
  );

  static String? _reasonFrom(Object? details) {
    final candidates = details is List ? details : <Object?>[details];
    for (final candidate in candidates) {
      if (candidate is Map) {
        final domain = candidate['domain'];
        final reason = candidate['reason'];
        if (reason is String &&
            reason.isNotEmpty &&
            (domain == null || domain == reasons.identityErrorDomain)) {
          return reason;
        }
      }
    }
    return null;
  }

  @override
  String toString() =>
      'IdentityFailure(${kind.name}, $code${reason == null ? '' : ', $reason'}): $message';
}

/// Calls one identity callable. A seam: production uses `cloud_functions`
/// (see `FunctionsIdentityCallableInvoker`), tests use a fake. An implementation
/// throws [IdentityFailure] for every failure.
abstract interface class IdentityCallableInvoker {
  /// Calls [endpoint] with [data] and returns the decoded answer.
  Future<Object?> call(
    String endpoint,
    Map<String, Object?> data, {
    Duration timeout,
  });
}

/// The identity callables of DESIGN-database-rules-phase4.md, as typed calls. Every
/// method either returns the typed result or throws an [IdentityFailure]; an answer
/// of the wrong shape is an `unexpected` failure, never a crash.
class IdentityService {
  IdentityService(this._invoker);

  final IdentityCallableInvoker _invoker;

  /// The longest a call waits. The server's own limit is 60 seconds.
  static const Duration callTimeout = Duration(seconds: 65);

  Future<T> _call<T>(
    String endpoint,
    Map<String, Object?> data,
    T Function(Object? raw) parse,
  ) async {
    final Object? raw;
    try {
      raw = await _invoker.call(endpoint, data, timeout: callTimeout);
    } on IdentityFailure {
      rethrow;
    } on TimeoutException catch (error) {
      throw IdentityFailure.network(error);
    }
    try {
      return parse(raw);
    } on FormatException catch (error) {
      throw IdentityFailure(
        kind: IdentityFailureKind.unexpected,
        code: 'bad-response',
        message:
            'The server answered with something unexpected: ${error.message}',
      );
    }
  }

  /// Links the signed-in account to its tipper record, or creates one when
  /// [alias] is given and nothing matches. Without an alias and with no match,
  /// the server refuses with `invalid_alias` (or `creation_disabled`): that is
  /// the cue to ask the user for an alias.
  Future<LinkOrCreateTipperResult> linkOrCreateTipper({String? alias}) => _call(
    endpoints.linkOrCreateTipperEndpoint,
    LinkOrCreateTipperRequest(alias: alias).toJson(),
    LinkOrCreateTipperResult.fromJson,
  );

  /// Changes the signed-in tipper's alias.
  Future<UpdateTipperAliasResult> updateTipperAlias(String alias) => _call(
    endpoints.updateTipperAliasEndpoint,
    UpdateTipperAliasRequest(alias: alias).toJson(),
    UpdateTipperAliasResult.fromJson,
  );

  /// Moves a push token to the signed-in tipper.
  Future<RegisterDeviceTokenResult> registerDeviceToken(String token) => _call(
    endpoints.registerDeviceTokenEndpoint,
    DeviceTokenRequest(token: token).toJson(),
    RegisterDeviceTokenResult.fromJson,
  );

  /// Removes a push token from the signed-in tipper.
  Future<UnregisterDeviceTokenResult> unregisterDeviceToken(String token) =>
      _call(
        endpoints.unregisterDeviceTokenEndpoint,
        DeviceTokenRequest(token: token).toJson(),
        UnregisterDeviceTokenResult.fromJson,
      );

  /// Detaches the signed-in account from its tipper record, ready for the account
  /// to be deleted.
  Future<UnlinkMyAccountResult> unlinkMyAccount() => _call(
    endpoints.unlinkMyAccountEndpoint,
    const UnlinkMyAccountRequest().toJson(),
    UnlinkMyAccountResult.fromJson,
  );

  /// An administrator changes another tipper's name, contact email or role.
  Future<AdminUpdateTipperResult> adminUpdateTipper({
    required String tipperId,
    String? name,
    String? email,
    TipperRole? role,
  }) => _call(
    endpoints.adminUpdateTipperEndpoint,
    AdminUpdateTipperRequest(
      tipperId: tipperId,
      name: name,
      email: email,
      role: role,
    ).toJson(),
    AdminUpdateTipperResult.fromJson,
  );

  /// An administrator merges one tipper record into another. With [dryRun] the
  /// server only reports what it would do.
  Future<AdminMergeTippersResult> adminMergeTippers({
    required String originalId,
    required String targetId,
    bool mergeTips = false,
    bool mergeLogon = false,
    bool dryRun = false,
  }) => _call(
    endpoints.adminMergeTippersEndpoint,
    AdminMergeTippersRequest(
      originalId: originalId,
      targetId: targetId,
      mergeTips: mergeTips,
      mergeLogon: mergeLogon,
      dryRun: dryRun,
    ).toJson(),
    AdminMergeTippersResult.fromJson,
  );
}
