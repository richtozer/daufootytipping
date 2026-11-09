import 'dart:convert';

import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/restore_cli.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';

/// The rollback rehearsal (DESIGN-database-rules-phase4.md, section 9): the database in the shape cutover step B
/// leaves it, the restore tool run against it through the same code the owner runs, and the result compared with
/// what was there before the purge.
///
/// [modelOfThePurge] is this test's own statement of step B as the plan defines it. The real purge tool is built in
/// M8; when it is, its tests should run this same round trip with it in place of the model.

Map<String, Object?> _preCutover() => <String, Object?>{
  // Linked, with a photo and a paid comp.
  'tLinked': <String, Object?>{
    'name': 'Alice',
    'photoURL': 'a.png',
    'compsParticipatedIn': <String>['c1'],
    'authuid': 'uidLinked',
    'tipperRole': 'tipper',
    'email': 'alice@example.test',
    'logon': 'alice@example.test',
    'isAnonymous': false,
    'acctCreatedUTC': '2026-03-01 04:05:06.000Z',
    'acctLoggedOnUTC': '2026-03-02 04:05:06.000Z',
  },
  // An administrator.
  'tAdmin': <String, Object?>{
    'name': 'Root',
    'authuid': 'uidAdmin',
    'tipperRole': 'admin',
    'email': 'root@example.test',
    'logon': 'root@example.test',
    'isAnonymous': false,
  },
  // A historical tipper nobody has signed in as: the legacy shape says "no account" with an empty authuid.
  'tUnlinked': <String, Object?>{
    'name': 'Old Timer',
    'authuid': '',
    'tipperRole': 'tipper',
    'email': 'old@example.test',
    'logon': 'old@example.test',
    'isAnonymous': false,
    'compsParticipatedIn': <String>['c0'],
  },
  // Signed up in 2025 without an alias: only contact fields, so the purge must give them a name.
  'tNoAlias123456': <String, Object?>{
    'authuid': 'uidNoAlias',
    'tipperRole': 'tipper',
    'email': 'noalias@example.test',
    'logon': 'noalias@example.test',
    'isAnonymous': false,
  },
  // An anonymous tipper, and one carrying the two legacy fields the purge deletes.
  'tAnon': <String, Object?>{
    'name': 'Visitor',
    'authuid': 'uidAnon',
    'tipperRole': 'tipper',
    'isAnonymous': true,
  },
  'tLegacy': <String, Object?>{
    'name': 'Legacy',
    'authuid': 'uidLegacy',
    'tipperRole': 'tipper',
    'email': 'legacy@example.test',
    'logon': 'legacy@example.test',
    'isAnonymous': false,
    'active': true,
    'tipperID': 'oldid',
  },
};

/// What cutover step B does to `/AllTippers` (section 8): removes the private fields and the two legacy fields
/// from every record, and gives a record left with none of the public fields a placeholder name so that it does
/// not vanish. `/TipperPrivate` is untouched.
Map<String, Object?> modelOfThePurge(Map<String, Object?> tippers) {
  final purged = <String, Object?>{};
  for (final entry in tippers.entries) {
    final record = Map<String, Object?>.of(
      entry.value! as Map<String, Object?>,
    );
    for (final field in [
      ...tipperPrivateFieldNames,
      ...tipperLegacyFieldNames,
    ]) {
      record.remove(field);
    }
    if (!tipperPublicFieldNames.any(record.containsKey)) {
      record['name'] = placeholderTipperName(entry.key);
    }
    purged[entry.key] = record;
  }
  return purged;
}

Map<String, Object?> _privateOf(Map<String, Object?> tippers) {
  final records = <String, Object?>{};
  for (final entry in tippers.entries) {
    final record = entry.value! as Map<String, Object?>;
    final privateRecord = <String, Object?>{
      for (final field in tipperPrivateFieldNames)
        // An unlinked tipper has no private authuid (the empty public one means "no account").
        if (record[field] != null &&
            !(field == 'authuid' && record[field] == ''))
          field: record[field],
    };
    records[entry.key] = privateRecord;
  }
  return records;
}

void main() {
  final skip = emulatorSkipReason;

  group('the rollback rehearsal on the emulator', () {
    late final RestDatabase db = openEmulatorDatabase();
    late Map<String, Object?> before;

    setUp(() async {
      await clearEmulatorDatabase(db);
      before = _preCutover();
      // The database as step B leaves it: public records purged, private records complete.
      await db.ref('AllTippers').set(modelOfThePurge(before));
      await db.ref('TipperPrivate').set(_privateOf(before));
      await db.ref(identityModePath).update(<String, Object?>{
        'mode': 'freeze',
      });
    });

    Future<({int code, String out, String err})> restore(
      List<String> args,
    ) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runRestoreCli(
        args,
        storeFor: (_) => RestRestoreStore(db),
        modeFor: (_) => RestModeStore(db),
        out: out,
        err: err,
      );
      return (code: code, out: '$out', err: '$err');
    }

    Future<Map<String, Object?>> tippersNow() async =>
        (jsonDecode(jsonEncode((await db.ref('AllTippers').once()).value))
                as Map<String, dynamic>)
            .cast<String, Object?>();

    test('the purge model leaves the shape the plan describes', () async {
      final purged = await tippersNow();
      expect(
        purged.keys.toSet(),
        before.keys.toSet(),
        reason: 'every tipper keeps a public node',
      );
      for (final record in purged.values) {
        for (final field in [
          ...tipperPrivateFieldNames,
          ...tipperLegacyFieldNames,
        ]) {
          expect((record! as Map).containsKey(field), false, reason: field);
        }
      }
      expect(
        (purged['tNoAlias123456']! as Map)['name'],
        placeholderTipperName('tNoAlias123456'),
      );
    });

    test('a plan changes nothing', () async {
      final purgedBefore = await tippersNow();
      final run = await restore(<String>[]);
      expect(run.code, 0, reason: run.err);
      expect(run.out, contains('Plan only'));
      expect(await tippersNow(), purgedBefore);
    });

    test(
      'restoring brings back exactly the shape that was there, bar the two deleted legacy fields and the placeholder name',
      () async {
        final run = await restore(<String>[
          '--apply',
          '--project',
          'demo-dau-rules',
        ]);
        expect(run.code, 0, reason: run.err);
        expect(run.out, contains('a second plan finds nothing left'));

        final restored = await tippersNow();
        expect(restored.keys.toSet(), before.keys.toSet());
        for (final entry in before.entries) {
          final expected = Map<String, Object?>.of(
            entry.value! as Map<String, Object?>,
          );
          for (final legacy in tipperLegacyFieldNames) {
            expected.remove(legacy); // deleted on purpose; not brought back
          }
          if (entry.key == 'tNoAlias123456') {
            expected['name'] = placeholderTipperName(
              entry.key,
            ); // the real name was never stored
          }
          expect(restored[entry.key], expected, reason: 'tipper ${entry.key}');
        }
      },
    );

    test(
      'every restored record satisfies what R1 requires of a tipper record',
      () async {
        await restore(<String>['--apply', '--project', 'demo-dau-rules']);
        for (final entry in (await tippersNow()).entries) {
          final record = entry.value! as Map;
          expect(
            record['authuid'],
            isA<String>(),
            reason: '${entry.key} authuid',
          );
          expect(
            <String>['admin', 'tipper'],
            contains(record['tipperRole']),
            reason: '${entry.key} role',
          );
          expect(record['name'], isA<String>(), reason: '${entry.key} name');
        }
      },
    );

    test(
      'the unlinked tipper is restored as unlinked: an empty authuid, not a missing one',
      () async {
        await restore(<String>['--apply', '--project', 'demo-dau-rules']);
        expect(((await tippersNow())['tUnlinked']! as Map)['authuid'], '');
      },
    );

    test('running it again writes nothing', () async {
      await restore(<String>['--apply', '--project', 'demo-dau-rules']);
      final restored = await tippersNow();
      final again = await restore(<String>[
        '--apply',
        '--project',
        'demo-dau-rules',
      ]);
      expect(again.code, 0);
      expect(again.out, contains('Nothing to restore'));
      expect(await tippersNow(), restored);
    });

    test(
      'it refuses while the callables are admitting requests, and writes nothing',
      () async {
        await db.ref(identityModePath).update(<String, Object?>{
          'mode': 'final',
        });
        final purged = await tippersNow();
        final run = await restore(<String>[
          '--apply',
          '--project',
          'demo-dau-rules',
        ]);
        expect(run.code, 1);
        expect(run.err, contains('Set freeze (or off) and drain first'));
        expect(await tippersNow(), purged);
      },
    );

    test(
      'it refuses while a request is in flight, and writes nothing',
      () async {
        await db.ref('$identityModePath/inflight/op1').set(<String, Object?>{
          'callable': 'link-or-create-tipper',
          'startedAtMs': 1,
        });
        final purged = await tippersNow();
        final run = await restore(<String>[
          '--apply',
          '--project',
          'demo-dau-rules',
        ]);
        expect(run.code, 1);
        expect(run.err, contains('still in flight'));
        expect(await tippersNow(), purged);
      },
    );

    test(
      'a purged public record whose private copy is missing blocks the whole restore',
      () async {
        await db.ref('TipperPrivate/tLinked').remove();
        final purged = await tippersNow();
        final run = await restore(<String>[
          '--apply',
          '--project',
          'demo-dau-rules',
        ]);
        expect(run.code, 1);
        expect(run.err, contains('tLinked'));
        expect(run.err, contains('no private one'));
        expect(
          await tippersNow(),
          purged,
          reason: 'nothing is written while any tipper is blocked',
        );
      },
    );

    test(
      'a tipper whose public record is missing blocks the whole restore',
      () async {
        await db.ref('AllTippers/tAdmin').remove();
        final purged = await tippersNow();
        final run = await restore(<String>[
          '--apply',
          '--project',
          'demo-dau-rules',
        ]);
        expect(run.code, 1);
        expect(run.err, contains('tAdmin'));
        expect(await tippersNow(), purged);
      },
    );
  }, skip: skip);
}
