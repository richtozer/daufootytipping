import 'dart:io';

import 'package:dart_functions/identity/mode_cli.dart';
import 'package:dart_functions/identity/mode_control.dart';

/// Shows or changes the identity server mode and drains. See `--help`.
Future<void> main(List<String> arguments) async {
  final executable = Platform.environment['FIREBASE_BIN'] ?? 'firebase';
  exitCode = await runModeCli(
    arguments,
    storeFor: (project) =>
        CliModeStore(project: project, executable: executable),
    out: stdout,
    err: stderr,
  );
}
