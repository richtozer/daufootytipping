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

Map<String, Object?> _authAccounts() => {
  'users': [
    {'uid': _adminUid, 'email': 'admin@example.com', 'emailVerified': true},
    {'uid': _patUid, 'email': 'pat@example.com', 'emailVerified': true},
  ],
};

typedef _Result = ({int code, String out, String err});

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('backfill_cli_'));
  tearDown(() => temp.deleteSync(recursive: true));

  String write(String name, Object? json) {
    final file = File('${temp.path}/$name')
      ..writeAsStringSync(jsonEncode(json));
    return file.path;
  }

  Future<_Result> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runBackfillCli(args, out: out, err: err);
    return (code: code, out: out.toString(), err: err.toString());
  }

  Map<String, String> files({Map<String, Object?>? database}) => {
    '--file': write('db-${database.hashCode}.json', database ?? _database()),
    '--auth-accounts': write('accounts.json', _authAccounts()),
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

  /// Plans once and returns the patch that was written, so a test can apply it.
  Future<Map<String, Object?>> patchFor(Map<String, String> inputs) async {
    final path = '${temp.path}/patch-${inputs['--file']!.hashCode}.json';
    await run(args(inputs, ['--patch-out', path]));
    return jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  }

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

    test(
      'refuses a raw Auth export, so password hashes never reach the tool',
      () async {
        final raw = write('raw-auth.json', {
          'users': [
            {
              'localId': _adminUid,
              'uid': _adminUid,
              'email': 'admin@example.com',
              'passwordHash': 'MUST-NEVER-BE-USED',
              'salt': 'x',
            },
          ],
        });
        final result = await run(args({...files(), '--auth-accounts': raw}));
        expect(result.code, 2);
        expect(result.err, contains('password hashes'));
        expect(result.out, isNot(contains('MUST-NEVER-BE-USED')));
        expect(result.err, isNot(contains('MUST-NEVER-BE-USED')));
      },
    );

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

  group('--check and --strict', () {
    test(
      '--check fails before the patch is applied and passes after',
      () async {
        final inputs = files();
        expect((await run(args(inputs, ['--check']))).code, 1);

        final patch = await patchFor(inputs);
        final applied = write('applied.json', applyWrites(_database(), patch));
        final result = await run(
          args({...inputs, '--file': applied}, ['--check']),
        );
        expect(result.code, 0, reason: result.out);
      },
    );

    test('--strict passes only when no cutover finding remains', () async {
      final clean = files();
      final cleanPatch = await patchFor(clean);
      final appliedClean = write(
        'applied.json',
        applyWrites(_database(), cleanPatch),
      );
      expect(
        (await run(
          args({...clean, '--file': appliedClean}, ['--strict']),
        )).code,
        0,
      );

      final database = _database();
      (database['AllTippers']! as Map<String, Object?>)['dup'] = {
        'name': 'Dup',
        'authuid': _patUid,
        'tipperRole': 'tipper',
      };
      final duplicated = files(database: database);
      final dupPatch = await patchFor(duplicated);
      final appliedDup = write(
        'applied-dup.json',
        applyWrites(database, dupPatch),
      );

      final check = await run(
        args({...duplicated, '--file': appliedDup}, ['--check']),
      );
      expect(check.code, 0, reason: 'the backfill itself is in place');
      expect(check.out, contains('NOT ready for the R2 cutover'));

      final strict = await run(
        args({...duplicated, '--file': appliedDup}, ['--strict']),
      );
      expect(strict.code, 1);
      expect(strict.out, contains('[cutover] duplicateAccountUid'));
    });
  });

  group('decisions', () {
    test(
      'a reviewed link ties a placeholder to its account in the patch',
      () async {
        final decisions = write('decisions.json', {
          '_comment': 'reviewed by the owner',
          'links': {'old': _patUid},
        });
        final database = _database();
        (database['AllTippers']! as Map<String, Object?>).remove('pat');
        final patchPath = '${temp.path}/patch.json';
        final result = await run(
          args(files(database: database), [
            '--decisions',
            decisions,
            '--patch-out',
            patchPath,
          ]),
        );
        expect(result.code, 0, reason: result.out + result.err);
        final patch =
            jsonDecode(File(patchPath).readAsStringSync())
                as Map<String, Object?>;
        expect(patch['AllTippers/old/authuid'], _patUid);
      },
    );

    test(
      'a link onto an account another record holds blocks, and no patch is written',
      () async {
        final decisions = write('decisions.json', {
          'links': {'old': _patUid},
        });
        final patchPath = '${temp.path}/patch.json';
        final result = await run(
          args(files(), ['--decisions', decisions, '--patch-out', patchPath]),
        );
        expect(result.code, 2);
        expect(result.out, contains('approvedLinkRejected'));
        expect(File(patchPath).existsSync(), false);
      },
    );

    test('an alias owner decision is used and shown as approved', () async {
      final database = _database();
      (database['AllTippers']! as Map<String, Object?>)['pat2'] = {
        'name': 'p a t',
        'authuid': 'pat2@example.com',
        'tipperRole': 'tipper',
      };
      final decisions = write('decisions.json', {
        'aliasOwners': ['pat2'],
      });
      final result = await run(
        args(files(database: database), ['--decisions', decisions]),
      );
      expect(result.code, 0, reason: result.out + result.err);
      expect(result.out, contains('pat2,pat [approved]'));
    });
  });

  group('input handling', () {
    test('missing required arguments print the usage and exit 2', () async {
      final result = await run(['--file', 'x.json']);
      expect(result.code, 2);
      expect(result.err, contains('--auth-accounts is required'));
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

    test('an Auth accounts file with no users is refused', () async {
      final result = await run(
        args({
          ...files(),
          '--auth-accounts': write('empty.json', {'users': []}),
        }),
      );
      expect(result.code, 2);
      expect(result.err, contains('no users'));
    });

    test(
      'a patch or accounts file inside the repository must be git-ignored',
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

    test(
      'parseAuthAccounts reads uid, email and verified, and nothing else',
      () {
        final users = parseAuthAccounts({
          'users': [
            {
              'uid': 'u1',
              'email': 'a@example.com',
              'emailVerified': true,
              'extra': 'ignored',
            },
            {'uid': 'u2'},
          ],
        });
        expect(users.keys, ['u1', 'u2']);
        expect(users['u1']!.emailVerified, true);
        expect(users['u2']!.email, isNull);
      },
    );

    test('parseAuthAccounts refuses hashes and an empty list', () {
      expect(
        () => parseAuthAccounts({
          'users': [
            {'uid': 'u', 'passwordHash': 'x'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => parseAuthAccounts({
          'users': [
            {'uid': 'u', 'salt': 'x'},
          ],
        }),
        throwsFormatException,
      );
      expect(() => parseAuthAccounts({'users': []}), throwsFormatException);
      expect(() => parseAuthAccounts(null), throwsFormatException);
    });

    test(
      'parseDecisions reads links and alias owners, skips comments, rejects bad values',
      () {
        final decisions = parseDecisions({
          '_note': 'x',
          'links': {'_c': 'x', 'a': 'uid'},
          'aliasOwners': ['b'],
        });
        expect(decisions.links, {'a': 'uid'});
        expect(decisions.aliasOwners, {'b'});
        expect(parseDecisions({}).links, isEmpty);
        expect(
          () => parseDecisions({
            'links': {'a': ''},
          }),
          throwsFormatException,
        );
        expect(
          () => parseDecisions({
            'aliasOwners': [1],
          }),
          throwsFormatException,
        );
        expect(() => parseDecisions({'links': []}), throwsFormatException);
        expect(() => parseDecisions([]), throwsFormatException);
      },
    );
  });
}
