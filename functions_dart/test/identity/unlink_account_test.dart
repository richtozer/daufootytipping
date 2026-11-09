import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/link_or_create.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/identity/unlink_account.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/identity_helpers.dart';
import '../support/identity_invariants.dart';

const int _t0 = 1700000000000;
const String _uidA = 'uidA00000000000000000000001';
const String _uidB = 'uidB00000000000000000000002';
const String _uidNew = 'uidN00000000000000000000009';
const String _uidOther = 'uidX00000000000000000000008';

void main() {
  final skip = emulatorSkipReason;

  group('unlinkMyAccount', () {
    late final RestDatabase db = openEmulatorDatabase();

    /// Pat (t1, uidA) and Sam (t2, uidB), both linked, with a tip and a token on
    /// Pat's record: the things that must survive being unlinked.
    IdentitySeed baseline() {
      final seed = IdentitySeed()
        ..tipper(
          't1',
          name: 'Pat',
          authuid: _uidA,
          logon: 'pat@example.com',
          email: 'pat@example.com',
          indexAccount: true,
        )
        ..tipper(
          't2',
          name: 'Sam',
          authuid: _uidB,
          logon: 'sam@example.com',
          email: 'sam@example.com',
          indexAccount: true,
        );
      seed.data['AllTips'] = <String, Object?>{
        'c1': <String, Object?>{
          't1': <String, Object?>{
            'g1': <String, Object?>{'r': 'a', 't': 1},
          },
        },
      };
      seed.data['AllTippersTokens'] = <String, Object?>{
        't1': <String, Object?>{'tokenA': '2026-03-01T00:00:00.000'},
      };
      return seed;
    }

    Future<void> seed([IdentitySeed? seed]) async {
      await clearEmulatorDatabase(db);
      await db.ref('/').set((seed ?? baseline()).data);
    }

    setUp(seed);

    Future<UnlinkMyAccountResult> unlink(
      String uid, {
      Checkpoint? checkpoint,
      int at = _t0,
      IdentityMode mode = IdentityMode.coexist,
    }) => unlinkMyAccount(
      database: db,
      caller: callerToken(uid, 'x@example.com'),
      admission: admissionFor(mode: mode),
      nowMs: () => at,
      checkpoint: checkpoint,
    );

    Future<LinkOrCreateTipperResult> signUp(String uid, String email) =>
        linkOrCreateTipper(
          database: db,
          caller: callerToken(uid, email),
          request: const LinkOrCreateTipperRequest(),
          admission: admissionFor(),
          nowMs: () => _t0,
        );

    test(
      'detaches the account and keeps the record, its claims, tips and tokens',
      () async {
        final result = await unlink(_uidA);
        expect(result.unlinked, true);

        final root = await readRoot(db);
        expect((root['AuthIndex'] as Map).containsKey(_uidA), false);
        expect(
          (root['AuthIndex'] as Map)[_uidB],
          't2',
          reason: 'Sam is untouched',
        );

        final private = rowAt(root, 'TipperPrivate', 't1');
        expect(
          private.containsKey('authuid'),
          false,
          reason:
              'removed, not blanked: only a missing authuid is free to link',
        );
        expect(
          rowAt(root, 'AllTippers', 't1')['authuid'],
          '',
          reason:
              'blanked, never removed: the 1.4.x client reads it as a string',
        );

        expect(rowAt(root, 'AllTippers', 't1')['name'], 'Pat');
        expect(private['logon'], 'pat@example.com');
        expect(root['AliasIndex'], containsPair('pat', 't1'));
        expect((root['LogonIndex'] as Map).values, contains('t1'));
        expect(((root['AllTips'] as Map)['c1'] as Map)['t1'], isNotNull);
        expect((root['AllTippersTokens'] as Map)['t1'], isNotNull);
        expect(rowAt(root, 'TipperPrivate', 't2')['authuid'], _uidB);
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test(
      'the same person can sign up again with a new account and gets the same record back',
      () async {
        await unlink(_uidA);

        final result = await signUp(_uidNew, 'pat@example.com');
        expect(result.tipperId, 't1');
        expect(result.outcome, LinkOutcome.linked);

        final root = await readRoot(db);
        expect((root['AuthIndex'] as Map)[_uidNew], 't1');
        expect(rowAt(root, 'TipperPrivate', 't1')['authuid'], _uidNew);
        expect(rowAt(root, 'AllTippers', 't1')['authuid'], _uidNew);
        expect(rowAt(root, 'AllTippers', 't1')['name'], 'Pat');
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test(
      'without it, signing up again is refused: the problem this callable exists to solve',
      () async {
        // Pat deletes only the sign-in account; the record keeps pointing at it.
        await expectLater(
          signUp(_uidNew, 'pat@example.com'),
          refusedAs('claimed'),
        );
      },
      skip: skip,
    );

    test(
      'a second call changes nothing and says nothing was attached',
      () async {
        await unlink(_uidA);
        final before = canonical(await readRoot(db));
        final again = await unlink(_uidA);
        expect(again.unlinked, false);
        expect(canonical(await readRoot(db)), before);
      },
      skip: skip,
    );

    test('an account that was never linked writes nothing', () async {
      final before = canonical(await readRoot(db));
      final result = await unlink(_uidNew);
      expect(result.unlinked, false);
      expect(canonical(await readRoot(db)), before);
    }, skip: skip);

    test(
      'only what names this account is changed: someone else\'s link is never touched',
      () async {
        // Pat's index entry is still there, but the record has since been linked to another account.
        await seed(
          IdentitySeed()
            ..tipper(
              't1',
              name: 'Pat',
              authuid: _uidOther,
              logon: 'pat@example.com',
            )
            ..tipper(
              't2',
              name: 'Sam',
              authuid: _uidB,
              logon: 'sam@example.com',
              indexAccount: true,
            ),
        );
        await db.ref('AuthIndex/$_uidA').set('t1');

        final result = await unlink(_uidA);
        expect(result.unlinked, true, reason: 'the index entry was Pat\'s own');

        final root = await readRoot(db);
        expect((root['AuthIndex'] as Map).containsKey(_uidA), false);
        expect(rowAt(root, 'TipperPrivate', 't1')['authuid'], _uidOther);
        expect(rowAt(root, 'AllTippers', 't1')['authuid'], _uidOther);
      },
      skip: skip,
    );

    test(
      'the 1.5 shape, where the public record has no authuid, does not grow one',
      () async {
        await seed(
          IdentitySeed()..tipper(
            't1',
            name: 'Pat',
            authuid: _uidA,
            logon: 'pat@example.com',
            indexAccount: true,
            legacyPublic: false,
          ),
        );
        await unlink(_uidA, mode: IdentityMode.finalShape);
        final root = await readRoot(db);
        expect(rowAt(root, 'AllTippers', 't1').containsKey('authuid'), false);
        expect(
          rowAt(root, 'TipperPrivate', 't1').containsKey('authuid'),
          false,
        );
      },
      skip: skip,
    );

    group('a call that was cut short is finished by a retry', () {
      // A retry cannot find the record by the index any more once step 1 is done,
      // so it must find it from the record itself.
      test(
        'the index entry already gone, the record still naming the account',
        () async {
          await seed(
            IdentitySeed()..tipper(
              't1',
              name: 'Pat',
              authuid: _uidA,
              logon: 'pat@example.com',
            ), // not indexed
          );
          final result = await unlink(_uidA);
          expect(result.unlinked, true);
          final root = await readRoot(db);
          expect(
            rowAt(root, 'TipperPrivate', 't1').containsKey('authuid'),
            false,
          );
          expect(rowAt(root, 'AllTippers', 't1')['authuid'], '');
        },
        skip: skip,
      );

      test('only the public copy still naming the account', () async {
        await unlink(_uidA);
        await db
            .ref('AllTippers/t1/authuid')
            .set(_uidA); // as if step 3 had not run
        final result = await unlink(_uidA);
        expect(result.unlinked, true);
        expect(rowAt(await readRoot(db), 'AllTippers', 't1')['authuid'], '');
      }, skip: skip);

      for (final step in <String>['unlink:index', 'unlink:private']) {
        test('crashed after $step: the retry completes it', () async {
          await expectLater(
            unlink(_uidA, checkpoint: crashAfter(step)),
            throwsA(isA<SimulatedCrash>()),
          );
          // The crash left the lease in place; the retry comes after it has run out.
          final retryAt = _t0 + tipperLeaseTtl.inMilliseconds + 1000;
          final result = await unlink(_uidA, at: retryAt);
          expect(result.unlinked, true);

          final root = await readRoot(db);
          expect((root['AuthIndex'] as Map).containsKey(_uidA), false);
          expect(
            rowAt(root, 'TipperPrivate', 't1').containsKey('authuid'),
            false,
          );
          expect(rowAt(root, 'AllTippers', 't1')['authuid'], '');
          expect(root['IdentityLocks'], isNull);
          expectIdentityConsistent(root);
        }, skip: skip);
      }
    });

    test(
      'a stale duplicate record naming the same account is detached too',
      () async {
        final seedData = baseline();
        seedData.tipper(
          't9',
          name: 'Pat old',
          authuid: _uidA,
          claimAlias: false,
          claimLogon: false,
        );
        await seed(seedData);
        await unlink(_uidA);
        final root = await readRoot(db);
        for (final id in ['t1', 't9']) {
          expect(
            rowAt(root, 'TipperPrivate', id).containsKey('authuid'),
            false,
            reason: id,
          );
          expect(rowAt(root, 'AllTippers', id)['authuid'], '', reason: id);
        }
      },
      skip: skip,
    );
  });
}
