import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/backfill_plan.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';

/// The identity backfill applied to a real Realtime Database (the emulator, through the production
/// REST handle), then checked by the same planner.
///
/// This proves what unit tests cannot: that the database accepts every key the plan produces
/// (unicode aliases, hashed login emails), that one multi-path update lands as the plan says, and that
/// the verifier then finds nothing to do. With a copy of a production export at
/// `test/data/production-export.json` it also runs on the real records (skipped without the file).
final File _export = File('../test/data/production-export.json');

const String _adminUid = 'adminUid0000000000000000001';
const String _patUid = 'patUid000000000000000000002';
const String _samUid = 'samUid000000000000000000003';

Map<String, Object?> _syntheticDatabase() => {
  'AllTippers': {
    'admin': {
      'name': 'The Admin',
      'authuid': _adminUid,
      'tipperRole': 'admin',
      'logon': 'admin@example.com',
      'isAnonymous': false,
    },
    'pat': {
      'name': 'Zoë Ünïcode Παύλος',
      'authuid': _patUid,
      'tipperRole': 'tipper',
      'logon': 'Pat.Plus+tag@Example.com',
      'email': 'pat@example.com',
      'compsParticipatedIn': ['comp-1'],
      'acctLoggedOnUTC': '2026-03-01 04:05:06.000Z',
    },
    'old': {
      'name': 'Old',
      'authuid': 'old.player@example.com',
      'tipperRole': 'tipper',
    },
    'sam1': {'name': 'Sam', 'authuid': _samUid, 'tipperRole': 'tipper'},
    'sam2': {
      'name': 's a m',
      'authuid': 'sam@example.com',
      'tipperRole': 'tipper',
    },
  },
};

Map<String, AuthUser> _accounts(Iterable<String> uids) => {
  for (final uid in uids) uid: AuthUser(uid: uid, emailVerified: true),
};

Future<Map<String, Object?>> _readAll(RestDatabase database) async {
  final value = (await database.ref('/').once()).value;
  return value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
}

Future<void> _applyAndCheck(
  RestDatabase database, {
  required Map<String, Object?> data,
  required Map<String, AuthUser> accounts,
  required Set<String> allowlist,
}) async {
  await database.ref('/').set(data);

  BackfillInput inputFrom(Map<String, Object?> db) => BackfillInput(
    database: db,
    authUsers: accounts,
    adminAllowlist: allowlist,
  );

  final first = planIdentityBackfill(inputFrom(await _readAll(database)));
  expect(
    first.hasBlockingFindings,
    false,
    reason: '${first.findings.map((f) => f.kind.name)}',
  );
  expect(first.writes, isNotEmpty);

  await database.ref('/').update(first.writes);

  final second = planIdentityBackfill(inputFrom(await _readAll(database)));
  expect(
    second.writes,
    isEmpty,
    reason: 'the verifier finds nothing left to write',
  );
  expect(
    second.findings.where((finding) => finding.kind.blocking),
    isEmpty,
    reason: 'and nothing wrong',
  );
  expect(second.isClean, true);
  expect(second.counts['alreadyPresent'], first.writes.length);
}

void main() {
  final skip = emulatorSkipReason;

  group('the backfill on a real database', () {
    late final database = openEmulatorDatabase();
    setUp(() => clearEmulatorDatabase(database));

    test('lands as planned, and the verifier is then clean', () async {
      await _applyAndCheck(
        database,
        data: _syntheticDatabase(),
        accounts: _accounts([_adminUid, _patUid, _samUid]),
        allowlist: {_adminUid},
      );

      final stored = await _readAll(database);
      expect((stored['AuthIndex']! as Map)[_patUid], 'pat');
      expect((stored['AliasIndex']! as Map)['zoëünïcodeπαύλος'], 'pat');
      expect((stored['Placeholders']! as Map)['old'], 'old.player@example.com');
      expect(
        (stored['TipperPrivate']! as Map).keys,
        containsAll(['admin', 'pat', 'old', 'sam1', 'sam2']),
      );
      expect(
        ((stored['AllTippers']! as Map)['pat'] as Map).containsKey('logon'),
        true,
        reason: 'the public record is untouched',
      );
    }, skip: skip);

    test(
      'a re-run after a stale claim appears is reported, not overwritten',
      () async {
        await _applyAndCheck(
          database,
          data: _syntheticDatabase(),
          accounts: _accounts([_adminUid, _patUid, _samUid]),
          allowlist: {_adminUid},
        );
        await database.ref('/AliasIndex/ghost').set('nobody');

        final plan = planIdentityBackfill(
          BackfillInput(
            database: await _readAll(database),
            authUsers: _accounts([_adminUid, _patUid, _samUid]),
            adminAllowlist: {_adminUid},
          ),
        );
        expect(plan.isClean, false);
        final blocking = plan.findings
            .where((finding) => finding.kind.blocking)
            .single;
        expect(blocking.kind, FindingKind.unexpectedEntry);
        expect(blocking.subjects, ['AliasIndex/ghost']);
      },
      skip: skip,
    );

    test(
      'the real records: every key is accepted and the verifier is clean',
      () async {
        final root =
            jsonDecode(_export.readAsStringSync()) as Map<String, Object?>;
        final tippers = Map<String, Object?>.from(root['AllTippers']! as Map);
        // No Auth data in a database export, so accounts are told apart by the shape Firebase generates.
        final shape = RegExp(r'^[A-Za-z0-9]{28}$');
        final accounts = <String>{
          for (final tipper in tippers.values)
            if ((tipper as Map)['authuid'] is String &&
                shape.hasMatch(tipper['authuid'] as String))
              tipper['authuid'] as String,
        };
        final admins = <String>{
          for (final tipper in tippers.values)
            if ((tipper as Map)['tipperRole'] == 'admin' &&
                accounts.contains(tipper['authuid']))
              tipper['authuid'] as String,
        };
        await _applyAndCheck(
          database,
          data: {
            'AllTippers': tippers,
            if (root['AppConfig'] != null) 'AppConfig': root['AppConfig'],
            if (root['AllTips'] != null) 'AllTips': root['AllTips'],
          },
          accounts: _accounts(accounts),
          allowlist: admins,
        );
      },
      skip:
          skip ??
          (_export.existsSync()
              ? null
              : 'copy a production export to test/data/production-export.json'),
    );
  });
}
