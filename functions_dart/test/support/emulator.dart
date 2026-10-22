import 'dart:io';

import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:http/http.dart' as http;

/// Namespace of the demo project the rules_test emulator runs.
const String emulatorNamespace = 'demo-dau-rules';

final String? _emulatorHost =
    Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'];

/// Why the emulator-backed tests are skipped, or null when they will run.
///
/// Run them with `npm run test:dart` in rules_test, which starts the Database
/// emulator inside the isolation boundary and sets the host variable.
final String? emulatorSkipReason = _emulatorHost == null
    ? 'needs FIREBASE_DATABASE_EMULATOR_HOST (run npm run test:dart in rules_test)'
    : null;

/// A client that authenticates to the emulator as its admin, the way the
/// deployed functions' service account bypasses rules in production.
class _EmulatorAdminClient extends http.BaseClient {
  _EmulatorAdminClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }
}

/// The production REST handle, pointed at the emulator. [wrap] puts a client of
/// the test's own in front of the connection, to make requests fail on purpose.
RestDatabase openEmulatorDatabase({
  http.Client Function(http.Client inner)? wrap,
  Duration? requestTimeout,
}) {
  final host = _emulatorHost;
  if (host == null) {
    throw StateError(emulatorSkipReason!);
  }
  final admin = _EmulatorAdminClient(http.Client());
  return RestDatabase(
    client: wrap == null ? admin : wrap(admin),
    databaseUrl: 'http://$host/?ns=$emulatorNamespace',
    requestTimeout: requestTimeout ?? defaultRestRequestTimeout,
  );
}

/// Removes everything from the emulator database.
Future<void> clearEmulatorDatabase(RestDatabase database) =>
    database.ref('/').remove();
