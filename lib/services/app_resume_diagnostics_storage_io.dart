import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app_resume_diagnostics_storage_contract.dart';

class FileResumeDiagnosticsStorage implements ResumeDiagnosticsStorage {
  FileResumeDiagnosticsStorage(this._file);

  static const String directoryName = 'diagnostics';
  static const String fileName = 'android_resume_diagnostics.jsonl';

  final File _file;

  @override
  Future<List<String>> readLines() async {
    if (!await _file.exists()) {
      return <String>[];
    }
    return _file.readAsLines();
  }

  @override
  Future<void> appendLine(String encodedEvent) async {
    await _ensureParentDirectory();
    await _file.writeAsString(
      '$encodedEvent\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<void> replaceLines(List<String> encodedEvents) async {
    await _ensureParentDirectory();
    final String contents = encodedEvents.isEmpty
        ? ''
        : '${encodedEvents.join('\n')}\n';
    await _file.writeAsString(contents, flush: true);
  }

  Future<void> _ensureParentDirectory() async {
    await _file.parent.create(recursive: true);
  }
}

Future<ResumeDiagnosticsStorage> createResumeDiagnosticsStorage() async {
  final Directory supportDirectory = await getApplicationSupportDirectory();
  final File diagnosticsFile = File(
    path.join(
      supportDirectory.path,
      FileResumeDiagnosticsStorage.directoryName,
      FileResumeDiagnosticsStorage.fileName,
    ),
  );
  return FileResumeDiagnosticsStorage(diagnosticsFile);
}
