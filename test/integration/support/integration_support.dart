// Support for the client integration tests (scripts/test-client-integration.sh).
//
// These tests run the app's own client classes (IdentityService, the linked
// tipper resolver, the token registrar, account deletion, the live score entry)
// against the REAL Dart callable server, compiled from functions_dart, and a
// Realtime Database emulator running the REAL rulesets. Nothing here fakes the
// server or the rules; it only stands in for what cannot run outside a device:
// the Firebase Auth SDK (accounts are unsigned tokens, which the emulators and
// the server accept only in emulator mode) and the database plugin (reads and
// writes are the same paths and payloads over the emulator's REST interface).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:dau_shared/constants/paths.dart' as paths;

/// Why the integration tests are skipped, or null when they will run.
final String? integrationSkipReason =
    Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'] == null ||
        Platform.environment['INTEGRATION_SERVER_URL'] == null
    ? 'needs the emulator and the Dart server: run scripts/test-client-integration.sh'
    : null;

/// The namespace of the demo project the emulator runs.
const String emulatorNamespace = 'demo-dau-rules';

/// The rulesets under test, from the repository's generated rule files.
enum Ruleset {
  r1Compat('database.rules.r1-compat.json'),
  freeze('database.rules.freeze.json'),
  r2('database.rules.r2.json');

  const Ruleset(this.fileName);

  final String fileName;

  String get text => File('config/generated/$fileName').readAsStringSync();
}

String _base64Url(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// A signed-in account, as the emulators and the server read one: an unsigned
/// token carrying the claims the real one would.
class Account {
  const Account(this.uid, {this.email, this.provider = 'google.com'});

  final String uid;
  final String? email;
  final String provider;

  /// The ID token. It is not signed, so it is accepted only by emulators and by
  /// the server started in emulator mode. It carries the standard claims the
  /// emulator's rules engine reads (the same set as `@firebase/rules-unit-testing`).
  String get idToken {
    final issuedAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return '${_base64Url({'alg': 'none', 'typ': 'JWT'})}.'
        '${_base64Url({
          'iss': 'https://securetoken.google.com/$emulatorNamespace',
          'aud': emulatorNamespace,
          'iat': issuedAt,
          'exp': issuedAt + 3600,
          'auth_time': issuedAt,
          'sub': uid,
          'user_id': uid,
          if (email != null) 'email': email,
          if (email != null) 'email_verified': true,
          'firebase': {'sign_in_provider': provider, 'identities': {}},
        })}.';
  }

  /// The App Check token the callables require.
  static String get appCheckToken =>
      '${_base64Url({'alg': 'none', 'typ': 'JWT'})}.'
      '${_base64Url({'sub': '1:1:ios:integration', 'app_id': '1:1:ios:integration'})}.';
}

/// What came back from the database.
class DbResult {
  const DbResult(this.status, this.body);

  final int status;
  final Object? body;

  bool get ok => status >= 200 && status < 300;

  /// The rules refused the request.
  bool get denied => status == 401 || status == 403;

  Map<String, dynamic>? get map =>
      body is Map ? Map<String, dynamic>.from(body! as Map) : null;
}

/// The emulator's REST interface, as an administrator (rules do not apply) or as
/// an [Account] (they do).
class EmulatorDatabase {
  EmulatorDatabase._(this._host);

  factory EmulatorDatabase.fromEnvironment() => EmulatorDatabase._(
    Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST']!,
  );

  final String _host;
  final HttpClient _http = HttpClient();

  Uri _uri(String path, {String suffix = '.json', String? userToken}) {
    final cleaned = path.replaceAll(RegExp(r'^/+'), '');
    final auth = userToken == null ? '' : '&auth=$userToken';
    return Uri.parse(
      'http://$_host/$cleaned$suffix?ns=$emulatorNamespace$auth',
    );
  }

  Future<DbResult> _send(
    String method,
    String path, {
    Object? body,
    String? userToken,
  }) async {
    // The administrator is the emulator's own `owner` credential, which bypasses
    // the rules. A user is a token in the `auth` parameter, which does not: a
    // token in the Authorization header would be taken for the administrator's.
    final request = await _http.openUrl(
      method,
      _uri(path, userToken: userToken),
    );
    if (userToken == null) {
      request.headers.set('Authorization', 'Bearer owner');
    }
    request.headers.contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = text;
    }
    return DbResult(response.statusCode, decoded);
  }

  /// Everything below is the administrator's.
  Future<DbResult> adminGet(String path) => _send('GET', path);

  Future<DbResult> adminPut(String path, Object? value) =>
      _send('PUT', path, body: value);

  Future<DbResult> adminPatch(String path, Map<String, Object?> updates) =>
      _send('PATCH', path, body: updates);

  /// Empties the database and loads [ruleset], so each test starts clean.
  Future<void> reset({Ruleset ruleset = Ruleset.r1Compat}) async {
    await _send('DELETE', '/');
    await useRules(ruleset);
  }

  /// Loads [ruleset], as the cutover will.
  Future<void> useRules(Ruleset ruleset) async {
    final uri = Uri.parse(
      'http://$_host/.settings/rules.json?ns=$emulatorNamespace',
    );
    final request = await _http.putUrl(uri);
    request.headers
      ..set('Authorization', 'Bearer owner')
      ..contentType = ContentType.json;
    request.write(ruleset.text);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw StateError('could not load ${ruleset.fileName}: $text');
    }
  }

  /// The identity mode the server reads (`/ServerConfig/identity/mode`).
  Future<void> setIdentityMode(String mode) =>
      adminPut('/ServerConfig/identity', {'mode': mode});

  /// What a running app has: identity callables on (mode `coexist`) and new
  /// tippers allowed (`AppConfig/createLinkedTipper`).
  Future<void> seedRunningApp() async {
    await setIdentityMode('coexist');
    await adminPut(
      '${paths.configPathRoot}/${paths.createLinkedTipperKey}',
      true,
    );
  }

  /// Gives the tipper the administrator role, as it already is on a database that
  /// has administrators: in the private record, which is what the functions and
  /// the R2 rules both read (the public copy is written too, as 1.4.x clients do).
  Future<void> makeAdministrator(String tipperId) => adminPatch('/', {
    '${paths.tipperPrivatePath}/$tipperId/tipperRole': 'admin',
    '${paths.tippersPath}/$tipperId/tipperRole': 'admin',
  });

  /// This database as [account] sees it, under the rules in force.
  ClientDatabase as(Account account) => ClientDatabase._(this, account);
}

/// The database as one signed-in account uses it.
class ClientDatabase {
  ClientDatabase._(this._db, this.account);

  final EmulatorDatabase _db;
  final Account account;

  Future<DbResult> get(String path) =>
      _db._send('GET', path, userToken: account.idToken);

  Future<DbResult> put(String path, Object? value) =>
      _db._send('PUT', path, body: value, userToken: account.idToken);

  /// A multi-path update, as `DatabaseReference.update` does.
  Future<DbResult> update(String path, Map<String, Object?> updates) =>
      _db._send('PATCH', path, body: updates, userToken: account.idToken);

  Future<DbResult> remove(String path) =>
      _db._send('DELETE', path, userToken: account.idToken);
}

/// [IdentityReads] over a [ClientDatabase], so the resolver's reads are subject
/// to the rules in force, as the app's are.
class RestIdentityReads implements IdentityReads {
  RestIdentityReads(this._client);

  final ClientDatabase _client;

  Future<Object?> _value(String path) async {
    final result = await _client.get(path);
    if (!result.ok) {
      throw StateError('read of $path refused (${result.status})');
    }
    return result.body;
  }

  @override
  Future<String?> authIndexEntry(String uid) async {
    final value = await _value('${paths.authIndexPath}/$uid');
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<Map<String, dynamic>?> privateRecord(String tipperId) async {
    final value = await _value('${paths.tipperPrivatePath}/$tipperId');
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  Future<Map<String, dynamic>?> publicRecord(String tipperId) async {
    final value = await _value('${paths.tippersPath}/$tipperId');
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }
}

/// Calls the real Dart server's callables over HTTP as one account, and reads
/// failures the way the client reads those of the `cloud_functions` plugin.
class HttpIdentityCallableInvoker implements IdentityCallableInvoker {
  HttpIdentityCallableInvoker(this.account, {String? serverUrl})
    : _serverUrl = serverUrl ?? Platform.environment['INTEGRATION_SERVER_URL']!;

  final Account account;
  final String _serverUrl;
  final HttpClient _http = HttpClient();

  /// How many calls were made, by endpoint.
  final Map<String, int> calls = <String, int>{};

  @override
  Future<Object?> call(
    String endpoint,
    Map<String, Object?> data, {
    Duration timeout = const Duration(seconds: 65),
  }) async {
    calls[endpoint] = (calls[endpoint] ?? 0) + 1;
    final Map<String, dynamic> reply;
    final int status;
    try {
      final request = await _http.postUrl(Uri.parse('$_serverUrl/$endpoint'));
      request.headers
        ..set('Authorization', 'Bearer ${account.idToken}')
        ..set('X-Firebase-AppCheck', Account.appCheckToken)
        ..contentType = ContentType.json;
      request.write(jsonEncode({'data': data}));
      final response = await request.close().timeout(timeout);
      status = response.statusCode;
      final text = await utf8.decodeStream(response);
      reply = Map<String, dynamic>.from(jsonDecode(text) as Map);
    } on Exception catch (error) {
      throw IdentityFailure.network(error);
    }
    if (status == 200) {
      return reply['result'];
    }
    final error = Map<String, dynamic>.from(reply['error'] as Map);
    throw IdentityFailure.fromFunctionsError(
      code: '${error['status']}'.toLowerCase().replaceAll('_', '-'),
      message: error['message'] as String?,
      details: error['details'],
    );
  }
}
