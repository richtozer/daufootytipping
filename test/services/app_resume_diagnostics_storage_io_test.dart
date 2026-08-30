import 'dart:io';

import 'package:daufootytipping/services/app_resume_diagnostics_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'appends individual JSONL records and replaces only when requested',
    () async {
      final Directory temporaryDirectory =
          await Directory.systemTemp.createTemp('resume-diagnostics-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final File file = File('${temporaryDirectory.path}/events.jsonl');
      final FileResumeDiagnosticsStorage storage =
          FileResumeDiagnosticsStorage(file);

      await storage.appendLine('{"sequence":1}');
      await storage.appendLine('{"sequence":2}');

      expect(
        await storage.readLines(),
        <String>['{"sequence":1}', '{"sequence":2}'],
      );

      await storage.replaceLines(<String>['{"sequence":2}']);

      expect(await storage.readLines(), <String>['{"sequence":2}']);
    },
  );
}
