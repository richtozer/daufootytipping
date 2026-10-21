import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/backfill_plan.dart';

const String backfillUsage = '''
Plans or checks the identity backfill (DESIGN-database-rules-phase4.md, M4a). It reads files and writes
files; it never contacts the database or Firebase.

Usage: dart run bin/identity_backfill.dart --file <export.json> --auth-export <auth.json> [options]

  --file <path>            whole-database export: firebase database:get / --project <id> -o <path>
  --auth-export <path>     firebase auth:export <path> --project <id>. It holds PASSWORD HASHES, which are never
                           read; only uid, email and emailVerified are. Must be git-ignored. Delete it afterwards.
  --allowlist <path>       admin allowlist (default ../config/admin-auth-uids.json)
  --approved-links <path>  JSON { "<tipperId>": "<authUid>" }: owner-reviewed links of a placeholder record to
                           the account that is that person. Without an entry, a candidate is never linked.
  --patch-out <path>       write the multi-path update (contains personal data: must be git-ignored).
                           Not written while any blocking finding remains.
  --report-out <path>      write the findings (tipper ids and database paths only) as JSON
  --check                  exit 1 unless the database already matches the plan and nothing is amiss
                           (the verifier after the backfill, and the drift report afterwards)

Apply a patch with: firebase database:update / <patch> --project <id> --disable-triggers
(scripts/apply-identity-backfill.sh does the checks around it.)
''';

/// Runs the tool. Returns the process exit code: 0 success, 1 a failed
/// `--check`, 2 blocking findings or unusable input.
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
    for (final sensitive in [parsed.authExport, parsed.patchOut]) {
      if (sensitive != null) {
        _requireGitIgnoredInsideRepo(sensitive);
      }
    }
    input = BackfillInput(
      database: _readObject(parsed.file, 'database export'),
      authUsers: parseAuthExport(_readJson(parsed.authExport, 'Auth export')),
      adminAllowlist: parseAllowlist(_readJson(parsed.allowlist, 'allowlist')),
      approvedLinks: parsed.approvedLinks == null
          ? const <String, String>{}
          : parseApprovedLinks(
              _readJson(parsed.approvedLinks!, 'approved links'),
            ),
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

  if (parsed.check) {
    return plan.isClean ? 0 : 1;
  }
  return plan.hasBlockingFindings ? 2 : 0;
}

/// Reads a `firebase auth:export` file. Only the uid, email and verified flag
/// of each user are read; the password hashes in the file are ignored.
Map<String, AuthUser> parseAuthExport(Object? decoded) {
  final users = decoded is Map ? decoded['users'] : null;
  if (users is! List) {
    throw const FormatException(
      'The Auth export has no "users" list; is it a `firebase auth:export` JSON file?',
    );
  }
  final byUid = <String, AuthUser>{};
  for (final raw in users) {
    if (raw is! Map) {
      continue;
    }
    final uid = raw['localId'] ?? raw['uid'];
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
    throw const FormatException('The Auth export contains no users.');
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

/// Reads the owner-reviewed links: `{ "<tipperId>": "<authUid>" }`. Keys that
/// begin with an underscore are comments.
Map<String, String> parseApprovedLinks(Object? decoded) {
  if (decoded is! Map) {
    throw const FormatException('Approved links must be a JSON object.');
  }
  final links = <String, String>{};
  for (final entry in decoded.entries) {
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
  return links;
}

/// A readable summary. It names tipper ids and database paths, never names or addresses.
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
      final flag = finding.kind.blocking ? 'BLOCKS' : 'info  ';
      final shown = finding.subjects.take(12).join('  ');
      final more = finding.subjects.length > 12
          ? '  ... and ${finding.subjects.length - 12} more (see the report file)'
          : '';
      buffer.writeln(
        '  [$flag] ${finding.kind.name} (${finding.subjects.length}): $shown$more',
      );
    }
  }
  buffer.writeln(
    '\n${plan.writes.length} writes planned'
    '${plan.hasBlockingFindings ? ', but blocking findings must be settled first' : ''}.',
  );
  return buffer.toString();
}

/// The findings as data, for the report file. Ids and paths only.
Map<String, Object?> planReport(BackfillPlan plan) => {
  'counts': plan.counts,
  'blocking': plan.hasBlockingFindings,
  'findings': [
    for (final finding in plan.findings)
      {
        'kind': finding.kind.name,
        'blocking': finding.kind.blocking,
        'subjects': finding.subjects,
      },
  ],
};

class _Arguments {
  _Arguments({
    required this.help,
    required this.file,
    required this.authExport,
    required this.allowlist,
    required this.approvedLinks,
    required this.patchOut,
    required this.reportOut,
    required this.check,
  });

  final bool help;
  final String file;
  final String authExport;
  final String allowlist;
  final String? approvedLinks;
  final String? patchOut;
  final String? reportOut;
  final bool check;

  static const Set<String> _withValue = {
    '--file',
    '--auth-export',
    '--allowlist',
    '--approved-links',
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
      } else if (argument == '--check' || argument == '--help') {
        flags.add(argument);
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }
    final help = flags.contains('--help');
    if (!help) {
      for (final required in ['--file', '--auth-export']) {
        if (!values.containsKey(required)) {
          throw FormatException('$required is required.');
        }
      }
    }
    return _Arguments(
      help: help,
      file: values['--file'] ?? '',
      authExport: values['--auth-export'] ?? '',
      allowlist: values['--allowlist'] ?? '../config/admin-auth-uids.json',
      approvedLinks: values['--approved-links'],
      patchOut: values['--patch-out'],
      reportOut: values['--report-out'],
      check: flags.contains('--check'),
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
