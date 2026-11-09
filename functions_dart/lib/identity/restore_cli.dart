import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/restore_public.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;

/// The Firebase project the restore targets unless told otherwise.
const String defaultRestoreProject = 'dau-footy-tipping-f8a42';

/// The two nodes the restore reads, and the one write it makes. Two
/// implementations, as for the mode tool: over the REST handle (tests, against
/// the emulator) and over the Firebase CLI the owner is logged into.
abstract interface class RestoreStore {
  Future<Object?> readTippers();

  Future<Object?> readTipperPrivate();

  /// Applies [patch] (paths from the database root) as one update.
  Future<void> applyPatch(Map<String, Object?> patch);
}

/// A [RestoreStore] over the REST handle.
class RestRestoreStore implements RestoreStore {
  RestRestoreStore(this._database);

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

/// A [RestoreStore] over the Firebase CLI. The patch is handed over in a file in
/// a private temporary folder (it holds email addresses), deleted afterwards.
class CliRestoreStore implements RestoreStore {
  CliRestoreStore({
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
    final folder = await Directory.systemTemp.createTemp('identity-restore-');
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

const String restoreToolUsage =
    '''
Restores the public identity fields after the purge (DESIGN-database-rules-phase4.md, section 9): copies each
tipper's email, login, account id, role, anonymous flag and login times from /TipperPrivate back to the public
record, so that R1-compat and the 1.4.x clients it serves find the shape they read. It never overwrites a field
the public record already has, and never brings back the legacy `active` and `tipperID` fields.

Usage: dart run bin/identity_restore.dart [options]

  (no options)     plan only: read the two nodes and say what would be written. Writes nothing.
  --out <file>     also write the patch to <file>. It holds email addresses: keep it under test/data/ (git-ignored).
  --apply          write it. Needs --project. Refuses unless the identity mode is freeze or off and no request is in
                   flight, and unless a second read plans exactly the same patch. Afterwards it reads again and the
                   plan must be empty.
  --project <id>   default $defaultRestoreProject for a plan; --apply must name it.

Run it BEFORE deploying R1-compat on the way back (R1's record check needs authuid and tipperRole), and with
the functions' triggers suppressed, which --apply does. The output names counts and opaque ids only.
Exit codes: 0 done (or nothing to do), 1 blocked or not verified, 2 usage.
''';

/// Runs the restore tool. [storeFor] and [modeFor] build the stores for a
/// project, so tests can supply ones over the emulator.
Future<int> runRestoreCli(
  List<String> arguments, {
  required RestoreStore Function(String project) storeFor,
  required ModeStore Function(String project) modeFor,
  required StringSink out,
  required StringSink err,
  Future<void> Function(String path, String contents)? writeFile,
}) async {
  var apply = false;
  String? project;
  String? outFile;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--apply':
        apply = true;
      case '--project':
        project = i + 1 < arguments.length ? arguments[++i] : null;
      case '--out':
        outFile = i + 1 < arguments.length ? arguments[++i] : null;
      default:
        err.writeln('Unknown argument ${arguments[i]}\n\n$restoreToolUsage');
        return 2;
    }
  }
  if (apply && project == null) {
    err.writeln(
      'ERROR: this writes data, so the project must be named: add --project <id> '
      '(production is $defaultRestoreProject).',
    );
    return 2;
  }
  final targetProject = project ?? defaultRestoreProject;
  final store = storeFor(targetProject);

  Future<RestorePlan> plan() async => planPublicIdentityRestore(
    tippers: await store.readTippers(),
    tipperPrivate: await store.readTipperPrivate(),
  );

  final first = await plan();
  _describe(first, out);
  if (first.isBlocked) {
    err.writeln(
      'BLOCKED: ${first.blocking.length} tipper(s) cannot be restored, so nothing is written:',
    );
    for (final finding in first.blocking) {
      err.writeln('  $finding');
    }
    return 1;
  }

  if (outFile != null) {
    await (writeFile ?? _writeFile)(outFile, jsonEncode(first.patch));
    out.writeln('Patch written to $outFile (it holds email addresses).');
  }
  if (!apply) {
    out.writeln(
      'Plan only: nothing was written. Add --apply (with --project) to write it.',
    );
    return 0;
  }
  if (first.isEmpty) {
    out.writeln('Nothing to restore.');
    return 0;
  }

  final modeStore = modeFor(targetProject);
  final mode = (await modeStore.readMode()).mode;
  if (mode != IdentityMode.freeze && mode != IdentityMode.off) {
    err.writeln(
      'STOP: the identity mode is ${mode.name}. Set freeze (or off) and drain first, so no callable '
      'writes while the restore runs.',
    );
    return 1;
  }
  final inflight = await modeStore.readInflight();
  if (inflight.isNotEmpty) {
    err.writeln(
      'STOP: ${inflight.length} request(s) are still in flight. Drain first '
      '(dart run bin/identity_mode.dart drain).',
    );
    return 1;
  }

  final second = await plan();
  if (jsonEncode(second.patch) != jsonEncode(first.patch)) {
    err.writeln(
      'STOP: the data changed between the two reads, so nothing was written. Run it again.',
    );
    return 1;
  }

  await store.applyPatch(first.patch);
  final after = await plan();
  if (!after.isEmpty || after.isBlocked) {
    err.writeln(
      'NOT VERIFIED: after writing, ${after.fieldsToRestore} field(s) would still be restored '
      'and ${after.blocking.length} tipper(s) are blocked.',
    );
    return 1;
  }
  out.writeln(
    'Restored ${first.fieldsToRestore} field(s) on ${first.recordsToRestore} record(s); '
    'a second plan finds nothing left. Now deploy R1-compat.',
  );
  return 0;
}

void _describe(RestorePlan plan, StringSink out) {
  out.writeln(
    'Would restore ${plan.fieldsToRestore} field(s) on ${plan.recordsToRestore} record(s).',
  );
  if (plan.differing > 0) {
    out.writeln(
      '${plan.differing} field(s) differ between the public and private copies; the public copy is kept.',
    );
  }
  if (plan.placeholderNames > 0) {
    out.writeln(
      '${plan.placeholderNames} tipper(s) carry the purge\'s placeholder name; it stays (the real name was never stored).',
    );
  }
}

Future<void> _writeFile(String path, String contents) =>
    File(path).writeAsString(contents);
