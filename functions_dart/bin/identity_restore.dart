import 'dart:io';

import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/restore_cli.dart';

/// Restores the public identity fields after the purge. See `--help`.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(restoreToolUsage);
    return;
  }
  final executable = Platform.environment['FIREBASE_BIN'] ?? 'firebase';
  exitCode = await runRestoreCli(
    arguments,
    storeFor: (project) =>
        CliRestoreStore(project: project, executable: executable),
    modeFor: (project) =>
        CliModeStore(project: project, executable: executable),
    out: stdout,
    err: stderr,
  );
}
