import 'dart:io';

import 'package:dart_functions/identity/backfill_cli.dart';

/// Plans or checks the identity backfill. See `--help`.
Future<void> main(List<String> arguments) async {
  exitCode = await runBackfillCli(arguments, out: stdout, err: stderr);
}
