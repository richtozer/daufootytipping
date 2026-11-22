import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/identity_records_store.dart';
import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/purge_public.dart';
import 'package:dart_functions/identity/server_mode.dart';

const String purgeToolUsage =
    '''
Purges the public identity fields (cutover step B, DESIGN-database-rules-phase4.md, section 8): removes each tipper's
email, login, account id, role, anonymous flag and login times, and the legacy `active` and `tipperID`, from
/AllTippers, once /TipperPrivate holds them. A public login time later than the private one is written to the private
record first (a 1.4.x sign-in since the backfill is not lost). A tipper left with no public field gets a placeholder name.

It refuses, writing nothing, while any tipper is unresolved: a public record with identity fields and no private
record (run the final backfill first), a field that differs between the two copies, or one only the public record has.

Usage: dart run bin/identity_purge.dart [options]

  (no options)      plan only: read the two nodes and say what would be written. Writes nothing.
  --out <file>      also write the patch to <file>. It holds no email address, only removals, login times and names.
  --apply           write it. Needs --project and --snapshot. Refuses unless the identity mode is freeze or off and no
                    request is in flight, and unless a second read finds nothing unresolved and plans exactly the same patch. Afterwards it reads
                    again and the plan must be empty.
  --snapshot <file> before writing, save /AllTippers as it is now to <file> (it holds email addresses: keep it under
                    test/data/, which is git-ignored). A file already there is never overwritten.
  --project <id>    default $defaultIdentityProject for a plan; --apply must name it.

Run it with the mode at freeze and drained, then set the mode final and run the audit. It is safe to run again as a
sweep: on purged data the plan is empty. To go back, see bin/identity_restore.dart. The output names counts and opaque
ids only.
Exit codes: 0 done (or nothing to do), 1 blocked or not verified, 2 usage.
''';

/// Runs the purge tool. [storeFor] and [modeFor] build the stores for a project,
/// so tests can supply ones over the emulator.
Future<int> runPurgeCli(
  List<String> arguments, {
  required IdentityRecordsStore Function(String project) storeFor,
  required ModeStore Function(String project) modeFor,
  required StringSink out,
  required StringSink err,
  Future<void> Function(String path, String contents)? writeFile,
  bool Function(String path)? fileExists,
}) async {
  var apply = false;
  String? project;
  String? outFile;
  String? snapshotFile;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--apply':
        apply = true;
      case '--project':
        project = i + 1 < arguments.length ? arguments[++i] : null;
      case '--out':
        outFile = i + 1 < arguments.length ? arguments[++i] : null;
      case '--snapshot':
        snapshotFile = i + 1 < arguments.length ? arguments[++i] : null;
      default:
        err.writeln('Unknown argument ${arguments[i]}\n\n$purgeToolUsage');
        return 2;
    }
  }
  if (apply && project == null) {
    err.writeln(
      'ERROR: this writes data, so the project must be named: add --project <id> '
      '(production is $defaultIdentityProject).',
    );
    return 2;
  }
  if (apply && snapshotFile == null) {
    err.writeln(
      'ERROR: this removes data, so it is saved first: add --snapshot <file> '
      '(under test/data/, which is git-ignored).',
    );
    return 2;
  }
  final targetProject = project ?? defaultIdentityProject;
  final store = storeFor(targetProject);

  Future<({Object? tippers, PurgePlan plan})> read() async {
    final tippers = await store.readTippers();
    final plan = planPublicIdentityPurge(
      tippers: tippers,
      tipperPrivate: await store.readTipperPrivate(),
    );
    return (tippers: tippers, plan: plan);
  }

  final first = await read();
  _describe(first.plan, out);
  if (first.plan.isBlocked) {
    err.writeln(
      'BLOCKED: ${first.plan.blocking.length} tipper(s) are unresolved, so nothing is written:',
    );
    for (final finding in first.plan.blocking) {
      err.writeln('  $finding');
    }
    return 1;
  }

  if (outFile != null) {
    await (writeFile ?? _writeFile)(outFile, jsonEncode(first.plan.patch));
    out.writeln('Patch written to $outFile.');
  }
  if (!apply) {
    out.writeln(
      'Plan only: nothing was written. Add --apply (with --project and --snapshot) to write it.',
    );
    return 0;
  }
  if (first.plan.isEmpty) {
    out.writeln('Nothing to purge.');
    return 0;
  }
  if ((fileExists ?? _fileExists)(snapshotFile!)) {
    err.writeln(
      'STOP: $snapshotFile already exists and is never overwritten. Name a new snapshot file.',
    );
    return 1;
  }

  final modeStore = modeFor(targetProject);
  final mode = (await modeStore.readMode()).mode;
  if (mode != IdentityMode.freeze && mode != IdentityMode.off) {
    err.writeln(
      'STOP: the identity mode is ${mode.name}. Set freeze (or off) and drain first, so no callable '
      'writes while the purge runs.',
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

  final second = await read();
  // A record that has become unresolved since the first read adds nothing to the
  // patch for the others, so the patch alone would not show it.
  if (second.plan.isBlocked) {
    err.writeln(
      'STOP: ${second.plan.blocking.length} tipper(s) are unresolved on the second read, so nothing '
      'was written:',
    );
    for (final finding in second.plan.blocking) {
      err.writeln('  $finding');
    }
    return 1;
  }
  if (jsonEncode(second.plan.patch) != jsonEncode(first.plan.patch)) {
    err.writeln(
      'STOP: the data changed between the two reads, so nothing was written. Run it again.',
    );
    return 1;
  }

  // The state the second read planned from is the state saved: nothing has been
  // written since, and nothing is written until the file is safely on disk.
  try {
    await (writeFile ?? _writeFile)(snapshotFile, jsonEncode(second.tippers));
  } on Object catch (error) {
    err.writeln(
      'STOP: could not save the snapshot ($error), so nothing was written.',
    );
    return 1;
  }
  out.writeln(
    'Snapshot of /AllTippers saved to $snapshotFile (it holds email addresses).',
  );

  await store.applyPatch(first.plan.patch);
  final after = await read();
  if (!after.plan.isEmpty || after.plan.isBlocked) {
    err.writeln(
      'NOT VERIFIED: after writing, ${after.plan.fieldsToRemove} field(s) would still be removed '
      'and ${after.plan.blocking.length} tipper(s) are unresolved.',
    );
    return 1;
  }
  out.writeln(
    'Purged ${first.plan.fieldsToRemove} field(s) from ${first.plan.recordsToPurge} record(s); '
    'a second plan finds nothing left. Now set the identity mode to final and run the audit.',
  );
  return 0;
}

void _describe(PurgePlan plan, StringSink out) {
  out.writeln(
    'Would remove ${plan.fieldsToRemove} field(s) from ${plan.recordsToPurge} record(s).',
  );
  if (plan.loginTimesPreserved > 0) {
    out.writeln(
      '${plan.loginTimesPreserved} later login time(s) in the public records are written to the private records first.',
    );
  }
  if (plan.placeholderNames > 0) {
    out.writeln(
      '${plan.placeholderNames} tipper(s) are left with no public field and get a placeholder name.',
    );
  }
}

Future<void> _writeFile(String path, String contents) =>
    File(path).writeAsString(contents);

bool _fileExists(String path) => File(path).existsSync();
