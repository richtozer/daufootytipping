import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_functions/firebase_functions.dart'
    hide Credential, DataSnapshot;
import 'package:firebase_admin/firebase_admin.dart';
import 'package:firebase_dart/standalone_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';
import 'package:intl/intl.dart';

// firebase_functions 0.7 replaced its specialized HttpsError subclasses with
// HttpResponseException. These adapters preserve the existing domain-specific
// catch clauses while using the new runtime-recognized exception type.
class InvalidArgumentError extends HttpResponseException {
  InvalidArgumentError(String message)
      : super(400, message, status: 'INVALID_ARGUMENT');
}

class UnauthenticatedError extends HttpResponseException {
  UnauthenticatedError(String message)
      : super(401, message, status: 'UNAUTHENTICATED');
}

class PermissionDeniedError extends HttpResponseException {
  PermissionDeniedError(String message)
      : super(403, message, status: 'PERMISSION_DENIED');
}

class NotFoundError extends HttpResponseException {
  NotFoundError(String message) : super(404, message, status: 'NOT_FOUND');
}

class AbortedError extends HttpResponseException {
  AbortedError(String message) : super(409, message, status: 'ABORTED');
}

class InternalError extends HttpResponseException {
  InternalError(String message) : super(500, message, status: 'INTERNAL');
}

class UnavailableError extends HttpResponseException {
  UnavailableError(String message) : super(503, message, status: 'UNAVAILABLE');
}

void logFunction(String message) {
  stdout.writeln('[adminFixtureDownload] $message');
}

void logScheduledFixtureDownload(String message) {
  stdout.writeln('[scheduledFixtureDownload] $message');
}

const _adminCallableOptions = CallableOptions(
  region: Region(SupportedRegion.asiaSoutheast1),
  timeoutSeconds: TimeoutSeconds(300),
  enforceAppCheck: EnforceAppCheck(true),
);
const _backendScoringCommandOptions = HttpsOptions(
  region: Region(SupportedRegion.asiaSoutheast1),
  timeoutSeconds: TimeoutSeconds(300),
);
const _scheduledFixtureDownloadOptions = HttpsOptions(
  region: Region(SupportedRegion.asiaSoutheast1),
  timeoutSeconds: TimeoutSeconds(300),
);
const _appBadgeCountOptions = HttpsOptions(
  region: Region(SupportedRegion.asiaSoutheast1),
  timeoutSeconds: TimeoutSeconds(120),
  invoker: Invoker.public(),
);
const int _idempotencyPruneLimit = 500;
const Duration _fixtureDownloadLockTtl = Duration(minutes: 10);

void main(List<String> args) async {
  await runFunctions((firebase) {
    final runtimeAdminApp = firebase.adminApp;

    // The name: values below are the DEPLOYED endpoint ids and are declared
    // verbatim in hyphenated form. firebase_functions 0.7 lowercases the name
    // as-is (0.6 kebab-cased camelCase for you), so renaming these to camelCase
    // would silently rename every deployed function and break the Flutter
    // client and the TypeScript functions that call these by name.
    firebase.https.onCall(
      name: adminFixtureDownloadEndpoint,
      options: _adminCallableOptions,
      (request, response) async {
        logFunction('adminFixtureDownload: callable invoked');
        // 1. Verify caller authentication
        final auth = request.auth;
        if (auth == null) {
          logFunction('adminFixtureDownload: missing callable auth');
          throw UnauthenticatedError('User must be authenticated');
        }

        final uid = auth.uid;
        logFunction('adminFixtureDownload: auth uid=$uid');

        final dbHandle = await _openBackendScoringDatabase(
          runtimeAdminApp: runtimeAdminApp,
        );

        try {
          final compKey = extractAdminFixtureDownloadCompKey(request.data);
          logFunction('adminFixtureDownload: compKey=$compKey');
          if (compKey == null || compKey.isEmpty) {
            throw InvalidArgumentError('Missing required parameter: compKey');
          }

          final resultMsg = await executeFixtureDownload(
            authUid: uid,
            compKey: compKey,
            db: dbHandle.database,
            fetchFixtureJson: _fetchFixtureJson,
            now: DateTime.now().toUtc(),
            afterSuccessfulDownload: (comp, now) => _afterSuccessfulFixtureDownload(
              db: dbHandle.database,
              comp: comp,
              now: now,
            ),
          );

          return CallableResult({
            'success': true,
            'message': resultMsg,
          });
        } on HttpResponseException catch (e) {
          logFunction('adminFixtureDownload: callable error: $e');
          rethrow;
        } catch (e, stackTrace) {
          logFunction('adminFixtureDownload: unexpected failure: $e\n$stackTrace');
          rethrow;
        } finally {
          await dbHandle.close();
        }
      },
    );

    firebase.https.onCall(
      name: adminScoringRescoreEndpoint,
      options: _adminCallableOptions,
      (request, response) async {
        final auth = request.auth;
        if (auth == null) {
          throw UnauthenticatedError('User must be authenticated');
        }

        final dbHandle = await _openBackendScoringDatabase(
          runtimeAdminApp: runtimeAdminApp,
        );
        try {
          final compKey = extractAdminFixtureDownloadCompKey(request.data);
          if (compKey == null || compKey.isEmpty) {
            throw InvalidArgumentError('Missing required parameter: compKey');
          }
          final result = await executeAdminScoringRescore(
            authUid: auth.uid,
            compKey: compKey,
            db: dbHandle.database,
            now: DateTime.now().toUtc(),
          );
          return CallableResult({
            'success': true,
            'message': result.message,
          });
        } finally {
          await dbHandle.close();
        }
      },
    );

    firebase.https.onCall(
      name: adminCheckFixtureUrlEndpoint,
      options: _adminCallableOptions,
      (request, response) async {
        logFunction('adminCheckFixtureUrl: callable invoked');
        final auth = request.auth;
        if (auth == null) {
          logFunction('adminCheckFixtureUrl: missing callable auth');
          throw UnauthenticatedError('User must be authenticated');
        }

        final dbHandle = await _openBackendScoringDatabase(
          runtimeAdminApp: runtimeAdminApp,
        );
        try {
          final url = extractAdminCheckFixtureUrlUrl(request.data);
          if (url == null || url.isEmpty) {
            throw InvalidArgumentError('Missing required parameter: url');
          }

          final active = await checkFixtureUrlActive(
            authUid: auth.uid,
            url: url,
            db: dbHandle.database,
          );

          return CallableResult({'active': active});
        } on HttpResponseException catch (e) {
          logFunction('adminCheckFixtureUrl: callable error: $e');
          rethrow;
        } catch (e, stackTrace) {
          logFunction(
            'adminCheckFixtureUrl: unexpected failure: $e\n$stackTrace',
          );
          rethrow;
        } finally {
          await dbHandle.close();
        }
      },
    );

    firebase.https.onRequest(
      name: backendScoringCommandEndpoint,
      options: _backendScoringCommandOptions,
      (request) => _handleBackendScoringCommandRequestWithRuntimeApp(
        request,
        runtimeAdminApp: runtimeAdminApp,
      ),
    );

    firebase.https.onRequest(
      name: scheduledFixtureDownloadEndpoint,
      options: _scheduledFixtureDownloadOptions,
      (request) => _handleScheduledFixtureDownloadRequestWithRuntimeApp(
        request,
        runtimeAdminApp: runtimeAdminApp,
      ),
    );

    firebase.https.onRequest(
      name: appBadgeCountEndpoint,
      options: _appBadgeCountOptions,
      (request) => _handleAppBadgeCountRequestWithRuntimeApp(
        request,
        runtimeAdminApp: runtimeAdminApp,
      ),
    );
  });
}

String? extractAdminFixtureDownloadCompKey(Object? data) {
  if (data is! Map) {
    return null;
  }
  final compKey = data['compKey'];
  return compKey is String ? compKey : null;
}

String? extractAdminCheckFixtureUrlUrl(Object? data) {
  if (data is! Map) {
    return null;
  }
  final url = data['url'];
  return url is String ? url : null;
}

String resolveProjectId({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  return env['GCLOUD_PROJECT'] ??
      env['GOOGLE_CLOUD_PROJECT'] ??
      env['GCP_PROJECT'] ??
      env['FIREBASE_PROJECT'] ??
      'dau-footy-tipping-f8a42';
}

String resolveDatabaseUrl({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final emulatorHost = env['FIREBASE_DATABASE_EMULATOR_HOST'];
  if (emulatorHost != null && emulatorHost.isNotEmpty) {
    final namespace = env['RTDB_EMULATOR_NAMESPACE'] ??
        env['FIREBASE_DATABASE_EMULATOR_NAMESPACE'] ??
        '${resolveProjectId(environment: env)}-default-rtdb';
    return 'http://$emulatorHost/?ns=$namespace';
  }

  final firebaseConfig = env['FIREBASE_CONFIG'];
  if (firebaseConfig != null && firebaseConfig.isNotEmpty) {
    try {
      final decoded = json.decode(firebaseConfig);
      if (decoded is Map) {
        final configuredUrl = decoded['databaseURL'];
        if (configuredUrl is String && configuredUrl.isNotEmpty) {
          return configuredUrl;
        }
      }
    } catch (_) {}
  }

  return 'https://dau-footy-tipping-f8a42-default-rtdb.asia-southeast1.firebasedatabase.app';
}

const String _backendScoringCommandSecretHeader = 'x-backend-scoring-secret';
const String _appBadgeCommandSecretHeader = 'x-app-badge-secret';
const List<String> _backendScoringCommandSecretEnvKeys = [
  'BACKEND_SCORING_COMMAND_SECRET',
  'DART_BACKEND_SCORING_COMMAND_SECRET',
];

const List<String> _backendScoringCommandUrlEnvKeys = [
  'BACKEND_SCORING_COMMAND_URL',
  'DART_BACKEND_SCORING_COMMAND_URL',
];
const List<String> _appBadgeCommandSecretEnvKeys = [
  'APP_BADGE_COMMAND_SECRET',
  'DART_APP_BADGE_COMMAND_SECRET',
];
const String _defaultProjectId = 'dau-footy-tipping-f8a42';
const String _defaultFunctionRegion = 'asia-southeast1';
const String _defaultFunctionsEmulatorOrigin = 'http://127.0.0.1:9229';

String? resolveBackendScoringCommandSecret({
  Map<String, String>? environment,
}) {
  final secrets = resolveBackendScoringCommandSecrets(environment: environment);
  return secrets.isEmpty ? null : secrets.first;
}

List<String> resolveBackendScoringCommandSecrets({
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final secrets = <String>[];
  for (final key in _backendScoringCommandSecretEnvKeys) {
    final value = env[key];
    if (value != null && value.isNotEmpty && !secrets.contains(value)) {
      secrets.add(value);
    }
  }
  return secrets;
}

List<String> resolveAppBadgeCommandSecrets({
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final secrets = <String>[];
  for (final key in _appBadgeCommandSecretEnvKeys) {
    final value = env[key];
    if (value != null && value.isNotEmpty && !secrets.contains(value)) {
      secrets.add(value);
    }
  }
  return secrets;
}

String? resolveBackendScoringCommandUrl({
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final localUrl = resolveLocalDartFunctionUrl(
    'backend-scoring-command',
    environment: env,
  );
  if (localUrl != null) {
    return localUrl;
  }

  for (final key in _backendScoringCommandUrlEnvKeys) {
    final value = env[key];
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

bool isRunningInFirebaseFunctionsEmulator({
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final value = env['FUNCTIONS_EMULATOR'];
  return value != null && value.isNotEmpty && value != 'false' && value != '0';
}

String? resolveLocalDartFunctionUrl(
  String functionName, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  if (!isRunningInFirebaseFunctionsEmulator(environment: env)) {
    return null;
  }

  return [
    _resolveFunctionsEmulatorOrigin(env),
    _resolveFirebaseProjectId(env),
    _resolveFirebaseFunctionRegion(env),
    functionName,
  ].join('/');
}

String _resolveFirebaseProjectId(Map<String, String> environment) {
  return environment['GCLOUD_PROJECT'] ??
      environment['GOOGLE_CLOUD_PROJECT'] ??
      environment['GCP_PROJECT'] ??
      environment['FIREBASE_PROJECT'] ??
      _defaultProjectId;
}

String _resolveFirebaseFunctionRegion(Map<String, String> environment) {
  return environment['FUNCTION_REGION'] ??
      environment['FUNCTIONS_REGION'] ??
      _defaultFunctionRegion;
}

String _resolveFunctionsEmulatorOrigin(Map<String, String> environment) {
  final configuredOrigin = environment['LOCAL_FUNCTIONS_EMULATOR_ORIGIN'] ??
      environment['FUNCTIONS_EMULATOR_ORIGIN'] ??
      environment['FUNCTIONS_EMULATOR_HOST'];
  if (configuredOrigin != null && configuredOrigin.trim().isNotEmpty) {
    return _normalizeOrigin(configuredOrigin);
  }

  return _defaultFunctionsEmulatorOrigin;
}

String _normalizeOrigin(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }

  return 'http://$trimmed';
}

bool isBackendScoringCommandAuthorized(
  Map<String, String> headers, {
  String? expectedSecret,
  List<String>? expectedSecrets,
}) {
  final secrets = expectedSecrets ??
      (expectedSecret == null
          ? resolveBackendScoringCommandSecrets()
          : <String>[expectedSecret]);
  if (secrets.isEmpty) {
    return false;
  }

  final providedSecret = _headerValueCaseInsensitive(
    headers,
    _backendScoringCommandSecretHeader,
  );
  var authorized = false;
  for (final secret in secrets) {
    authorized = _constantTimeStringEquals(providedSecret, secret) || authorized;
  }
  return authorized;
}

bool isAppBadgeCommandAuthorized(
  Map<String, String> headers, {
  required Iterable<String> expectedSecrets,
}) {
  final suppliedSecret = _headerValueCaseInsensitive(
    headers,
    _appBadgeCommandSecretHeader,
  );
  var authorized = false;
  for (final secret in expectedSecrets) {
    authorized =
        _constantTimeStringEquals(suppliedSecret, secret) || authorized;
  }
  return authorized;
}

bool _constantTimeStringEquals(String? left, String right) {
  if (left == null) {
    return false;
  }

  var diff = left.length ^ right.length;
  final maxLength = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < maxLength; i++) {
    final leftUnit = i < left.length ? left.codeUnitAt(i) : 0;
    final rightUnit = i < right.length ? right.codeUnitAt(i) : 0;
    diff |= leftUnit ^ rightUnit;
  }
  return diff == 0;
}

String? _headerValueCaseInsensitive(
  Map<String, String> headers,
  String headerName,
) {
  final target = headerName.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value;
    }
  }
  return null;
}

Response _backendScoringErrorResponse(
  int statusCode,
  String status,
  String message,
) {
  return Response(
    statusCode,
    body: jsonEncode(<String, dynamic>{
      'error': <String, dynamic>{
        'status': status,
        'message': message,
      },
    }),
    headers: _jsonHeaders,
  );
}

Future<Response> _handleBackendScoringCommandRequestWithRuntimeApp(
  dynamic request, {
  required dynamic runtimeAdminApp,
}) async {
  try {
    if (request.method.toUpperCase() != 'POST') {
      return _backendScoringErrorResponse(
        405,
        'METHOD_NOT_ALLOWED',
        'Method not allowed',
      );
    }

    final commandSecrets = resolveBackendScoringCommandSecrets();
    if (commandSecrets.isEmpty) {
      return _backendScoringErrorResponse(
        400,
        'FAILED_PRECONDITION',
        'Backend scoring command secret is not configured',
      );
    }

    final headers = Map<String, String>.from(request.headers as Map);
    if (!isBackendScoringCommandAuthorized(
      headers,
      expectedSecrets: commandSecrets,
    )) {
      throw PermissionDeniedError('Unauthorized backend scoring command request');
    }

    final bodyString = await request.readAsString();
    if (bodyString.isEmpty) {
      throw InvalidArgumentError('Request body is required');
    }

    final decoded = json.decode(bodyString);
    if (decoded is! Map) {
      throw InvalidArgumentError('Request body must be a JSON object');
    }

    final payload = Map<String, dynamic>.from(decoded);
    final commandJson = payload['command'] is Map
        ? Map<String, dynamic>.from(payload['command'] as Map)
        : payload;
    final command = BackendScoringCommand.fromJson(commandJson);

    final dbHandle = await _openBackendScoringDatabase(
      runtimeAdminApp: runtimeAdminApp,
    );
    try {
      final result = await executeBackendScoringCommand(
        db: dbHandle.database,
        command: command,
        now: DateTime.now().toUtc(),
      );
      return Response.ok(
        jsonEncode(result.toJson()),
        headers: _jsonHeaders,
      );
    } finally {
      await dbHandle.close();
    }
  } on InvalidArgumentError catch (error) {
    return _backendScoringErrorResponse(
      400,
      'INVALID_ARGUMENT',
      error.toString(),
    );
  } on UnauthenticatedError catch (error) {
    return _backendScoringErrorResponse(
      401,
      'UNAUTHENTICATED',
      error.toString(),
    );
  } on PermissionDeniedError catch (error) {
    return _backendScoringErrorResponse(
      403,
      'PERMISSION_DENIED',
      error.toString(),
    );
  } on NotFoundError catch (error) {
    return _backendScoringErrorResponse(
      404,
      'NOT_FOUND',
      error.toString(),
    );
  } on AbortedError catch (error) {
    return _backendScoringErrorResponse(
      503,
      'UNAVAILABLE',
      error.toString(),
    );
  } on InternalError catch (error) {
    return _backendScoringErrorResponse(
      500,
      'INTERNAL',
      error.toString(),
    );
  } catch (error, stackTrace) {
    developer.log(
      'backendScoringCommand: unhandled error',
      name: 'backendScoringCommand',
      error: error,
      stackTrace: stackTrace,
    );
    return _backendScoringErrorResponse(
      500,
      'INTERNAL',
      'An unexpected error occurred.',
    );
  }
}

Future<Response> _handleAppBadgeCountRequestWithRuntimeApp(
  dynamic request, {
  required dynamic runtimeAdminApp,
}) async {
  try {
    if (request.method.toUpperCase() != 'POST') {
      return _backendScoringErrorResponse(
        405,
        'METHOD_NOT_ALLOWED',
        'Method not allowed',
      );
    }

    final commandSecrets = resolveAppBadgeCommandSecrets();
    if (commandSecrets.isEmpty) {
      return _backendScoringErrorResponse(
        400,
        'FAILED_PRECONDITION',
        'App badge command secret is not configured',
      );
    }

    final headers = normalizeHttpHeaders(request.headers);
    if (!isAppBadgeCommandAuthorized(
      headers,
      expectedSecrets: commandSecrets,
    )) {
      throw PermissionDeniedError('Unauthorized app badge count request');
    }

    final bodyString = await request.readAsString();
    if (bodyString.isEmpty) {
      throw InvalidArgumentError('Request body is required');
    }
    final decoded = json.decode(bodyString);
    if (decoded is! Map) {
      throw InvalidArgumentError('Request body must be a JSON object');
    }
    final payload = Map<String, dynamic>.from(decoded);
    final compKey = payload['compKey'];
    if (compKey is! String || compKey.trim().isEmpty) {
      throw InvalidArgumentError('compKey is required');
    }
    final requestedTipperIds = _parseRequestedAppBadgeTipperIds(
      payload['tipperIds'],
    );

    final dbHandle = await _openBackendScoringDatabase(
      runtimeAdminApp: runtimeAdminApp,
    );
    try {
      final comp = await _loadBackendScoringComp(dbHandle.database, compKey);
      final results = calculateOutstandingTipCounts(
        comp: comp,
        games: await _loadBackendScoringGames(
          db: dbHandle.database,
          comp: comp,
        ),
        allTippers: await _loadBackendScoringTippers(dbHandle.database),
        tipsByTipperRaw: await _loadBackendScoringTipsByTipperRaw(
          db: dbHandle.database,
          compKey: compKey,
        ),
        now: DateTime.now().toUtc(),
        requestedTipperIds: requestedTipperIds,
      );
      return Response.ok(
        jsonEncode(<String, dynamic>{
          'compKey': compKey,
          'calculatedAt': DateTime.now().toUtc().toIso8601String(),
          'counts': results,
        }),
        headers: _jsonHeaders,
      );
    } finally {
      await dbHandle.close();
    }
  } on FormatException catch (error) {
    return _backendScoringErrorResponse(
      400,
      'INVALID_ARGUMENT',
      error.toString(),
    );
  } on InvalidArgumentError catch (error) {
    return _backendScoringErrorResponse(
      400,
      'INVALID_ARGUMENT',
      error.toString(),
    );
  } on PermissionDeniedError catch (error) {
    return _backendScoringErrorResponse(
      403,
      'PERMISSION_DENIED',
      error.toString(),
    );
  } on NotFoundError catch (error) {
    return _backendScoringErrorResponse(
      404,
      'NOT_FOUND',
      error.toString(),
    );
  } catch (error, stackTrace) {
    developer.log(
      'appBadgeCount: unhandled error',
      name: 'appBadgeCount',
      error: error,
      stackTrace: stackTrace,
    );
    return _backendScoringErrorResponse(
      500,
      'INTERNAL',
      'An unexpected error occurred.',
    );
  }
}

Set<String>? _parseRequestedAppBadgeTipperIds(Object? rawTipperIds) {
  if (rawTipperIds == null) {
    return null;
  }
  if (rawTipperIds is! List) {
    throw InvalidArgumentError('tipperIds must be an array');
  }
  final result = <String>{};
  for (final rawTipperId in rawTipperIds) {
    if (rawTipperId is! String || rawTipperId.trim().isEmpty) {
      throw InvalidArgumentError('tipperIds must contain non-empty strings');
    }
    result.add(rawTipperId);
  }
  return result;
}

Map<String, int> calculateOutstandingTipCounts({
  required DAUComp comp,
  required List<Game> games,
  required List<Tipper> allTippers,
  required Map<String, dynamic> tipsByTipperRaw,
  required DateTime now,
  Set<String>? requestedTipperIds,
}) {
  for (final round in comp.daurounds) {
    round.games = games
        .where(
          (game) =>
              game.isGameInRound(round) &&
              !_isBackendScoringGameOutsideRegularComp(comp, game),
        )
        .toList();
  }
  const RoundsLinkingService().finalizeRoundsAndComputeUnassigned(
    rounds: comp.daurounds,
    allGames: games,
    nrlCutoff: comp.nrlRegularCompEndDateUTC,
    aflCutoff: comp.aflRegularCompEndDateUTC,
    now: now,
  );

  final badgeRound = OutstandingTipsCalculator.appBadgeRoundForTime(
    rounds: comp.daurounds,
    now: now,
  );

  final tippersById = <String, Tipper>{
    for (final tipper in allTippers)
      if (tipper.dbkey != null) tipper.dbkey!: tipper,
  };
  final result = <String, int>{};
  final targetTipperIds = requestedTipperIds ?? tippersById.keys.toSet();
  for (final tipperId in targetTipperIds) {
    final tipper = tippersById[tipperId];
    final eligible = tipper != null &&
        !tipper.isAnonymous &&
        tipper.paidForComp(comp);
    if (!eligible) {
      if (requestedTipperIds != null) {
        result[tipperId] = 0;
      }
      continue;
    }

    final submittedGameKeys = <String>{};
    final rawTips = tipsByTipperRaw[tipperId];
    if (rawTips is Map) {
      submittedGameKeys.addAll(rawTips.keys.map((key) => key.toString()));
    }
    result[tipperId] = badgeRound == null
        ? 0
        : OutstandingTipsCalculator.countUpcomingUntippedGames(
            games: badgeRound.games,
            submittedGameKeys: submittedGameKeys,
            now: now,
          );
  }
  return result;
}

Future<Response> _handleScheduledFixtureDownloadRequestWithRuntimeApp(
  dynamic request, {
  required dynamic runtimeAdminApp,
}) async {
  try {
    logScheduledFixtureDownload('request received');
    if (request.method.toUpperCase() != 'POST') {
      return _backendScoringErrorResponse(
        405,
        'METHOD_NOT_ALLOWED',
        'Method not allowed',
      );
    }

    final commandSecrets = resolveBackendScoringCommandSecrets();
    if (commandSecrets.isEmpty) {
      logScheduledFixtureDownload('backend command secret is not configured');
      return _backendScoringErrorResponse(
        400,
        'FAILED_PRECONDITION',
        'Backend command secret is not configured',
      );
    }

    final headers = normalizeHttpHeaders(request.headers);
    if (!isBackendScoringCommandAuthorized(
      headers,
      expectedSecrets: commandSecrets,
    )) {
      logScheduledFixtureDownload('request authorization failed');
      throw PermissionDeniedError('Unauthorized scheduled fixture request');
    }
    logScheduledFixtureDownload('request authorized; opening database');

    final dbHandle = await _openBackendScoringDatabase(
      runtimeAdminApp: runtimeAdminApp,
    );
    logScheduledFixtureDownload('database opened');
    try {
      final result = await executeScheduledFixtureDownload(
        db: dbHandle.database,
        fetchFixtureJson: _fetchFixtureJson,
        now: DateTime.now().toUtc(),
        afterSuccessfulDownload: (comp, now) => _afterSuccessfulFixtureDownload(
          db: dbHandle.database,
          comp: comp,
          now: now,
        ),
      );
      logScheduledFixtureDownload(
        'completed with status=${result.outcome.apiValue}',
      );
      return Response.ok(
        jsonEncode(<String, dynamic>{
          'success': true,
          'status': result.outcome.apiValue,
          'message': result.message,
        }),
        headers: _jsonHeaders,
      );
    } finally {
      await dbHandle.close();
    }
  } on PermissionDeniedError catch (error) {
    return _backendScoringErrorResponse(
      403,
      'PERMISSION_DENIED',
      error.toString(),
    );
  } on InvalidArgumentError catch (error) {
    return _backendScoringErrorResponse(
      400,
      'INVALID_ARGUMENT',
      error.toString(),
    );
  } on UnauthenticatedError catch (error) {
    return _backendScoringErrorResponse(
      401,
      'UNAUTHENTICATED',
      error.toString(),
    );
  } on NotFoundError catch (error) {
    return _backendScoringErrorResponse(
      404,
      'NOT_FOUND',
      error.toString(),
    );
  } on AbortedError catch (error) {
    return _backendScoringErrorResponse(
      503,
      'UNAVAILABLE',
      error.toString(),
    );
  } on InternalError catch (error) {
    return _backendScoringErrorResponse(
      500,
      'INTERNAL',
      error.toString(),
    );
  } catch (error, stackTrace) {
    logScheduledFixtureDownload(
      'unhandled error: $error\n$stackTrace',
    );
    return _backendScoringErrorResponse(
      500,
      'INTERNAL',
      'An unexpected error occurred.',
    );
  }
}

Map<String, String> normalizeHttpHeaders(Object? rawHeaders) {
  if (rawHeaders is! Map) {
    return const <String, String>{};
  }

  final headers = <String, String>{};
  for (final entry in rawHeaders.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String) {
      continue;
    }
    if (value is String) {
      headers[key] = value;
    } else if (value is Iterable) {
      headers[key] = value.whereType<String>().join(',');
    }
  }
  return headers;
}

enum FixtureDownloadOutcome {
  nothingToDo,
  applied,
}

extension FixtureDownloadOutcomeApi on FixtureDownloadOutcome {
  String get apiValue => switch (this) {
        FixtureDownloadOutcome.nothingToDo => 'nothing_to_do',
        FixtureDownloadOutcome.applied => 'applied',
      };
}

class FixtureDownloadResult {
  const FixtureDownloadResult({
    required this.outcome,
    required this.message,
  });

  final FixtureDownloadOutcome outcome;
  final String message;
}

Future<void> _afterSuccessfulFixtureDownload({
  required dynamic db,
  required DAUComp comp,
  required DateTime now,
}) async {
  await _triggerBackendScoringAdminRescore(
    compKey: comp.dbkey!,
    now: now,
  );
  await _deleteStaleTokens(db);
}

Future<void> _triggerBackendScoringAdminRescore({
  required String compKey,
  required DateTime now,
}) async {
  final commandUrl = resolveBackendScoringCommandUrl();
  if (commandUrl == null || commandUrl.isEmpty) {
    throw InternalError('Backend scoring command URL is not configured');
  }

  final commandSecret = resolveBackendScoringCommandSecret();
  if (commandSecret == null || commandSecret.isEmpty) {
    throw InternalError('Backend scoring command secret is not configured');
  }

  final sourceEventId =
      'fixture_download_${compKey}_${now.microsecondsSinceEpoch}';
  final command = BackendScoringCommand(
    commandType: BackendScoringCommandType.adminRescore,
    compKey: compKey,
    roundNumber: null,
    tipperId: null,
    gameKey: null,
    sourceEventId: sourceEventId,
    sourcePath: '/admin/fixtureDownload',
    scopeKey: 'comp:$compKey/all_rounds/all_tippers',
    commandId: _buildBackendScoringCommandId(sourceEventId),
  );

  logFunction(
    'executeFixtureDownload: triggering backend scoring admin rescore '
    'for compKey=$compKey',
  );
  final response = await http.post(
    Uri.parse(commandUrl),
    headers: <String, String>{
      ..._jsonHeaders,
      _backendScoringCommandSecretHeader: commandSecret,
    },
    body: jsonEncode(<String, dynamic>{
      'command': command.toJson(),
    }),
  );

  if (response.statusCode != 200) {
    throw InternalError(
      'Backend scoring command failed with HTTP ${response.statusCode}: ${response.body}',
    );
  }
  logFunction(
    'executeFixtureDownload: triggered backend scoring admin rescore '
    'for compKey=$compKey',
  );
}

Future<void> _deleteStaleTokens(dynamic db) async {
  try {
    final snapshot = await db.ref(paths.tokensPath).once();
    final rawTokens = snapshot.value;
    if (rawTokens is! Map) {
      return;
    }

    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final staleThreshold = nowMillis - const Duration(days: 30).inMilliseconds;
    var deletedCount = 0;

    for (final userEntry in rawTokens.entries) {
      final userKey = userEntry.key;
      final userTokens = userEntry.value;
      if (userKey is! String || userKey.isEmpty || userTokens is! Map) {
        continue;
      }

      for (final tokenEntry in userTokens.entries) {
        final tokenKey = tokenEntry.key;
        final tokenValue = tokenEntry.value;
        if (tokenKey is! String ||
            tokenKey.isEmpty ||
            tokenValue is! String ||
            tokenValue.isEmpty) {
          continue;
        }

        final tokenMillis =
            DateTime.tryParse(tokenValue)?.millisecondsSinceEpoch;
        if (tokenMillis != null && tokenMillis < staleThreshold) {
          await db
              .ref(paths.tokensPath)
              .child(userKey)
              .child(tokenKey)
              .remove();
          deletedCount += 1;
        }
      }
    }

    developer.log(
      'Fixture download token cleanup removed $deletedCount stale tokens',
      name: 'fixtureDownloadCleanup',
    );
  } catch (error, stackTrace) {
    developer.log(
      'Fixture download token cleanup failed',
      name: 'fixtureDownloadCleanup',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

String _buildBackendScoringCommandId(String sourceEventId) {
  return 'event_${base64Url.encode(utf8.encode(sourceEventId))}';
}

Future<String> _readCurrentDauCompKey(dynamic db) async {
  final value = await readDatabaseValue(
    db,
    '${paths.configPathRoot}/${paths.currentDAUCompKey}',
  );
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw NotFoundError('Current DAU comp is not configured');
}

Future<Object?> readDatabaseValue(dynamic db, String path) async {
  final reference = db.ref(path);
  final snapshot = await reference.once();
  return snapshot.value;
}

Future<DAUComp> _loadFixtureDownloadComp(
  dynamic db,
  String compKey,
) async {
  final compRaw = await readDatabaseValue(
    db,
    '${paths.daucompsPath}/$compKey',
  );
  if (compRaw == null) {
    throw NotFoundError('DAUComp not found for key: $compKey');
  }

  final compData = Map<String, dynamic>.from(compRaw as Map);
  final dauroundsList = _deserializeCombinedRounds(compData);
  return DAUComp.fromJson(compData, compKey, dauroundsList);
}

Future<bool> _hasStartedResultNotKnownGames({
  required dynamic db,
  required String compKey,
  required DateTime now,
}) async {
  final gamesRef = db.ref('${paths.gamesPathRoot}/$compKey');
  final snapshot = await gamesRef.once();
  final rawGames = snapshot.value;
  if (rawGames is! Map) {
    return false;
  }

  for (final gameEntry in rawGames.entries) {
    final rawGame = gameEntry.value;
    if (rawGame is! Map) {
      continue;
    }

    final dateUtcRaw = rawGame['DateUtc'];
    if (dateUtcRaw is! String) {
      continue;
    }

    final dateUtc = DateTime.tryParse(dateUtcRaw);
    if (dateUtc == null || !dateUtc.isBefore(now)) {
      continue;
    }

    final homeScore = rawGame['HomeTeamScore'];
    final awayScore = rawGame['AwayTeamScore'];
    if (homeScore == null || awayScore == null) {
      return true;
    }
  }

  return false;
}

Future<void> _writeFixtureDownloadStatus(
  dynamic db,
  String compKey, {
  required String state,
  required DateTime now,
  required String triggeredBy,
  String? message,
  String? error,
  DateTime? lastAppliedAt,
}) async {
  final statusRef = db.ref('${paths.statsPathRoot}/$compKey/${paths.scoringStatusKey}');
  final status = <String, dynamic>{
    'state': state,
    'inProgress': state == 'downloading',
    'triggeredBy': triggeredBy,
    'lastCheckedAt': now.toIso8601String(),
  };
  if (lastAppliedAt != null) {
    status['lastAppliedAt'] = lastAppliedAt.toIso8601String();
  }
  if (message != null) {
    status['message'] = message;
  }
  if (error != null) {
    status['error'] = error;
  }
  await statusRef.set(status);
}

abstract class _BackendScoringDatabaseHandle {
  dynamic ref(String path);

  Future<void> close();

  dynamic get database => this;
}

class _AdminBackendScoringDatabaseHandle
    extends _BackendScoringDatabaseHandle {
  _AdminBackendScoringDatabaseHandle(this._adminApp);

  final dynamic _adminApp;

  @override
  dynamic ref(String path) => _adminApp.database().ref(path);

  @override
  Future<void> close() => _adminApp.delete();
}

class _StandaloneBackendScoringDatabaseHandle
    extends _BackendScoringDatabaseHandle {
  _StandaloneBackendScoringDatabaseHandle(this._database);

  final StandaloneFirebaseDatabase _database;

  @override
  dynamic ref(String path) {
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    DatabaseReference ref = _database.reference();
    for (final segment in segments) {
      ref = ref.child(segment);
    }
    return ref;
  }

  @override
  Future<void> close() => _database.delete();
}

class _RestBackendScoringDatabaseHandle extends _BackendScoringDatabaseHandle {
  _RestBackendScoringDatabaseHandle(this._client, this._databaseUrl);

  final dynamic _client;
  final String _databaseUrl;

  static Future<_RestBackendScoringDatabaseHandle> create({
    required dynamic runtimeAdminApp,
    required String databaseUrl,
  }) async {
    final client = await runtimeAdminApp.client;
    return _RestBackendScoringDatabaseHandle(client, databaseUrl);
  }

  @override
  dynamic ref(String path) => _RestDatabaseReference(
        client: _client,
        databaseUrl: _databaseUrl,
        path: path,
      );

  @override
  Future<void> close() async {}
}

class _RestDatabaseReference {
  _RestDatabaseReference({
    required dynamic client,
    required String databaseUrl,
    required String path,
  })  : _client = client,
        _databaseUrl = databaseUrl,
        _path = path;

  final dynamic _client;
  final String _databaseUrl;
  final String _path;
  static const Duration _requestTimeout = Duration(seconds: 15);

  String? get _key {
    final segments = _path.split('/').where((segment) => segment.isNotEmpty);
    return segments.isEmpty ? null : segments.last;
  }

  Future<DataSnapshot> once() async {
    final response = await runRtdbRestRequest(
      _client.get(_uri()),
      operation: 'read',
      path: _path,
    );
    _throwForRestError(response, 'read', _path);
    return _RestDataSnapshot(_key, _decodeRestBody(response.body as String));
  }

  Future<void> set(dynamic value) async {
    final response = await runRtdbRestRequest(
      _client.put(
        _uri(),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(value),
      ),
      operation: 'set',
      path: _path,
    );
    _throwForRestError(response, 'set', _path);
  }

  Future<void> update(Map<dynamic, dynamic> value) async {
    final response = await runRtdbRestRequest(
      _client.patch(
        _uri(),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(value),
      ),
      operation: 'update',
      path: _path,
    );
    _throwForRestError(response, 'update', _path);
  }

  Future<TransactionResult> runTransaction(
    TransactionHandler transactionHandler, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var attempts = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempts += 1;
      final readResponse = await runRtdbRestRequest(
        _client.get(
          _uri(),
          headers: const {'X-Firebase-ETag': 'true'},
        ),
        operation: 'transaction read',
        path: _path,
        timeout: _remainingTransactionTime(deadline, attempts),
      );
      _throwForRestError(readResponse, 'transaction read', _path);
      final etag = readResponse.headers['etag'] as String?;
      final currentValue = _decodeRestBody(readResponse.body as String);
      final mutableData = MutableData(_key, currentValue);
      final updatedData = await transactionHandler(mutableData);
      if (updatedData == null) {
        return _RestTransactionResult(
          committed: false,
          dataSnapshot: _RestDataSnapshot(_key, currentValue),
        );
      }

      final writeResponse = await runRtdbRestRequest(
        _client.put(
          _uri(),
          headers: {
            'content-type': 'application/json',
            'if-match': etag ?? '*',
          },
          body: jsonEncode(updatedData.value),
        ),
        operation: 'transaction write',
        path: _path,
        timeout: _remainingTransactionTime(deadline, attempts),
      );
      if (writeResponse.statusCode == 412) {
        continue;
      }
      _throwForRestError(writeResponse, 'transaction write', _path);
      return _RestTransactionResult(
        committed: true,
        dataSnapshot: _RestDataSnapshot(
          _key,
          _decodeRestBody(writeResponse.body as String),
        ),
      );
    }

    throw AbortedError(
      'RTDB transaction timed out at $_path after $attempts attempts',
    );
  }

  Duration _remainingTransactionTime(DateTime deadline, int attempts) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw AbortedError(
        'RTDB transaction timed out at $_path after $attempts attempts',
      );
    }
    return remaining < _requestTimeout ? remaining : _requestTimeout;
  }

  Uri _uri() {
    return buildRtdbRestUri(databaseUrl: _databaseUrl, path: _path);
  }
}

Uri buildRtdbRestUri({
  required String databaseUrl,
  required String path,
}) {
  final baseUri = Uri.parse(databaseUrl);
  final databasePathSegments = baseUri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  final referencePathSegments =
      path.split('/').where((segment) => segment.isNotEmpty).toList();
  final restPathSegments = referencePathSegments.isEmpty
      ? const ['.json']
      : [
          ...referencePathSegments.take(referencePathSegments.length - 1),
          '${referencePathSegments.last}.json',
        ];

  return baseUri.replace(
    pathSegments: [...databasePathSegments, ...restPathSegments],
  );
}

Future<T> runRtdbRestRequest<T>(
  Future<T> request, {
  required String operation,
  required String path,
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    return await request.timeout(timeout);
  } on TimeoutException {
    throw UnavailableError(
      'RTDB REST $operation timed out after '
      '${timeout.inMilliseconds}ms at $path',
    );
  }
}

class _RestDataSnapshot implements DataSnapshot {
  _RestDataSnapshot(this.key, this.value);

  @override
  final String? key;

  @override
  final dynamic value;
}

class _RestTransactionResult implements TransactionResult {
  _RestTransactionResult({
    required this.committed,
    required this.dataSnapshot,
  });

  @override
  final bool committed;

  @override
  final DataSnapshot? dataSnapshot;

  @override
  FirebaseDatabaseException? get error => null;
}

dynamic _decodeRestBody(String body) {
  if (body.isEmpty) {
    return null;
  }
  return jsonDecode(body);
}

void _throwForRestError(dynamic response, String operation, String path) {
  final statusCode = response.statusCode as int;
  if (statusCode >= 200 && statusCode < 300) {
    return;
  }
  throw InternalError(
    'RTDB REST $operation failed for $path with HTTP $statusCode: '
    '${response.body}',
  );
}

class _RuntimeAdminCredential implements Credential {
  _RuntimeAdminCredential(this._runtimeAdminApp);

  final dynamic _runtimeAdminApp;

  @override
  Future<AccessToken> getAccessToken() async {
    final client = await _runtimeAdminApp.client;
    final token = client.credentials.accessToken;
    return _RuntimeAccessToken(
      token.data as String,
      token.expiry as DateTime,
    );
  }
}

class _RuntimeAccessToken implements AccessToken {
  _RuntimeAccessToken(this.accessToken, this.expirationTime);

  @override
  final String accessToken;

  @override
  final DateTime expirationTime;
}

dynamic _initializeLegacyAdminApp(
  dynamic runtimeAdminApp, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final Credential? credential = runtimeAdminApp == null
      ? Credentials.applicationDefault()
      : _RuntimeAdminCredential(runtimeAdminApp);
  if (credential == null) {
    throw InternalError('Failed to load application default credentials');
  }

  final appName = 'legacy-rtdb-${DateTime.now().microsecondsSinceEpoch}';
  return FirebaseAdmin.instance.initializeApp(
    AppOptions(
      credential: credential,
      databaseUrl: resolveDatabaseUrl(environment: env),
      projectId: resolveProjectId(environment: env),
    ),
    appName,
  );
}

Future<_BackendScoringDatabaseHandle> _openBackendScoringDatabase({
  dynamic runtimeAdminApp,
}) async {
  final env = Platform.environment;
  final emulatorHost = env['FIREBASE_DATABASE_EMULATOR_HOST'];
  if (emulatorHost != null && emulatorHost.isNotEmpty) {
    final db = StandaloneFirebaseDatabase(
      resolveDatabaseUrl(environment: env),
    );
    await db.authenticate('owner');
    developer.log(
      'backendScoringCommand: using standalone RTDB emulator client',
      name: 'backendScoringCommand',
    );
    return _StandaloneBackendScoringDatabaseHandle(db);
  }

  if (runtimeAdminApp != null) {
    developer.log(
      'backendScoringCommand: using RTDB REST client',
      name: 'backendScoringCommand',
    );
    return _RestBackendScoringDatabaseHandle.create(
      runtimeAdminApp: runtimeAdminApp,
      databaseUrl: resolveDatabaseUrl(environment: env),
    );
  }

  final adminApp = _initializeLegacyAdminApp(null, environment: env);
  developer.log(
    'backendScoringCommand: using runtime Firebase Admin SDK client',
    name: 'backendScoringCommand',
  );
  return _AdminBackendScoringDatabaseHandle(adminApp);
}

Future<FixtureDownloadResult> executeScheduledFixtureDownload({
  required dynamic db,
  required Future<List<dynamic>> Function(Uri url) fetchFixtureJson,
  required DateTime now,
  Future<void> Function(DAUComp comp, DateTime now)? afterSuccessfulDownload,
}) async {
  final compKey = await _readCurrentDauCompKey(db);
  final comp = await _loadFixtureDownloadComp(db, compKey);
  final shouldTrigger = await _hasStartedResultNotKnownGames(
    db: db,
    compKey: compKey,
    now: now,
  );
  if (!shouldTrigger) {
    await _writeFixtureDownloadStatus(
      db,
      compKey,
      state: 'nothing_to_do',
      now: now,
      triggeredBy: 'scheduler',
      message:
          'No started games without fixture results were found for ${comp.name}.',
    );
    return FixtureDownloadResult(
      outcome: FixtureDownloadOutcome.nothingToDo,
      message:
          'Nothing to do. No started games without fixture results were found for ${comp.name}.',
    );
  }

  return _executeFixtureDownloadCore(
    comp: comp,
    db: db,
    fetchFixtureJson: fetchFixtureJson,
    now: now,
    triggeredBy: 'scheduler',
    afterSuccessfulDownload: afterSuccessfulDownload,
  );
}

Future<String> executeFixtureDownload({
  required String authUid,
  required String compKey,
  required dynamic db,
  required Future<List<dynamic>> Function(Uri url) fetchFixtureJson,
  required DateTime now,
  Future<void> Function(DAUComp comp, DateTime now)? afterSuccessfulDownload,
}) async {
  logFunction('executeFixtureDownload: checking admin role for authUid=$authUid');
  final roleSnapshot = await db.ref(paths.tippersPath).once();
  final role = resolveTipperRoleForAuthUid(roleSnapshot.value, authUid);
  if (role == null) {
    logFunction('executeFixtureDownload: no AllTippers record for authUid=$authUid');
    throw PermissionDeniedError('User is not authorized as admin');
  }
  logFunction('executeFixtureDownload: resolved role=$role');
  if (role != 'admin') {
    throw PermissionDeniedError('User is not authorized as admin');
  }

  final comp = await _loadFixtureDownloadComp(db, compKey);
  final result = await _executeFixtureDownloadCore(
    comp: comp,
    db: db,
    fetchFixtureJson: fetchFixtureJson,
    now: now,
    triggeredBy: 'admin',
    afterSuccessfulDownload: afterSuccessfulDownload,
  );
  return result.message;
}

typedef BackendScoringCommandExecutor = Future<BackendScoringCommandResult>
    Function({
  required dynamic db,
  required BackendScoringCommand command,
  required DateTime now,
});

Future<BackendScoringCommandResult> executeAdminScoringRescore({
  required String authUid,
  required String compKey,
  required dynamic db,
  required DateTime now,
  BackendScoringCommandExecutor executeCommand = executeBackendScoringCommand,
}) async {
  final roleSnapshot = await db.ref(paths.tippersPath).once();
  final role = resolveTipperRoleForAuthUid(roleSnapshot.value, authUid);
  if (role != 'admin') {
    throw PermissionDeniedError('User is not authorized as admin');
  }

  final sourceEventId = 'admin_rescore_${compKey}_${now.microsecondsSinceEpoch}';
  return executeCommand(
    db: db,
    command: BackendScoringCommand(
      commandType: BackendScoringCommandType.adminRescore,
      compKey: compKey,
      roundNumber: null,
      tipperId: null,
      gameKey: null,
      sourceEventId: sourceEventId,
      sourcePath: '/admin/scoringRescore',
      scopeKey: 'comp:$compKey/all_rounds/all_tippers',
      commandId: _buildBackendScoringCommandId(sourceEventId),
    ),
    now: now,
  );
}

typedef FixtureUrlChecker = Future<bool> Function(Uri url);
typedef FixtureUrlHostResolver =
    Future<List<InternetAddress>> Function(String host);

const Set<String> _blockedFixtureUrlHostnames = {
  'localhost',
  'metadata',
  'metadata.google.internal',
};

Future<bool> checkFixtureUrlActive({
  required String authUid,
  required String url,
  required dynamic db,
  FixtureUrlChecker? checkUrl,
  FixtureUrlHostResolver resolveHost = InternetAddress.lookup,
}) async {
  final roleSnapshot = await db.ref(paths.tippersPath).once();
  final role = resolveTipperRoleForAuthUid(roleSnapshot.value, authUid);
  if (role != 'admin') {
    throw PermissionDeniedError('User is not authorized as admin');
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw InvalidArgumentError('url must be a valid absolute URL');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw InvalidArgumentError('url must use http or https');
  }

  if (!await isAllowedFixtureUrlHost(uri, resolveHost: resolveHost)) {
    throw InvalidArgumentError('url host is not allowed');
  }

  final checker =
      checkUrl ??
      (target) => fetchFixtureUrlActive(target, resolveHost: resolveHost);
  return checker(uri);
}

/// Rejects hosts that would let an authenticated admin use this
/// server-side fetch as an SSRF probe of internal infrastructure (the cloud
/// metadata service, loopback, or other private-network addresses).
Future<bool> isAllowedFixtureUrlHost(
  Uri uri, {
  FixtureUrlHostResolver resolveHost = InternetAddress.lookup,
}) async {
  final host = uri.host.toLowerCase();
  if (host.isEmpty || _blockedFixtureUrlHostnames.contains(host)) {
    return false;
  }

  final literal = InternetAddress.tryParse(host);
  if (literal != null) {
    return !isDisallowedFixtureUrlAddress(literal);
  }

  try {
    final addresses = await resolveHost(host);
    if (addresses.isEmpty) {
      return false;
    }
    return addresses.every(
      (address) => !isDisallowedFixtureUrlAddress(address),
    );
  } catch (_) {
    return false;
  }
}

bool isDisallowedFixtureUrlAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }

  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
    if (bytes[0] == 0) return true; // 0.0.0.0/8
    if (bytes[0] == 10) return true; // 10.0.0.0/8
    if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) {
      return true; // 172.16.0.0/12
    }
    if (bytes[0] == 192 && bytes[1] == 168) return true; // 192.168.0.0/16
  }
  if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
    if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique local
  }

  return false;
}

/// Maximum number of redirect hops to follow — matches dart:io's own
/// default [HttpClientRequest.maxRedirects].
const int maxFixtureUrlRedirectHops = 5;

class FixtureUrlHopResult {
  final int statusCode;
  final String? redirectLocation;
  const FixtureUrlHopResult({required this.statusCode, this.redirectLocation});
}

typedef FixtureUrlHopFetcher = Future<FixtureUrlHopResult> Function(Uri uri);

/// Fetches [url], following redirects manually so that every hop — not
/// just the initially submitted URL — is checked against
/// [isAllowedFixtureUrlHost]. A plain `http.get` follows redirects
/// transparently, which would let a public URL redirect to a private or
/// cloud-metadata address and bypass the SSRF guard in [checkFixtureUrlActive].
Future<bool> fetchFixtureUrlActive(
  Uri url, {
  FixtureUrlHostResolver resolveHost = InternetAddress.lookup,
  FixtureUrlHopFetcher fetchHop = _requestFixtureUrlHop,
}) async {
  var currentUri = url;
  for (var hop = 0; hop <= maxFixtureUrlRedirectHops; hop++) {
    if (!await isAllowedFixtureUrlHost(currentUri, resolveHost: resolveHost)) {
      return false;
    }

    try {
      final result = await fetchHop(currentUri);
      if (result.statusCode >= 300 && result.statusCode < 400) {
        final location = result.redirectLocation;
        if (location == null) {
          return false;
        }
        currentUri = currentUri.resolve(location);
        continue;
      }
      return result.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  return false; // Exceeded maxFixtureUrlRedirectHops.
}

Future<FixtureUrlHopResult> _requestFixtureUrlHop(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 10));
    final location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();
    return FixtureUrlHopResult(
      statusCode: response.statusCode,
      redirectLocation: location,
    );
  } finally {
    client.close(force: true);
  }
}

String? resolveTipperRoleForAuthUid(Object? rawTippers, String authUid) {
  if (rawTippers is! Map) {
    return null;
  }

  String? resolvedRole;
  var matchCount = 0;
  for (final rawTipper in rawTippers.values) {
    if (rawTipper is! Map || rawTipper['authuid'] != authUid) {
      continue;
    }
    matchCount += 1;
    if (matchCount > 1) {
      return null;
    }
    final role = rawTipper['tipperRole'];
    if (role is! String) {
      return null;
    }
    resolvedRole = role;
  }
  return resolvedRole;
}

Future<FixtureDownloadResult> _executeFixtureDownloadCore({
  required DAUComp comp,
  required dynamic db,
  required Future<List<dynamic>> Function(Uri url) fetchFixtureJson,
  required DateTime now,
  required String triggeredBy,
  Future<void> Function(DAUComp comp, DateTime now)? afterSuccessfulDownload,
}) async {
  final compKey = comp.dbkey!;

  logFunction('executeFixtureDownload: loading compKey=$compKey');

  final lockRef = db.ref(
    '${paths.daucompsPath}/$compKey/${paths.downloadLockKey}',
  );
  TransactionResult transactionResult;
  try {
    transactionResult = await lockRef.runTransaction((MutableData mutableData) {
      final currentValue = mutableData.value;
      if (currentValue != null) {
        DateTime? lockTimestamp;
        if (currentValue is String) {
          lockTimestamp = DateTime.tryParse(currentValue);
        }
        if (lockTimestamp != null) {
          if (now.difference(lockTimestamp) < _fixtureDownloadLockTtl) {
            return null;
          }
        }
      }
      mutableData.value = now.toIso8601String();
      return mutableData;
    });
  } catch (e) {
    throw AbortedError('Fixture download failed to acquire lock: $e');
  }

  if (!transactionResult.committed) {
    logFunction('executeFixtureDownload: lock already held for compKey=$compKey');
    throw AbortedError('Fixture download is already in progress.');
  }
  logFunction('executeFixtureDownload: lock acquired for compKey=$compKey');

  try {
    await _writeFixtureDownloadStatus(
      db,
      compKey,
      state: 'downloading',
      now: now,
      triggeredBy: triggeredBy,
      message: 'Downloading fixtures...',
    );

    logFunction('executeFixtureDownload: fetching NRL fixture ${comp.nrlFixtureJsonURL}');
    final nrlGames = await fetchFixtureJson(comp.nrlFixtureJsonURL);
    logFunction('executeFixtureDownload: fetching AFL fixture ${comp.aflFixtureJsonURL}');
    final aflGames = await fetchFixtureJson(comp.aflFixtureJsonURL);

    await _writeFixtureDownloadStatus(
      db,
      compKey,
      state: 'downloading',
      now: now,
      triggeredBy: triggeredBy,
      message: 'Applying fixture updates...',
    );

    final importApplier = const FixtureImportApplier();
    final ops = importApplier.buildGameUpdates(nrlGames, aflGames);

    final dbUpdates = <String, dynamic>{};

    final teamsValue = await readDatabaseValue(db, paths.teamsPathRoot);
    final Map<String, dynamic> existingTeams = teamsValue != null
        ? Map<String, dynamic>.from(teamsValue as Map)
        : {};
    final existingTeamKeys =
        existingTeams.keys.map((key) => key.toLowerCase()).toSet();

    void ensureTeamExists(String teamName, String league) {
      final teamKey = '$league-${_normalizeTeamLookupName(teamName)}';
      if (existingTeamKeys.add(teamKey.toLowerCase())) {
        dbUpdates['${paths.teamsPathRoot}/$teamKey'] = {
          'name': teamName.trim(),
          'league': league,
          'logoURI': null,
        };
      }
    }

    for (final op in ops) {
      for (final entry in op.attributes.entries) {
        dbUpdates[
            '${paths.gamesPathRoot}/$compKey/${op.dbkey}/${entry.key}'] =
            entry.value;
      }
      if (op.attributes['HomeTeamScore'] != null &&
          op.attributes['AwayTeamScore'] != null) {
        dbUpdates[
            '${paths.statsPathRoot}/$compKey/${paths.liveScoresBackendRoot}/${op.dbkey}'] =
            null;
      }
      final homeTeam = op.attributes['HomeTeam'] as String?;
      final awayTeam = op.attributes['AwayTeam'] as String?;
      if (homeTeam != null) ensureTeamExists(homeTeam, op.league);
      if (awayTeam != null) ensureTeamExists(awayTeam, op.league);
    }

    importApplier.tagGamesWithLeagueInPlace(nrlGames, 'nrl');
    importApplier.tagGamesWithLeagueInPlace(aflGames, 'afl');

    final allGames = [...nrlGames, ...aflGames];
    final combined = importApplier.computeCombinedRoundsIfMissing(comp, allGames);
    if (combined != null) {
      for (var i = 0; i < combined.length; i++) {
        final round = combined[i];
        final startDateStr = '${DateFormat('yyyy-MM-dd HH:mm:ss').format(round.firstGameKickOffUTC)}Z';
        final endDateStr = '${DateFormat('yyyy-MM-dd HH:mm:ss').format(round.lastGameKickOffUTC)}Z';
        dbUpdates[
            '${paths.daucompsPath}/$compKey/${paths.combinedRoundsPath}/$i/'
            '${paths.roundStartDateKey}'] = startDateStr;
        dbUpdates[
            '${paths.daucompsPath}/$compKey/${paths.combinedRoundsPath}/$i/'
            '${paths.roundEndDateKey}'] = endDateStr;
      }
    }

    dbUpdates[
        '${paths.daucompsPath}/$compKey/${paths.lastFixtureUTCKey}'] =
        now.toIso8601String();

    logFunction('executeFixtureDownload: applying ${dbUpdates.length} database updates');
    await db.ref('/').update(dbUpdates);

    if (afterSuccessfulDownload != null) {
      await afterSuccessfulDownload(comp, now);
    }

    try {
      final prunedCount =
          await pruneExpiredBackendScoringIdempotencyRecords(
        compKey: compKey,
        db: db,
        now: now,
      );
      logFunction(
        'executeFixtureDownload: pruned $prunedCount expired backend scoring '
        'idempotency records',
      );
    } catch (e) {
      logFunction(
        'executeFixtureDownload: backend scoring idempotency prune failed: $e',
      );
    }

    final message =
        'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    await _writeFixtureDownloadStatus(
      db,
      compKey,
      state: 'applied',
      now: now,
      triggeredBy: triggeredBy,
      lastAppliedAt: now,
      message: message,
    );
    return FixtureDownloadResult(
      outcome: FixtureDownloadOutcome.applied,
      message: message,
    );
  } catch (e) {
    logFunction('executeFixtureDownload: failed with $e');
    try {
      await _writeFixtureDownloadStatus(
        db,
        compKey,
        state: 'failed',
        now: now,
        triggeredBy: triggeredBy,
        error: e.toString(),
        message: 'Fixture download failed.',
      );
    } catch (_) {}
    rethrow;
  } finally {
    await lockRef.set(null);
  }
}

Future<int> pruneExpiredBackendScoringIdempotencyRecords({
  required String compKey,
  required dynamic db,
  required DateTime now,
  int limit = _idempotencyPruneLimit,
}) async {
  if (limit <= 0) {
    return 0;
  }

  final idempotencyRef = db.ref(
    '${paths.statsPathRoot}/$compKey/'
    '${paths.scoringIdempotencyBackendRoot}',
  );
  final snapshot = await idempotencyRef.once();
  final rawRecords = snapshot.value;
  if (rawRecords is! Map) {
    return 0;
  }

  final updates = <String, dynamic>{};
  void collectExpired(dynamic rawValue, String relativePath) {
    if (updates.length >= limit || rawValue is! Map) {
      return;
    }

    final value = Map<dynamic, dynamic>.from(rawValue);
    final expiresAtRaw = value['expiresAt'];
    if (expiresAtRaw is String) {
      final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
      if (expiresAt != null && !expiresAt.isAfter(now.toUtc())) {
        updates[relativePath] = null;
      }
      return;
    }

    for (final entry in value.entries) {
      if (updates.length >= limit) {
        return;
      }
      final key = entry.key;
      if (key is! String || key.isEmpty) {
        continue;
      }
      final childPath = relativePath.isEmpty ? key : '$relativePath/$key';
      collectExpired(entry.value, childPath);
    }
  }

  collectExpired(rawRecords, '');
  if (updates.isEmpty) {
    return 0;
  }

  await idempotencyRef.update(updates);
  return updates.length;
}

Future<List<dynamic>> _fetchFixtureJson(Uri url) async {
  final response = await http
      .get(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
      )
      .timeout(const Duration(seconds: 30));
  if (response.statusCode == 200) {
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is List) {
      return decoded;
    }
    throw Exception('Expected list, got ${decoded.runtimeType}');
  }
  throw Exception('Failed to fetch fixture from $url: ${response.statusCode}');
}

const Duration _backendIdempotencyTtl = Duration(hours: 24);

const Map<String, String> _jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
};

class BackendScoringCommandResult {
  final String status;
  final bool skipped;
  final String commandId;
  final String commandType;
  final String scopeKey;
  final String compKey;
  final String message;

  const BackendScoringCommandResult({
    required this.status,
    required this.skipped,
    required this.commandId,
    required this.commandType,
    required this.scopeKey,
    required this.compKey,
    required this.message,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status,
    'skipped': skipped,
    'commandId': commandId,
    'commandType': commandType,
    'scopeKey': scopeKey,
    'compKey': compKey,
    'message': message,
  };
}

Future<BackendScoringCommandResult> executeBackendScoringCommand({
  required dynamic db,
  required BackendScoringCommand command,
  required DateTime now,
}) async {
  switch (command.commandType) {
    case BackendScoringCommandType.tipWritten:
      return _handleTipWrittenBackendScoringCommand(
        db: db,
        command: command,
        now: now,
      );
    case BackendScoringCommandType.officialScoreWritten:
      return _handleOfficialScoreWrittenBackendScoringCommand(
        db: db,
        command: command,
        now: now,
      );
    case BackendScoringCommandType.adminRescore:
      return _handleAdminRescoreBackendScoringCommand(
        db: db,
        command: command,
        now: now,
      );
    case BackendScoringCommandType.liveScoreWritten:
      return _handleOfficialScoreWrittenBackendScoringCommand(
        db: db,
        command: command,
        now: now,
      );
  }
}

class _BackendScoringLockResult {
  final bool acquired;
  final BackendScoringIdempotencyRecord startedRecord;
  final BackendScoringIdempotencyRecord? existingRecord;
  final String? skipMessage;

  const _BackendScoringLockResult({
    required this.acquired,
    required this.startedRecord,
    this.existingRecord,
    this.skipMessage,
  });
}

Future<_BackendScoringLockResult> _acquireBackendScoringCommandLock({
  required dynamic db,
  required BackendScoringCommand command,
  required DateTime now,
}) async {
  final idempotencyRef = db.ref(
    '${paths.statsPathRoot}/${command.compKey}/'
    '${paths.scoringIdempotencyBackendRoot}/${command.commandId}',
  );
  final startedRecord = BackendScoringIdempotencyRecord(
    status: BackendScoringIdempotencyStatus.started,
    commandId: command.commandId,
    commandType: command.commandType.name,
    compKey: command.compKey,
    sourceEventId: command.sourceEventId,
    sourcePath: command.sourcePath,
    scopeKey: command.scopeKey,
    startedAt: now.toIso8601String(),
    expiresAt: now.add(_backendIdempotencyTtl).toIso8601String(),
  );

  final transactionResult =
      await idempotencyRef.runTransaction((MutableData mutableData) {
    final currentValue = mutableData.value;
    if (currentValue is Map) {
      final existingRecord = BackendScoringIdempotencyRecord.fromJson(
        Map<String, dynamic>.from(currentValue),
      );

      if (existingRecord.status == BackendScoringIdempotencyStatus.completed) {
        return null;
      }

      if (existingRecord.status == BackendScoringIdempotencyStatus.started &&
          !_isIdempotencyExpired(existingRecord, now)) {
        return null;
      }
    }

    mutableData.value = startedRecord.toJson();
    return mutableData;
  });

  if (transactionResult.committed) {
    return _BackendScoringLockResult(
      acquired: true,
      startedRecord: startedRecord,
    );
  }

  final currentSnapshot = await idempotencyRef.once();
  final currentValue = currentSnapshot.value;
  if (currentValue is Map) {
    final existingRecord = BackendScoringIdempotencyRecord.fromJson(
      Map<String, dynamic>.from(currentValue),
    );
    if (existingRecord.status == BackendScoringIdempotencyStatus.completed) {
      return _BackendScoringLockResult(
        acquired: false,
        startedRecord: startedRecord,
        existingRecord: existingRecord,
        skipMessage: 'Command already completed; skipping replay.',
      );
    }

    if (existingRecord.status == BackendScoringIdempotencyStatus.started &&
        !_isIdempotencyExpired(existingRecord, now)) {
      return _BackendScoringLockResult(
        acquired: false,
        startedRecord: startedRecord,
        existingRecord: existingRecord,
        skipMessage: 'Command already in progress; skipping duplicate.',
      );
    }
  }

  throw AbortedError(
    'Failed to acquire idempotency lock for command ${command.commandId}',
  );
}

Future<BackendScoringCommandResult>
_handleTipWrittenBackendScoringCommand({
  required dynamic db,
  required BackendScoringCommand command,
  required DateTime now,
}) async {
  final lock = await _acquireBackendScoringCommandLock(
    db: db,
    command: command,
    now: now,
  );
  if (!lock.acquired) {
    return BackendScoringCommandResult(
      status: lock.existingRecord?.status.apiValue ?? 'completed',
      skipped: true,
      commandId: command.commandId,
      commandType: command.commandType.name,
      scopeKey: command.scopeKey,
      compKey: command.compKey,
      message: lock.skipMessage ?? 'Command skipped.',
    );
  }

  final startedRecord = lock.startedRecord;
  final idempotencyRef = db.ref(
    '${paths.statsPathRoot}/${command.compKey}/'
    '${paths.scoringIdempotencyBackendRoot}/${command.commandId}',
  );
  final comp = await _loadBackendScoringComp(db, command.compKey);
  final tipper = await _loadBackendScoringTipper(db, command.tipperId!);

  try {
    final games = await _loadBackendScoringGames(
      db: db,
      comp: comp,
    );
    Game? targetGame;
    for (final game in games) {
      if (game.dbkey == command.gameKey) {
        targetGame = game;
        break;
      }
    }
    if (targetGame == null) {
      throw NotFoundError(
        'Game ${command.gameKey} not found for comp ${command.compKey}',
      );
    }

    final roundNumber = targetGame.getDAURound(comp)?.dAUroundNumber;
    if (roundNumber == null) {
      throw NotFoundError(
        'Round for game ${command.gameKey} not found for comp ${command.compKey}',
      );
    }

    final round = _findRoundByNumber(comp, roundNumber);
    if (round == null) {
      throw NotFoundError(
        'Round $roundNumber not found for comp ${command.compKey}',
      );
    }

    final roundGames = games.where((game) {
      final gameRound = game.getDAURound(comp);
      return gameRound?.dAUroundNumber == roundNumber;
    }).toList();

    final tipsByGameKey = await _loadBackendScoringTipsForTipper(
      db: db,
      compKey: command.compKey,
      tipper: tipper,
      gamesByKey: {for (final game in roundGames) game.dbkey: game},
      now: now,
    );

    final roundStats = ScoringCalculator.calculateRoundStatsForTipper(
      roundNumber: roundNumber,
      games: roundGames,
      tipsByGameKey: tipsByGameKey,
      now: now,
    );

    await db
        .ref(
          '${paths.statsPathRoot}/${command.compKey}/'
          '${paths.roundStatsBackendRoot}/$roundNumber/${tipper.dbkey}',
        )
        .set(roundStats.toJson());

    final completedRecord = BackendScoringIdempotencyRecord(
      status: BackendScoringIdempotencyStatus.completed,
      commandId: command.commandId,
      commandType: command.commandType.name,
      compKey: command.compKey,
      sourceEventId: command.sourceEventId,
      sourcePath: command.sourcePath,
      scopeKey: command.scopeKey,
      startedAt: startedRecord.startedAt,
      expiresAt: startedRecord.expiresAt,
      completedAt: now.toIso8601String(),
    );
    await idempotencyRef.set(completedRecord.toJson());
    await db.ref(
      '${paths.statsPathRoot}/${command.compKey}/${paths.scoringStatusKey}',
    ).set(<String, dynamic>{
      'status': 'completed',
      'inProgress': false,
      'commandId': command.commandId,
      'commandType': command.commandType.name,
      'compKey': command.compKey,
      'scopeKey': command.scopeKey,
      'sourceEventId': command.sourceEventId,
      'sourcePath': command.sourcePath,
      'startedAt': startedRecord.startedAt,
      'completedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'message': 'Round stats updated for round $roundNumber tipper ${tipper.dbkey}.',
    });

    return BackendScoringCommandResult(
      status: 'completed',
      skipped: false,
      commandId: command.commandId,
      commandType: command.commandType.name,
      scopeKey: command.scopeKey,
      compKey: command.compKey,
      message: 'Round stats updated for round $roundNumber tipper ${tipper.dbkey}.',
    );
  } catch (error) {
    final failedRecord = BackendScoringIdempotencyRecord(
      status: BackendScoringIdempotencyStatus.failed,
      commandId: command.commandId,
      commandType: command.commandType.name,
      compKey: command.compKey,
      sourceEventId: command.sourceEventId,
      sourcePath: command.sourcePath,
      scopeKey: command.scopeKey,
      startedAt: startedRecord.startedAt,
      expiresAt: startedRecord.expiresAt,
      failedAt: now.toIso8601String(),
      error: error.toString(),
    );
    await idempotencyRef.set(failedRecord.toJson());
    await db.ref(
      '${paths.statsPathRoot}/${command.compKey}/${paths.scoringStatusKey}',
    ).set(<String, dynamic>{
      'status': 'failed',
      'inProgress': false,
      'commandId': command.commandId,
      'commandType': command.commandType.name,
      'compKey': command.compKey,
      'scopeKey': command.scopeKey,
      'sourceEventId': command.sourceEventId,
      'sourcePath': command.sourcePath,
      'startedAt': startedRecord.startedAt,
      'failedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'error': error.toString(),
    });
    rethrow;
  }
}

Future<BackendScoringCommandResult>
_handleOfficialScoreWrittenBackendScoringCommand({
  required dynamic db,
  required BackendScoringCommand command,
  required DateTime now,
}) async {
  final lock = await _acquireBackendScoringCommandLock(
    db: db,
    command: command,
    now: now,
  );
  if (!lock.acquired) {
    return BackendScoringCommandResult(
      status: lock.existingRecord?.status.apiValue ?? 'completed',
      skipped: true,
      commandId: command.commandId,
      commandType: command.commandType.name,
      scopeKey: command.scopeKey,
      compKey: command.compKey,
      message: lock.skipMessage ?? 'Command skipped.',
    );
  }

  final startedRecord = lock.startedRecord;
  final idempotencyRef = db.ref(
    '${paths.statsPathRoot}/${command.compKey}/'
    '${paths.scoringIdempotencyBackendRoot}/${command.commandId}',
  );
  final comp = await _loadBackendScoringComp(db, command.compKey);
  final games = await _loadBackendScoringGames(
    db: db,
    comp: comp,
  );
  Game? targetGame;
  for (final game in games) {
    if (game.dbkey == command.gameKey) {
      targetGame = game;
      break;
    }
  }
  if (targetGame == null) {
    throw NotFoundError(
      'Game ${command.gameKey} not found for comp ${command.compKey}',
    );
  }

  final roundNumber = targetGame.getDAURound(comp)?.dAUroundNumber;
  if (roundNumber == null) {
    throw NotFoundError(
      'Round for game ${command.gameKey} not found for comp ${command.compKey}',
    );
  }

  final round = _findRoundByNumber(comp, roundNumber);
  if (round == null) {
    throw NotFoundError(
      'Round $roundNumber not found for comp ${command.compKey}',
    );
  }

  try {
    final rebuildResult = await _rebuildBackendScoringRound(
      db: db,
      comp: comp,
      games: games,
      roundNumber: roundNumber,
      now: now,
    );

    final completedRecord = BackendScoringIdempotencyRecord(
      status: BackendScoringIdempotencyStatus.completed,
      commandId: command.commandId,
      commandType: command.commandType.name,
      compKey: command.compKey,
      sourceEventId: command.sourceEventId,
      sourcePath: command.sourcePath,
      scopeKey: command.scopeKey,
      startedAt: startedRecord.startedAt,
      expiresAt: startedRecord.expiresAt,
      completedAt: now.toIso8601String(),
    );
    await idempotencyRef.set(completedRecord.toJson());
    await db.ref(
      '${paths.statsPathRoot}/${command.compKey}/${paths.scoringStatusKey}',
    ).set(<String, dynamic>{
      'status': 'completed',
      'inProgress': false,
      'commandId': command.commandId,
      'commandType': command.commandType.name,
      'compKey': command.compKey,
      'scopeKey': command.scopeKey,
      'sourceEventId': command.sourceEventId,
      'sourcePath': command.sourcePath,
      'startedAt': startedRecord.startedAt,
      'completedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'message':
          'Round stats updated for round $roundNumber across ${rebuildResult.tipperCount} tippers.',
    });

    return BackendScoringCommandResult(
      status: 'completed',
      skipped: false,
      commandId: command.commandId,
      commandType: command.commandType.name,
      scopeKey: command.scopeKey,
      compKey: command.compKey,
      message:
          'Round stats updated for round $roundNumber across ${rebuildResult.tipperCount} tippers.',
    );
  } catch (error) {
    final failedRecord = BackendScoringIdempotencyRecord(
      status: BackendScoringIdempotencyStatus.failed,
      commandId: command.commandId,
      commandType: command.commandType.name,
      compKey: command.compKey,
      sourceEventId: command.sourceEventId,
      sourcePath: command.sourcePath,
      scopeKey: command.scopeKey,
      startedAt: startedRecord.startedAt,
      expiresAt: startedRecord.expiresAt,
      failedAt: now.toIso8601String(),
      error: error.toString(),
    );
    await idempotencyRef.set(failedRecord.toJson());
    await db.ref(
      '${paths.statsPathRoot}/${command.compKey}/${paths.scoringStatusKey}',
    ).set(<String, dynamic>{
      'status': 'failed',
      'inProgress': false,
      'commandId': command.commandId,
      'commandType': command.commandType.name,
      'compKey': command.compKey,
      'scopeKey': command.scopeKey,
      'sourceEventId': command.sourceEventId,
      'sourcePath': command.sourcePath,
      'startedAt': startedRecord.startedAt,
      'failedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'error': error.toString(),
    });
    rethrow;
  }
}

Future<BackendScoringCommandResult>
_handleAdminRescoreBackendScoringCommand({
  required dynamic db,
  required BackendScoringCommand command,
  required DateTime now,
}) async {
  final lock = await _acquireBackendScoringCommandLock(
    db: db,
    command: command,
    now: now,
  );
  if (!lock.acquired) {
    return BackendScoringCommandResult(
      status: lock.existingRecord?.status.apiValue ?? 'completed',
      skipped: true,
      commandId: command.commandId,
      commandType: command.commandType.name,
      scopeKey: command.scopeKey,
      compKey: command.compKey,
      message: lock.skipMessage ?? 'Command skipped.',
    );
  }

  final startedRecord = lock.startedRecord;
  final idempotencyRef = db.ref(
    '${paths.statsPathRoot}/${command.compKey}/'
    '${paths.scoringIdempotencyBackendRoot}/${command.commandId}',
  );

  try {
    final comp = await _loadBackendScoringComp(db, command.compKey);
    final games = await _loadBackendScoringGames(
      db: db,
      comp: comp,
    );
    final allTippers = await _loadBackendScoringTippers(db);
    final tipsByTipperRaw = await _loadBackendScoringTipsByTipperRaw(
      db: db,
      compKey: command.compKey,
    );
    final rebuildResults = <_BackendScoringRoundRebuildResult>[];
    final skippedRoundNumbers = <int>[];
    final requestedRoundNumber = command.roundNumber;
    final gameStatsUpdatesSink =
        requestedRoundNumber == null ? <String, dynamic>{} : null;
    if (requestedRoundNumber != null) {
      final round = _findRoundByNumber(comp, requestedRoundNumber);
      if (round == null) {
        throw NotFoundError(
          'Round $requestedRoundNumber not found for comp ${command.compKey}',
        );
      }
      rebuildResults.add(
        await _rebuildBackendScoringRound(
          db: db,
          comp: comp,
          games: games,
          roundNumber: requestedRoundNumber,
          now: now,
          allTippers: allTippers,
          tipsByTipperRaw: tipsByTipperRaw,
          replaceRoundStats: true,
        ),
      );
    } else {
      for (final round in comp.daurounds) {
        final rebuildResult = await _rebuildBackendScoringRound(
          db: db,
          comp: comp,
          games: games,
          roundNumber: round.dAUroundNumber,
          now: now,
          allTippers: allTippers,
          tipsByTipperRaw: tipsByTipperRaw,
          allowEmptyRound: true,
          replaceRoundStats: true,
          gameStatsUpdatesSink: gameStatsUpdatesSink,
        );
        if (rebuildResult.skipped) {
          skippedRoundNumbers.add(round.dAUroundNumber);
        } else {
          rebuildResults.add(rebuildResult);
        }
      }
      await db.ref(
        '${paths.statsPathRoot}/${command.compKey}/'
        '${paths.gameStatsBackendRoot}',
      ).set(
            _nestBackendGameStatsUpdates(gameStatsUpdatesSink),
          );
    }

    final rebuiltRoundNumbers =
        rebuildResults.map((result) => result.roundNumber).toList();
    final rebuiltRoundCount = rebuildResults.length;
    final tipperCount = rebuildResults.isNotEmpty
        ? rebuildResults.first.tipperCount
        : _filterBackendScoringTippersWithSubmittedTips(
            allTippers: allTippers,
            tipsByTipperRaw: tipsByTipperRaw,
          ).length;
    final message = requestedRoundNumber != null
        ? 'Admin rescore completed for round $requestedRoundNumber across $tipperCount tippers.'
        : 'Admin rescore completed for $rebuiltRoundCount rounds across $tipperCount tippers; skipped ${skippedRoundNumbers.length} empty rounds.';

    final completedRecord = BackendScoringIdempotencyRecord(
      status: BackendScoringIdempotencyStatus.completed,
      commandId: command.commandId,
      commandType: command.commandType.name,
      compKey: command.compKey,
      sourceEventId: command.sourceEventId,
      sourcePath: command.sourcePath,
      scopeKey: command.scopeKey,
      startedAt: startedRecord.startedAt,
      expiresAt: startedRecord.expiresAt,
      completedAt: now.toIso8601String(),
    );
    await idempotencyRef.set(completedRecord.toJson());
    await db.ref(
      '${paths.statsPathRoot}/${command.compKey}/${paths.scoringStatusKey}',
    ).set(<String, dynamic>{
      'status': 'completed',
      'inProgress': false,
      'commandId': command.commandId,
      'commandType': command.commandType.name,
      'compKey': command.compKey,
      'scopeKey': command.scopeKey,
      'sourceEventId': command.sourceEventId,
      'sourcePath': command.sourcePath,
      'startedAt': startedRecord.startedAt,
      'completedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'roundsRebuilt': rebuiltRoundNumbers,
      'roundsSkipped': skippedRoundNumbers,
      'message': message,
    });

    return BackendScoringCommandResult(
      status: 'completed',
      skipped: false,
      commandId: command.commandId,
      commandType: command.commandType.name,
      scopeKey: command.scopeKey,
      compKey: command.compKey,
      message: message,
    );
  } catch (error) {
    final failedRecord = BackendScoringIdempotencyRecord(
      status: BackendScoringIdempotencyStatus.failed,
      commandId: command.commandId,
      commandType: command.commandType.name,
      compKey: command.compKey,
      sourceEventId: command.sourceEventId,
      sourcePath: command.sourcePath,
      scopeKey: command.scopeKey,
      startedAt: startedRecord.startedAt,
      expiresAt: startedRecord.expiresAt,
      failedAt: now.toIso8601String(),
      error: error.toString(),
    );
    await idempotencyRef.set(failedRecord.toJson());
    await db.ref(
      '${paths.statsPathRoot}/${command.compKey}/${paths.scoringStatusKey}',
    ).set(<String, dynamic>{
      'status': 'failed',
      'inProgress': false,
      'commandId': command.commandId,
      'commandType': command.commandType.name,
      'compKey': command.compKey,
      'scopeKey': command.scopeKey,
      'sourceEventId': command.sourceEventId,
      'sourcePath': command.sourcePath,
      'startedAt': startedRecord.startedAt,
      'failedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'error': error.toString(),
    });
    rethrow;
  }
}

class _BackendScoringRoundRebuildResult {
  final int roundNumber;
  final int tipperCount;
  final bool skipped;

  const _BackendScoringRoundRebuildResult({
    required this.roundNumber,
    required this.tipperCount,
    this.skipped = false,
  });
}

Future<_BackendScoringRoundRebuildResult> _rebuildBackendScoringRound({
  required dynamic db,
  required DAUComp comp,
  required List<Game> games,
  required int roundNumber,
  required DateTime now,
  List<Tipper>? allTippers,
  Map<String, dynamic>? tipsByTipperRaw,
  bool allowEmptyRound = false,
  bool replaceRoundStats = false,
  Map<String, dynamic>? gameStatsUpdatesSink,
}) async {
  final roundGames = games.where((game) {
    final gameRound = game.getDAURound(comp);
    return gameRound?.dAUroundNumber == roundNumber;
  }).toList();
  if (roundGames.isEmpty) {
    if (allowEmptyRound) {
      if (replaceRoundStats) {
        await db
            .ref(
              '${paths.statsPathRoot}/${comp.dbkey}/'
              '${paths.roundStatsBackendRoot}/$roundNumber',
            )
            .set(null);
      }
      return _BackendScoringRoundRebuildResult(
        roundNumber: roundNumber,
        tipperCount: allTippers?.length ?? 0,
        skipped: true,
      );
    }
    throw NotFoundError(
      'No games found for round $roundNumber in comp ${comp.dbkey}',
    );
  }

  final rawTippers = allTippers ?? await _loadBackendScoringTippers(db);
  final rawTips = tipsByTipperRaw ??
      await _loadBackendScoringTipsByTipperRaw(
        db: db,
        compKey: comp.dbkey!,
      );
  final tippers = _filterBackendScoringTippersWithSubmittedTips(
    allTippers: rawTippers,
    tipsByTipperRaw: rawTips,
  );
  final roundGamesByKey = {
    for (final game in roundGames) game.dbkey: game,
  };
  final tipLoadResult = _buildBackendScoringTipsForRound(
    allTippers: tippers,
    gamesByKey: roundGamesByKey,
    tipsByTipperRaw: rawTips,
    now: now,
  );
  final tipsByTipper = tipLoadResult.tipsByTipper;

  final roundStatsUpdates = <String, dynamic>{};

  for (final tipper in tippers) {
    final tipperDbKey = tipper.dbkey;
    if (tipperDbKey == null) {
      continue;
    }
    final tipsByGameKey = tipsByTipper[tipperDbKey] ?? <String, Tip>{};
    final roundStats = ScoringCalculator.calculateRoundStatsForTipper(
      roundNumber: roundNumber,
      games: roundGames,
      tipsByGameKey: tipsByGameKey,
      now: now,
    );

    roundStatsUpdates[tipperDbKey] = roundStats.toJson();
  }

  if (roundStatsUpdates.isNotEmpty) {
    final roundStatsRef = db.ref(
      '${paths.statsPathRoot}/${comp.dbkey}/'
      '${paths.roundStatsBackendRoot}/$roundNumber',
    );
    if (replaceRoundStats) {
      await roundStatsRef.set(roundStatsUpdates);
    } else {
      await roundStatsRef.update(roundStatsUpdates);
    }
  }

  final gameStatsTipLoadResult = _buildBackendScoringTipsForRound(
    allTippers: rawTippers,
    gamesByKey: {
      for (final game in roundGames) game.dbkey: game,
    },
    tipsByTipperRaw: rawTips,
    now: now,
    defaultTipGamePredicate: _hasKnownBackendGameResult,
    requireStartedGameForDefaultTips: false,
  );
  await _rebuildBackendGameStatsForRound(
    db: db,
    comp: comp,
    roundGames: roundGames,
    allTippers: rawTippers,
    tipsByTipper: gameStatsTipLoadResult.tipsByTipper,
    updatesSink: gameStatsUpdatesSink,
    now: now,
  );

  return _BackendScoringRoundRebuildResult(
    roundNumber: roundNumber,
    tipperCount: tippers.length,
  );
}

class _RoundTipLoadResult {
  final Map<String, Map<String, Tip>> tipsByTipper;

  const _RoundTipLoadResult({
    required this.tipsByTipper,
  });
}

List<DAUComp> _buildBackendScoringPaidComps(dynamic compsParticipatedIn) {
  final rawCompKeys = <dynamic>[];
  if (compsParticipatedIn is List) {
    rawCompKeys.addAll(compsParticipatedIn);
  } else if (compsParticipatedIn is Map) {
    rawCompKeys.addAll(compsParticipatedIn.values);
  } else {
    return const [];
  }

  final comps = <DAUComp>[];
  for (final rawCompKey in rawCompKeys) {
    final compKey = rawCompKey.toString().trim();
    if (compKey.isEmpty) {
      continue;
    }
    comps.add(
      DAUComp(
        dbkey: compKey,
        name: compKey,
        aflFixtureJsonURL: Uri.parse('https://example.invalid/afl-fixtures.json'),
        nrlFixtureJsonURL: Uri.parse('https://example.invalid/nrl-fixtures.json'),
        daurounds: const [],
      ),
    );
  }

  return comps;
}

Tip _buildDefaultTipForStartedGame(Game game, Tipper tipper) {
  return Tip(
    game: game,
    tipper: tipper,
    tip: GameResult.d,
    submittedTimeUTC: DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
  );
}

Map<String, Tip> _applyDefaultTipsForStartedGames({
  required List<Game> games,
  required Map<String, Tip> tipsByGameKey,
  required Tipper tipper,
  required DateTime now,
  bool requireStartedGame = true,
}) {
  final augmentedTips = <String, Tip>{...tipsByGameKey};
  for (final game in games) {
    final gameKey = game.dbkey;
    if (augmentedTips.containsKey(gameKey)) {
      continue;
    }

    if (!requireStartedGame) {
      augmentedTips[gameKey] = _buildDefaultTipForStartedGame(game, tipper);
      continue;
    }

    final gameState = game.getGameState(now);
    if (gameState == GameState.startedResultKnown ||
        gameState == GameState.startedResultNotKnown) {
      augmentedTips[gameKey] = _buildDefaultTipForStartedGame(game, tipper);
    }
  }

  return augmentedTips;
}

Future<List<Tipper>> _loadBackendScoringTippers(dynamic db) async {
  final tippersSnapshot = await db.ref(paths.tippersPath).once();
  final tippers = <Tipper>[];
  if (tippersSnapshot.value is! Map) {
    return tippers;
  }

  final tippersRaw = Map<String, dynamic>.from(tippersSnapshot.value as Map);
  for (final entry in tippersRaw.entries) {
    final tipperRaw = entry.value;
    if (tipperRaw is! Map) {
      continue;
    }

    tippers.add(
      Tipper(
        dbkey: entry.key,
        authuid: tipperRaw['authuid'] as String? ?? '',
        email: tipperRaw['email'] as String?,
        logon: tipperRaw['logon'] as String?,
        name: tipperRaw['name'] as String? ?? entry.key,
        tipperRole: tipperRaw['tipperRole'] != null
            ? TipperRole.values.byName(tipperRaw['tipperRole'] as String)
            : TipperRole.tipper,
        photoURL: tipperRaw['photoURL'] as String?,
        compsPaidFor: _buildBackendScoringPaidComps(
          tipperRaw['compsParticipatedIn'],
        ),
        acctCreatedUTC: _tryParseDateTime(tipperRaw['acctCreatedUTC']),
        acctLoggedOnUTC: _tryParseDateTime(tipperRaw['acctLoggedOnUTC']),
        isAnonymous: tipperRaw['isAnonymous'] as bool? ?? false,
      ),
    );
  }

  return tippers;
}

Future<Map<String, dynamic>> _loadBackendScoringTipsByTipperRaw({
  required dynamic db,
  required String compKey,
}) async {
  final tipsSnapshot =
      await db.ref('${paths.tipsPathRoot}/$compKey').once();
  return tipsSnapshot.value is Map
      ? Map<String, dynamic>.from(tipsSnapshot.value as Map)
      : <String, dynamic>{};
}

_RoundTipLoadResult _buildBackendScoringTipsForRound({
  required List<Tipper> allTippers,
  required Map<String, Game> gamesByKey,
  required Map<String, dynamic> tipsByTipperRaw,
  required DateTime now,
  bool Function(Game game)? defaultTipGamePredicate,
  bool requireStartedGameForDefaultTips = true,
}) {
  final tipsByTipper = <String, Map<String, Tip>>{};

  for (final tipper in allTippers) {
    final tipperDbKey = tipper.dbkey;
    if (tipperDbKey == null) {
      continue;
    }

    final tipperTipsRaw = tipsByTipperRaw[tipperDbKey];
    final tipperTipsByGameKey = <String, Tip>{};
    if (tipperTipsRaw is Map && tipperTipsRaw.isNotEmpty) {
      final tipperTipsRawMap = Map<String, dynamic>.from(tipperTipsRaw);
      for (final entry in tipperTipsRawMap.entries) {
        final game = gamesByKey[entry.key];
        if (game == null || entry.value is! Map) {
          continue;
        }

        tipperTipsByGameKey[entry.key] = Tip.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
          entry.key,
          tipper,
          game,
        );
      }
    }

    final defaultableGames = defaultTipGamePredicate == null
        ? gamesByKey.values.toList()
        : gamesByKey.values.where(defaultTipGamePredicate).toList();

    tipsByTipper[tipperDbKey] = _applyDefaultTipsForStartedGames(
      games: defaultableGames,
      tipsByGameKey: tipperTipsByGameKey,
      tipper: tipper,
      now: now,
      requireStartedGame: requireStartedGameForDefaultTips,
    );
  }

  return _RoundTipLoadResult(tipsByTipper: tipsByTipper);
}

List<Tipper> _filterBackendScoringTippersWithSubmittedTips({
  required List<Tipper> allTippers,
  required Map<String, dynamic> tipsByTipperRaw,
}) {
  return allTippers.where((tipper) {
    final tipperDbKey = tipper.dbkey;
    if (tipperDbKey == null) {
      return false;
    }

    final tipperTipsRaw = tipsByTipperRaw[tipperDbKey];
    return tipperTipsRaw is Map && tipperTipsRaw.isNotEmpty;
  }).toList();
}

bool _hasKnownBackendGameResult(Game game) {
  final scoring = game.scoring;
  if (scoring == null) {
    return false;
  }
  return scoring.getGameResultCalculated(game.league) != GameResult.z;
}

Future<void> _rebuildBackendGameStatsForRound({
  required dynamic db,
  required DAUComp comp,
  required List<Game> roundGames,
  required List<Tipper> allTippers,
  required Map<String, Map<String, Tip>> tipsByTipper,
  required DateTime now,
  Map<String, dynamic>? updatesSink,
}) async {
  if (roundGames.isEmpty || allTippers.isEmpty) {
    return;
  }

  final paidCohortTippers = allTippers
      .where((tipper) => tipper.paidForComp(comp))
      .toList();
  final freeCohortTippers = allTippers
      .where((tipper) => !tipper.paidForComp(comp))
      .toList();

  final updates = <String, dynamic>{};
  final cohorts = <MapEntry<String, List<Tipper>>>[
    MapEntry('paid', paidCohortTippers),
    MapEntry('free', freeCohortTippers),
  ];
  for (final game in roundGames) {
    final hasKnownResult = _hasKnownBackendGameResult(game);
    final gameState = game.getGameState(now);
    final hasStarted = gameState == GameState.startedResultKnown ||
        gameState == GameState.startedResultNotKnown;
    for (final cohort in cohorts) {
      final tipsForCohort = cohort.value
          .map((tipper) => tipsByTipper[tipper.dbkey]?[game.dbkey])
          .toList();
      final hasSubmittedTips = tipsForCohort.any((tip) => tip != null);
      if (!hasKnownResult && (!hasStarted || !hasSubmittedTips)) {
        continue;
      }

      final gameStatsEntry = ScoringCalculator.calculateGameStatsEntry(
        cohortTippers: cohort.value,
        tipsForCohort: tipsForCohort,
        league: game.league,
      );
      updates['${cohort.key}/${game.dbkey}'] = gameStatsEntry.toJson();
    }
  }

  if (updatesSink != null) {
    updatesSink.addAll(updates);
    return;
  }

  if (updates.isNotEmpty) {
    await db
        .ref(
          '${paths.statsPathRoot}/${comp.dbkey}/'
          '${paths.gameStatsBackendRoot}',
        )
        .update(updates);
  }
}

Map<String, dynamic> _nestBackendGameStatsUpdates(
  Map<String, dynamic>? flatUpdates,
) {
  final nestedUpdates = <String, dynamic>{};
  if (flatUpdates == null) {
    return nestedUpdates;
  }

  for (final entry in flatUpdates.entries) {
    final separatorIndex = entry.key.indexOf('/');
    if (separatorIndex <= 0 || separatorIndex == entry.key.length - 1) {
      continue;
    }

    final cohortKey = entry.key.substring(0, separatorIndex);
    final gameKey = entry.key.substring(separatorIndex + 1);
    final cohortUpdates = nestedUpdates.putIfAbsent(
      cohortKey,
      () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    cohortUpdates[gameKey] = entry.value;
  }

  return nestedUpdates;
}

Future<DAUComp> _loadBackendScoringComp(dynamic db, String compKey) async {
  final compSnapshot =
      await db.ref('${paths.daucompsPath}/$compKey').once();
  if (compSnapshot.value == null) {
    throw NotFoundError('DAUComp not found for key: $compKey');
  }

  final compRaw = Map<String, dynamic>.from(compSnapshot.value as Map);
  final rounds = _deserializeCombinedRounds(compRaw);
  return DAUComp.fromJson(compRaw, compKey, rounds);
}

Future<Tipper> _loadBackendScoringTipper(
  dynamic db,
  String tipperId,
) async {
  final tipperSnapshot =
      await db.ref('${paths.tippersPath}/$tipperId').once();
  if (tipperSnapshot.value == null) {
    throw NotFoundError('Tipper not found for key: $tipperId');
  }

  final tipperRaw = Map<String, dynamic>.from(tipperSnapshot.value as Map);
  return Tipper(
    dbkey: tipperId,
    authuid: tipperRaw['authuid'] as String? ?? '',
    email: tipperRaw['email'] as String?,
    logon: tipperRaw['logon'] as String?,
    name: tipperRaw['name'] as String? ?? tipperId,
    tipperRole: tipperRaw['tipperRole'] != null
        ? TipperRole.values.byName(tipperRaw['tipperRole'] as String)
        : TipperRole.tipper,
    photoURL: tipperRaw['photoURL'] as String?,
    compsPaidFor: _buildBackendScoringPaidComps(
      tipperRaw['compsParticipatedIn'],
    ),
    acctCreatedUTC: _tryParseDateTime(tipperRaw['acctCreatedUTC']),
    acctLoggedOnUTC: _tryParseDateTime(tipperRaw['acctLoggedOnUTC']),
    isAnonymous: tipperRaw['isAnonymous'] as bool? ?? false,
  );
}

List<DAURound> _deserializeCombinedRounds(Map<String, dynamic> compRaw) {
  final rounds = <DAURound>[];
  final rawRounds = compRaw['combinedRounds2'];
  if (rawRounds is List) {
    for (var i = 0; i < rawRounds.length; i++) {
      final roundRaw = rawRounds[i];
      if (roundRaw is Map) {
        rounds.add(
          DAURound.fromJson(
            Map<String, dynamic>.from(roundRaw),
            i + 1,
          ),
        );
      }
    }
  } else if (rawRounds is Map) {
    rawRounds.forEach((key, value) {
      if (value is Map) {
        rounds.add(
          DAURound.fromJson(
            Map<String, dynamic>.from(value),
            (int.tryParse(key.toString()) ?? 0) + 1,
          ),
        );
      }
    });
  }

  rounds.sort();
  return rounds;
}

DAURound? _findRoundByNumber(DAUComp comp, int roundNumber) {
  for (final round in comp.daurounds) {
    if (round.dAUroundNumber == roundNumber) {
      return round;
    }
  }
  return null;
}

Future<List<Game>> _loadBackendScoringGames({
  required dynamic db,
  required DAUComp comp,
}) async {
  final teamsSnapshot = await db.ref(paths.teamsPathRoot).once();
  final teamsByKey = <String, Team>{};
  if (teamsSnapshot.value is Map) {
    final teamsRaw = Map<String, dynamic>.from(teamsSnapshot.value as Map);
    for (final entry in teamsRaw.entries) {
      final teamRaw = entry.value;
      if (teamRaw is Map) {
        final team = Team.fromJson(
          Map<String, dynamic>.from(teamRaw),
          entry.key,
        );
        teamsByKey[entry.key.toLowerCase()] = team;
      }
    }
  }

  final liveScoresSnapshot = await db
      .ref('${paths.statsPathRoot}/${comp.dbkey}/${paths.liveScoresBackendRoot}')
      .once();
  final liveScoresByGame = _deserializeLiveScores(liveScoresSnapshot);

  final gamesSnapshot =
      await db.ref('${paths.gamesPathRoot}/${comp.dbkey}').once();
  final games = <Game>[];
  if (gamesSnapshot.value == null) {
    return games;
  }

  final gamesRaw = Map<String, dynamic>.from(gamesSnapshot.value as Map);
  for (final entry in gamesRaw.entries) {
    final gameRaw = Map<String, dynamic>.from(entry.value as Map);
    final leagueName = entry.key.toString().split('-').first;
    final homeTeamKey =
        '$leagueName-${_normalizeTeamLookupName(gameRaw['HomeTeam'])}';
    final awayTeamKey =
        '$leagueName-${_normalizeTeamLookupName(gameRaw['AwayTeam'])}';
    final homeTeam = teamsByKey[homeTeamKey];
    final awayTeam = teamsByKey[awayTeamKey];
    if (homeTeam == null || awayTeam == null) {
      throw NotFoundError(
        'Team records missing for game ${entry.key}: $homeTeamKey / $awayTeamKey',
      );
    }

    final game = Game.fromJson(entry.key, gameRaw, homeTeam, awayTeam);
    if (_isBackendScoringGameOutsideRegularComp(comp, game)) {
      continue;
    }

    final scoring = Scoring(
      homeTeamScore: (gameRaw['HomeTeamScore'] as num?)?.toInt(),
      awayTeamScore: (gameRaw['AwayTeamScore'] as num?)?.toInt(),
      crowdSourcedScores: _crowdScoresForGame(liveScoresByGame[entry.key]),
    );
    game.scoring = scoring;

    games.add(game);
  }

  games.sort();
  return games;
}

bool _isBackendScoringGameOutsideRegularComp(DAUComp comp, Game game) {
  if (game.league == League.afl && comp.aflRegularCompEndDateUTC != null) {
    return game.startTimeUTC.isAfter(comp.aflRegularCompEndDateUTC!);
  }
  if (game.league == League.nrl && comp.nrlRegularCompEndDateUTC != null) {
    return game.startTimeUTC.isAfter(comp.nrlRegularCompEndDateUTC!);
  }
  return false;
}

String _normalizeTeamLookupName(dynamic rawName) {
  return rawName.toString().trim().toLowerCase();
}

Map<String, Map<String, dynamic>> _deserializeLiveScores(DataSnapshot snapshot) {
  final liveScores = <String, Map<String, dynamic>>{};
  if (snapshot.value == null) {
    return liveScores;
  }

  final raw = Map<String, dynamic>.from(snapshot.value as Map);
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is Map) {
      final current = value['current'] is Map
          ? Map<String, dynamic>.from(value['current'] as Map)
          : Map<String, dynamic>.from(value);
      liveScores[entry.key] = current;
    }
  }

  return liveScores;
}

List<CrowdSourcedScore>? _crowdScoresForGame(Map<String, dynamic>? current) {
  if (current == null) {
    return null;
  }

  final rawScores = current['crowdSourcedScores'];
  final scores = <CrowdSourcedScore>[];
  for (final rawScore in _crowdScoreValues(rawScores)) {
    final score = _tryParseCrowdSourcedScore(rawScore);
    if (score != null) {
      scores.add(score);
    }
  }

  if (scores.isEmpty) {
    scores.addAll(_crowdScoresFromCurrentSnapshot(current));
  }

  return scores.isEmpty ? null : scores;
}

Iterable<dynamic> _crowdScoreValues(dynamic rawScores) {
  if (rawScores is List) {
    return rawScores;
  }
  if (rawScores is Map) {
    final entries = rawScores.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return entries.map((entry) => entry.value);
  }
  return const [];
}

CrowdSourcedScore? _tryParseCrowdSourcedScore(dynamic rawScore) {
  if (rawScore is! Map) {
    return null;
  }

  try {
    final data = Map<String, dynamic>.from(rawScore);
    final submittedTimeRaw = data['submittedTimeUTC'];
    final scoreTeamRaw = data['scoreTeam'];
    final tipperIdRaw = data['tipperID'];
    final interimScore = _tryParseInt(data['interimScore']);
    if (submittedTimeRaw is! String ||
        scoreTeamRaw is! String ||
        tipperIdRaw is! String ||
        interimScore == null) {
      return null;
    }

    return CrowdSourcedScore(
      DateTime.parse(submittedTimeRaw),
      ScoringTeam.values.byName(scoreTeamRaw),
      tipperIdRaw,
      interimScore,
      data['gameComplete'] == true,
    );
  } catch (error, stackTrace) {
    developer.log(
      'backendScoringCommand: ignored malformed live score',
      name: 'backendScoringCommand',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

List<CrowdSourcedScore> _crowdScoresFromCurrentSnapshot(
  Map<String, dynamic> current,
) {
  final submittedTimeRaw = current['submittedTimeUTC'];
  final tipperIdRaw = current['tipperID'];
  if (submittedTimeRaw is! String || tipperIdRaw is! String) {
    return const [];
  }

  final submittedTime = DateTime.tryParse(submittedTimeRaw);
  if (submittedTime == null) {
    return const [];
  }

  final scores = <CrowdSourcedScore>[];
  void addScore(ScoringTeam team, dynamic rawScore) {
    final interimScore = _tryParseInt(rawScore);
    if (interimScore == null) {
      return;
    }
    scores.add(
      CrowdSourcedScore(
        submittedTime,
        team,
        tipperIdRaw,
        interimScore,
        current['gameComplete'] == true,
      ),
    );
  }

  addScore(ScoringTeam.home, current['homeInterimScore']);
  addScore(ScoringTeam.away, current['awayInterimScore']);
  return scores;
}

int? _tryParseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

Future<Map<String, Tip>> _loadBackendScoringTipsForTipper({
  required dynamic db,
  required String compKey,
  required Tipper tipper,
  required Map<String, Game> gamesByKey,
  required DateTime now,
}) async {
  final tipsSnapshot = await db
      .ref('${paths.tipsPathRoot}/$compKey/${tipper.dbkey}')
      .once();
  final tipsByGameKey = <String, Tip>{};
  if (tipsSnapshot.value is Map) {
    final tipsRaw = Map<String, dynamic>.from(tipsSnapshot.value as Map);
    for (final entry in tipsRaw.entries) {
      final game = gamesByKey[entry.key];
      if (game == null || entry.value is! Map) {
        continue;
      }

      tipsByGameKey[entry.key] = Tip.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
        entry.key,
        tipper,
        game,
      );
    }
  }

  return _applyDefaultTipsForStartedGames(
    games: gamesByKey.values.toList(),
    tipsByGameKey: tipsByGameKey,
    tipper: tipper,
    now: now,
  );
}

DateTime? _tryParseDateTime(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

bool _isIdempotencyExpired(
  BackendScoringIdempotencyRecord record,
  DateTime now,
) {
  final expiresAt = DateTime.tryParse(record.expiresAt)?.toUtc();
  if (expiresAt == null) {
    return true;
  }
  return !expiresAt.isAfter(now);
}
