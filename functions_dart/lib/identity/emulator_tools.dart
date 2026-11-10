import 'package:dart_functions/rtdb/emulator_admin_client.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:http/http.dart' as http;

/// The namespace of the demo project the local emulators run, unless told.
const String defaultEmulatorNamespace = 'demo-dau-rules';

/// The Realtime Database emulator the identity tools should use, or null.
///
/// The purge, restore and mode tools go through the Firebase CLI to a named
/// project. To rehearse the cutover on a local emulator they read and write that
/// emulator instead, when `FIREBASE_DATABASE_EMULATOR_HOST` is set (the variable
/// the emulator suite itself exports). It can only ever point a tool at a local
/// database: it names a host and port, never a project, so it cannot redirect
/// anything at production.
RestDatabase? emulatorDatabaseFromEnvironment(
  Map<String, String> environment, {
  http.Client? client,
}) {
  final host = environment['FIREBASE_DATABASE_EMULATOR_HOST'];
  if (host == null || host.isEmpty) {
    return null;
  }
  final namespace =
      environment['RTDB_EMULATOR_NAMESPACE'] ??
      environment['FIREBASE_DATABASE_EMULATOR_NAMESPACE'] ??
      defaultEmulatorNamespace;
  return RestDatabase(
    client: EmulatorAdminClient(client ?? http.Client()),
    databaseUrl: 'http://$host/?ns=$namespace',
  );
}
