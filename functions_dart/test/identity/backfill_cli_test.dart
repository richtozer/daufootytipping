import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/backfill_cli.dart';
import 'package:test/test.dart';

import '../support/apply_writes.dart';

const String _adminUid = 'adminUid0000000000000000001';
const String _patUid = 'patUid000000000000000000002';

Map<String, Object?> _database() => {
  'AllTippers': {
    'admin': {
      'name': 'The Admin',
      'authuid': _adminUid,
      'tipperRole': 'admin',
      'logon': 'admin@example.com',
    },
    'pat': {
      'name': 'Pat',
      'authuid': _patUid,
      'tipperRole': 'tipper',
      'logon': 'pat@example.com',
    },
    'old': {
      'name': 'Old',
      'authuid': 'old@example.com',
      'tipperRole': 'tipper',
    },
  },
};

Map<String, Object?> _authExport() => {
  'users': [
    {
      'localId': _adminUid,
      'email': 'admin@example.com',
      'emailVerified': true,
      'passwordHash': 'MUST-NEVER-BE-READ',
      'salt': 'x',
    },
    {'localId': _patUid, 'email': 'pat@example.com', 'emailVerified': true},
  ],
};

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('backfill_cli_'));
  tearDown(() => temp.deleteSync(recursive: true));

  String write(String name, Object? json) {
    final file = File('${temp.path}/$name')
      ..writeAsStringSync(jsonEncode(json));
    return file.path;
  }

  Future<({int code, String out, String err})> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runBackfillCli(args, out: out, err: err);
    return (code: code, out: out.toString(), err: err.toString());
  }

  Map<String, String> files({Map<String, Object?>? database}) => {
    '--file': write('db.json', database ?? _database()),
    '--auth-export': write('auth.json', _authExport()),
    '--allowlist': write('allow.json', {
      'adminAuthUids': [_adminUid],
    }),
  };

  List<String> args(
    Map<String, String> files, [
    List<String> more = const [],
  ]) => [
    for (final entry in files.entries) ...[entry.key, entry.value],
    ...more,
  ];

  group('the plan', () {
    test(
      'writes a patch for clean data and prints a summary without names',
      () async {
        final patchPath = '${temp.path}/patch.json';
        final result = await run(args(files(), ['--patch-out', patchPath]));

        expect(result.code, 0, reason: result.err);
        expect(result.out, contains('writes planned'));
        expect(result.out, isNot(contains('Pat')));
        expect(result.out, isNot(contains('pat@example.com')));
        final patch =
            jsonDecode(File(patchPath).readAsStringSync())
                as Map<String, Object?>;
        expect(patch['AuthIndex/$_patUid'], 'pat');
        expect(patch['Placeholders/old'], 'old@example.com');
      },
    );

    test('never reads the password hashes in the Auth export', () async {
      final result = await run(args(files()));
      expect(result.out, isNot(contains('MUST-NEVER-BE-READ')));
      expect(result.err, isNot(contains('MUST-NEVER-BE-READ')));
    });

    test(
      'does not write a patch while a finding blocks, and exits 2',
      () async {
        final database = _database();
        (database['AllTippers']! as Map<String, Object?>)['liv'] = {
          'name': 'Liv',
          'authuid': _patUid,
          'tipperRole': 'admin',
        };
        final patchPath = '${temp.path}/patch.json';
        final result = await run(
          args(files(database: database), ['--patch-out', patchPath]),
        );

        expect(result.code, 2);
        expect(result.out, contains('BLOCKS'));
        expect(File(patchPath).existsSync(), false);
      },
    );

    test('writes a findings file of ids and paths only', () async {
      final reportPath = '${temp.path}/report.json';
      await run(args(files(), ['--report-out', reportPath]));
      final report =
          jsonDecode(File(reportPath).readAsStringSync())
              as Map<String, Object?>;
      expect(report['blocking'], false);
      expect(jsonEncode(report), isNot(contains('@example.com')));
    });
  });

  group('--check', () {
    test('fails before the patch is applied and passes after', () async {
      final inputs = files();
      final patchPath = '${temp.path}/patch.json';
      await run(args(inputs, ['--patch-out', patchPath]));
      expect((await run(args(inputs, ['--check']))).code, 1);

      final patch =
          jsonDecode(File(patchPath).readAsStringSync())
              as Map<String, Object?>;
      final applied = write('applied.json', applyWrites(_database(), patch));
      final result = await run(
        args({...inputs, '--file': applied}, ['--check']),
      );
      expect(result.code, 0, reason: result.out);
    });
  });

  group('approved links', () {
    test('link a placeholder to its account in the patch', () async {
      final links = write('links.json', {
        '_comment': 'reviewed by the owner',
        'old': _patUid,
      });
      final database = _database();
      (database['AllTippers']! as Map<String, Object?>).remove('pat');
      final patchPath = '${temp.path}/patch.json';
      final result = await run(
        args(files(database: database), [
          '--approved-links',
          links,
          '--patch-out',
          patchPath,
        ]),
      );
      expect(result.code, 0, reason: result.out + result.err);
      final patch =
          jsonDecode(File(patchPath).readAsStringSync())
              as Map<String, Object?>;
      expect(patch['AllTippers/old/authuid'], _patUid);
    });
  });

  group('input handling', () {
    test('missing required arguments print the usage and exit 2', () async {
      final result = await run(['--file', 'x.json']);
      expect(result.code, 2);
      expect(result.err, contains('--auth-export is required'));
    });

    test('an unknown argument is refused', () async {
      expect((await run(['--bogus'])).code, 2);
    });

    test('--help prints the usage', () async {
      final result = await run(['--help']);
      expect(result.code, 0);
      expect(result.out, contains('Usage:'));
    });

    test('a missing file is a clear error, not a crash', () async {
      final result = await run(
        args({...files(), '--file': '${temp.path}/nope.json'}),
      );
      expect(result.code, 2);
      expect(result.err, contains('nope.json'));
    });

    test('an Auth export with no users is refused', () async {
      final result = await run(
        args({
          ...files(),
          '--auth-export': write('empty.json', {'users': []}),
        }),
      );
      expect(result.code, 2);
      expect(result.err, contains('no users'));
    });

    test(
      'a patch or Auth export inside the repository must be git-ignored',
      () async {
        final result = await run(
          args(files(), ['--patch-out', 'pubspec.yaml']),
        );
        expect(result.code, 2);
        expect(result.err, contains('not git-ignored'));
      },
    );
  });

  group('parsers', () {
    test('parseAllowlist needs a non-empty list of strings', () {
      expect(
        parseAllowlist({
          'adminAuthUids': ['a'],
        }),
        {'a'},
      );
      expect(
        () => parseAllowlist({'adminAuthUids': []}),
        throwsFormatException,
      );
      expect(
        () => parseAllowlist({
          'adminAuthUids': [1],
        }),
        throwsFormatException,
      );
      expect(() => parseAllowlist(null), throwsFormatException);
    });

    test('parseApprovedLinks skips comments and rejects a blank uid', () {
      expect(parseApprovedLinks({'_note': 'x', 'a': 'uid'}), {'a': 'uid'});
      expect(() => parseApprovedLinks({'a': ''}), throwsFormatException);
      expect(() => parseApprovedLinks([]), throwsFormatException);
    });
  });
}
