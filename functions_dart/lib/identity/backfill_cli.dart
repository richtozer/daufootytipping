import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/backfill_plan.dart';

const String backfillUsage = '''
Plans or checks the identity backfill (DESIGN-database-rules-phase4.md, M4a). It reads files and writes
files; it never contacts the database or Firebase.

Usage: dart run bin/identity_backfill.dart --file <export.json> --auth-accounts <accounts.json> [options]

  --file <path>            whole-database export: firebase database:get / --project <id> -o <path>
  --auth-accounts <path>   the Firebase Auth accounts as { "users": [ { "uid", "email", "emailVerified" } ] }.
                           Make it with scripts/slim_auth_export.mjs from a `firebase auth:export`. A file that
                           still holds password hashes is refused, so they never reach this tool. Must be
                           git-ignored. Delete it, and the full export, afterwards.
  --allowlist <path>       admin allowlist (default ../config/admin-auth-uids.json)
  --decisions <path>       the owner's reviewed decisions, as JSON:
                             { "links":      { "<tipperId>": "<authUid>" },
                               "aliasOwners": [ "<tipperId>", ... ] }
                           "links" tie a placeholder record to the account that is that person; without an
                           entry a candidate is never linked. "aliasOwners" name the record that owns a shared
                           alias; without one the ranking only proposes an owner. Keys beginning "_" are comments.
  --patch-out <path>       write the multi-path update (contains personal data: must be git-ignored).
                           Not written while any blocking finding remains.
  --report-out <path>      write the findings (tipper ids and database paths only) as JSON
  --check                  exit 1 unless the database already matches the plan and nothing blocks it: the
                           verifier after the backfill, and the drift report afterwards. It does NOT mean the
                           identities are ready for R2; findings marked "cutover" can remain.
  --strict                 as --check, and also exit 1 while any finding marked "cutover" remains (duplicate
                           accounts, shared aliases or login emails, ambiguous contacts): the cutover check.

Apply a patch with scripts/apply-identity-backfill.sh, which re-plans from live data first.
''';

/// Runs the tool. Returns the process exit code: 0 success, 1 a failed
/// `--check` or `--strict`, 2 blocking findings or unusable input.
Future<int> runBackfillCli(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
}) async {
  final _Arguments parsed;
  try {
    parsed = _Arguments.parse(arguments);
  } on FormatException catch (error) {
    err.writeln('${error.message}\n\n$backfillUsage');
    return 2;
  }
  if (parsed.help) {
    out.writeln(backfillUsage);
    return 0;
  }

  final BackfillInput input;
  try {
    for (final sensitive in [parsed.authAccounts, parsed.patchOut]) {
      if (sensitive != null) {
        _requireGitIgnoredInsideRepo(sensitive);
      }
    }
    final decisions = parsed.decisions == null
        ? const BackfillDecisions()
        : parseDecisions(_readJson(parsed.decisions!, 'decisions'));
    input = BackfillInput(
      database: _readObject(parsed.file, 'database export'),
      authUsers: parseAuthAccounts(
        _readJson(parsed.authAccounts, 'Auth accounts'),
      ),
      adminAllowlist: parseAllowlist(_readJson(parsed.allowlist, 'allowlist')),
      approvedLinks: decisions.links,
      approvedAliasOwners: decisions.aliasOwners,
    );
  } on FormatException catch (error) {
    err.writeln('ERROR: ${error.message}');
    return 2;
  } on FileSystemException catch (error) {
    err.writeln('ERROR: ${error.message}: ${error.path}');
    return 2;
  }

  final plan = planIdentityBackfill(input);
  out.write(describePlan(plan));

  final reportOut = parsed.reportOut;
  if (reportOut != null) {
    File(reportOut).writeAsStringSync('${_prettyJson(planReport(plan))}\n');
    out.writeln('Wrote the findings (ids and paths only) to $reportOut');
  }
  final patchOut = parsed.patchOut;
  if (patchOut != null) {
    if (plan.hasBlockingFindings) {
      out.writeln('Patch not written: settle the blocking findings first.');
    } else {
      File(patchOut).writeAsStringSync('${_prettyJson(plan.writes)}\n');
      out.writeln(
        'Wrote ${plan.writes.length} writes to $patchOut (personal data inside).',
      );
    }
  }

  if (parsed.strict) {
    return plan.isCutoverReady ? 0 : 1;
  }
  if (parsed.check) {
    return plan.isClean ? 0 : 1;
  }
  return plan.hasBlockingFindings ? 2 : 0;
}

/// Reads the Auth accounts file: `{ "users": [ { "uid", "email",
/// "emailVerified" } ] }`, as written by `scripts/slim_auth_export.mjs`.
///
/// A file that still carries password hashes (a raw `firebase auth:export`) is
/// refused outright, so the hashes never reach this tool at all.
Map<String, AuthUser> parseAuthAccounts(Object? decoded) {
  final users = decoded is Map ? decoded['users'] : null;
  if (users is! List) {
    throw const FormatException(
      'The Auth accounts file has no "users" list. Make it with scripts/slim_auth_export.mjs.',
    );
  }
  final byUid = <String, AuthUser>{};
  for (final raw in users) {
    if (raw is! Map) {
      continue;
    }
    if (raw.containsKey('passwordHash') ||
        raw.containsKey('salt') ||
        raw.containsKey('passwordSalt')) {
      throw const FormatException(
        'This looks like a raw `firebase auth:export`: it holds password hashes. '
        'Slim it first with scripts/slim_auth_export.mjs, and delete the full export.',
      );
    }
    final uid = raw['uid'];
    if (uid is! String || uid.isEmpty) {
      continue;
    }
    final email = raw['email'];
    byUid[uid] = AuthUser(
      uid: uid,
      email: email is String ? email : null,
      emailVerified: raw['emailVerified'] == true,
    );
  }
  if (byUid.isEmpty) {
    throw const FormatException('The Auth accounts file contains no users.');
  }
  return byUid;
}

/// Reads `config/admin-auth-uids.json`.
Set<String> parseAllowlist(Object? decoded) {
  final uids = decoded is Map ? decoded['adminAuthUids'] : null;
  if (uids is! List || uids.isEmpty || uids.any((uid) => uid is! String)) {
    throw const FormatException(
      'The allowlist must hold a non-empty "adminAuthUids" list of strings.',
    );
  }
  return uids.cast<String>().toSet();
}

/// The owner's reviewed decisions.
class BackfillDecisions {
  const BackfillDecisions({
    this.links = const <String, String>{},
    this.aliasOwners = const <String>{},
  });

  final Map<String, String> links;
  final Set<String> aliasOwners;
}

/// Reads the decisions file: `{ "links": { "<tipperId>": "<authUid>" },
/// "aliasOwners": [ "<tipperId>" ] }`. Keys that begin with an underscore are
/// comments.
BackfillDecisions parseDecisions(Object? decoded) {
  if (decoded is! Map) {
    throw const FormatException('The decisions must be a JSON object.');
  }
  final links = <String, String>{};
  final rawLinks = decoded['links'] ?? const <String, Object?>{};
  if (rawLinks is! Map) {
    throw const FormatException(
      '"links" must be an object of tipperId: authUid.',
    );
  }
  for (final entry in rawLinks.entries) {
    final key = entry.key.toString();
    if (key.startsWith('_')) {
      continue;
    }
    final uid = entry.value;
    if (uid is! String || uid.isEmpty) {
      throw FormatException('The approved link for $key must be an auth uid.');
    }
    links[key] = uid;
  }
  final rawOwners = decoded['aliasOwners'] ?? const <Object?>[];
  if (rawOwners is! List ||
      rawOwners.any((id) => id is! String || id.isEmpty)) {
    throw const FormatException('"aliasOwners" must be a list of tipper ids.');
  }
  return BackfillDecisions(
    links: links,
    aliasOwners: rawOwners.cast<String>().toSet(),
  );
}

/// A readable summary. It names tipper ids and database paths, never names or
/// addresses. Each finding says whether it blocks the patch, blocks the R2
/// cutover, or is only information.
String describePlan(BackfillPlan plan) {
  final buffer = StringBuffer('Identity backfill (reads files only)\n\n');
  for (final entry in plan.counts.entries) {
    buffer.writeln('  ${entry.key.padRight(20)} ${entry.value}');
  }
  if (plan.findings.isEmpty) {
    buffer.writeln('\nNo findings.');
  } else {
    buffer.writeln('\nFindings');
    for (final finding in plan.findings) {
      final flag = finding.kind.blocking
          ? 'BLOCKS'
          : finding.kind.blocksCutover
          ? 'cutover'
          : 'info';
      final shown = finding.subjects.take(12).join('  ');
      final more = finding.subjects.length > 12
          ? '  ... and ${finding.subjects.length - 12} more (see the report file)'
          : '';
      buffer.writeln(
        '  [${flag.padRight(7)}] ${finding.kind.name} (${finding.subjects.length}): $shown$more',
      );
    }
    buffer.writeln(
      '\n  BLOCKS  = settle before applying.   cutover = does not stop the backfill; '
      'resolve before the R2 cutover.   info = no action needed.',
    );
  }
  buffer.writeln(
    '\n${plan.writes.length} writes planned'
    '${plan.hasBlockingFindings ? ', but blocking findings must be settled first' : ''}.',
  );
  if (!plan.hasBlockingFindings && plan.writes.isEmpty) {
    buffer.writeln(
      plan.isCutoverReady
          ? 'Backfill in place, and no cutover findings remain.'
          : 'Backfill in place. NOT ready for the R2 cutover: the "cutover" findings above remain.',
    );
  }
  return buffer.toString();
}

/// The findings as data, for the report file. Ids and paths only.
Map<String, Object?> planReport(BackfillPlan plan) => {
  'counts': plan.counts,
  'blocking': plan.hasBlockingFindings,
  'cutoverReady': plan.isCutoverReady,
  'findings': [
    for (final finding in plan.findings)
      {
        'kind': finding.kind.name,
        'blocking': finding.kind.blocking,
        'blocksCutover': finding.kind.blocksCutover,
        'subjects': finding.subjects,
      },
  ],
};

class _Arguments {
  _Arguments({
    required this.help,
    required this.file,
    required this.authAccounts,
    required this.allowlist,
    required this.decisions,
    required this.patchOut,
    required this.reportOut,
    required this.check,
    required this.strict,
  });

  final bool help;
  final String file;
  final String authAccounts;
  final String allowlist;
  final String? decisions;
  final String? patchOut;
  final String? reportOut;
  final bool check;
  final bool strict;

  static const Set<String> _withValue = {
    '--file',
    '--auth-accounts',
    '--allowlist',
    '--decisions',
    '--patch-out',
    '--report-out',
  };

  static _Arguments parse(List<String> arguments) {
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (_withValue.contains(argument)) {
        if (index + 1 >= arguments.length) {
          throw FormatException('$argument needs a value.');
        }
        values[argument] = arguments[index += 1];
      } else if (argument == '--check' ||
          argument == '--strict' ||
          argument == '--help') {
        flags.add(argument);
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }
    final help = flags.contains('--help');
    if (!help) {
      for (final required in ['--file', '--auth-accounts']) {
        if (!values.containsKey(required)) {
          throw FormatException('$required is required.');
        }
      }
    }
    return _Arguments(
      help: help,
      file: values['--file'] ?? '',
      authAccounts: values['--auth-accounts'] ?? '',
      allowlist: values['--allowlist'] ?? '../config/admin-auth-uids.json',
      decisions: values['--decisions'],
      patchOut: values['--patch-out'],
      reportOut: values['--report-out'],
      check: flags.contains('--check'),
      strict: flags.contains('--strict'),
    );
  }
}

Object? _readJson(String path, String what) {
  try {
    return jsonDecode(File(path).readAsStringSync());
  } on FormatException {
    throw FormatException('The $what at $path is not valid JSON.');
  }
}

Map<String, Object?> _readObject(String path, String what) {
  final decoded = _readJson(path, what);
  if (decoded is! Map) {
    throw FormatException('The $what at $path is not a JSON object.');
  }
  return Map<String, Object?>.from(decoded);
}

String _prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

/// A file holding personal data may live outside the repository, or inside it
/// only where git ignores it, so it cannot be committed by accident.
void _requireGitIgnoredInsideRepo(String path) {
  final repoRoot = _gitOutput(['rev-parse', '--show-toplevel']);
  if (repoRoot == null) {
    return;
  }
  final absolute = File(path).absolute.path;
  if (!absolute.startsWith(repoRoot)) {
    return;
  }
  final ignored = Process.runSync('git', ['check-ignore', '-q', absolute]);
  if (ignored.exitCode != 0) {
    throw FormatException(
      '$path is inside the repository and not git-ignored, and it holds personal data. '
      'Use a path under /test/data/ (ignored) or outside the repository.',
    );
  }
}

String? _gitOutput(List<String> arguments) {
  try {
    final result = Process.runSync('git', arguments);
    return result.exitCode == 0 ? (result.stdout as String).trim() : null;
  } on ProcessException {
    return null;
  }
}
