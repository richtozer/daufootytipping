import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;

/// The Firebase project the identity tools (purge and restore) target unless told otherwise.
const String defaultIdentityProject = 'dau-footy-tipping-f8a42';

/// The two nodes the purge and restore tools read, and the one write each makes. Two
/// implementations, as for the mode tool: over the REST handle (tests, against
/// the emulator) and over the Firebase CLI the owner is logged into.
abstract interface class IdentityRecordsStore {
  Future<Object?> readTippers();

  Future<Object?> readTipperPrivate();

  /// Applies [patch] (paths from the database root) as one update.
  Future<void> applyPatch(Map<String, Object?> patch);
}

/// A [IdentityRecordsStore] over the REST handle.
class RestIdentityRecordsStore implements IdentityRecordsStore {
  RestIdentityRecordsStore(this._database);

  final RestDatabase _database;

  @override
  Future<Object?> readTippers() async =>
      (await _database.ref(paths.tippersPath).once()).value;

  @override
  Future<Object?> readTipperPrivate() async =>
      (await _database.ref(paths.tipperPrivatePath).once()).value;

  @override
  Future<void> applyPatch(Map<String, Object?> patch) =>
      _database.ref('/').update(patch);
}

/// A [IdentityRecordsStore] over the Firebase CLI. The patch is handed over in a file in
/// a private temporary folder (it holds email addresses), deleted afterwards.
class CliIdentityRecordsStore implements IdentityRecordsStore {
  CliIdentityRecordsStore({
    required this.project,
    this.executable = 'firebase',
    ProcessRunner? runner,
  }) : _run = runner ?? Process.run;

  final String project;
  final String executable;
  final ProcessRunner _run;

  Future<String> _firebase(List<String> arguments) async {
    final result = await _run(executable, [...arguments, '--project', project]);
    if (result.exitCode != 0) {
      throw StateError(
        'firebase ${arguments.first} failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
    return '${result.stdout}';
  }

  Future<Object?> _read(String path) async {
    final text = (await _firebase(['database:get', path])).trim();
    return text.isEmpty ? null : jsonDecode(text);
  }

  @override
  Future<Object?> readTippers() => _read(paths.tippersPath);

  @override
  Future<Object?> readTipperPrivate() => _read(paths.tipperPrivatePath);

  @override
  Future<void> applyPatch(Map<String, Object?> patch) async {
    final folder = await Directory.systemTemp.createTemp('identity-records-');
    try {
      final file = File('${folder.path}/patch.json');
      await file.writeAsString(jsonEncode(patch));
      await _firebase([
        'database:update',
        '/',
        file.path,
        '--force',
        '--disable-triggers',
      ]);
    } finally {
      await folder.delete(recursive: true);
    }
  }
}
