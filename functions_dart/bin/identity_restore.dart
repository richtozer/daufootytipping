import 'dart:io';

import 'package:dart_functions/identity/emulator_tools.dart';
import 'package:dart_functions/identity/identity_records_store.dart';
import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/restore_cli.dart';

/// Restores the public identity fields after the purge. See `--help`.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(restoreToolUsage);
    return;
  }
  final executable = Platform.environment['FIREBASE_BIN'] ?? 'firebase';
  final emulator = emulatorDatabaseFromEnvironment(Platform.environment);
  exitCode = await runRestoreCli(
    arguments,
    storeFor: (project) => emulator != null
        ? RestIdentityRecordsStore(emulator)
        : CliIdentityRecordsStore(project: project, executable: executable),
    modeFor: (project) => emulator != null
        ? RestModeStore(emulator)
        : CliModeStore(project: project, executable: executable),
    out: stdout,
    err: stderr,
  );
}
