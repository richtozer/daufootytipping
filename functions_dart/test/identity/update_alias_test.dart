import 'dart:async';

import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/identity/update_alias.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:firebase_functions/firebase_functions.dart'
    show HttpResponseException;
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/identity_helpers.dart';
import '../support/identity_invariants.dart';

const int _t0 = 1700000000000;
const String _uidA = 'uidA00000000000000000000001';
const String _uidB = 'uidB00000000000000000000002';

void main() {
  final skip = emulatorSkipReason;

  group('updateTipperAlias', () {
    late final RestDatabase db = openEmulatorDatabase();

    /// Pat (t1, uidA) and Sam (t2, uidB), both linked and fully indexed.
    IdentitySeed baseline() => IdentitySeed()
      ..tipper(
        't1',
        name: 'Pat',
        authuid: _uidA,
        logon: 'pat@example.com',
        indexAccount: true,
      )
      ..tipper(
        't2',
        name: 'Sam',
        authuid: _uidB,
        logon: 'sam@example.com',
        indexAccount: true,
      );

    Future<void> seed([IdentitySeed? seed]) async {
      await clearEmulatorDatabase(db);
      await db.ref('/').set((seed ?? baseline()).data);
    }

    setUp(seed);

    Future<UpdateTipperAliasResult> rename(
      String uid,
      String alias, {
      IdentityMode mode = IdentityMode.coexist,
      int at = _t0,
      Checkpoint? checkpoint,
    }) => updateTipperAlias(
      database: db,
      caller: callerToken(uid, 'x@example.com'),
      request: UpdateTipperAliasRequest(alias: alias),
      admission: admissionFor(mode: mode),
      nowMs: () => at,
      checkpoint: checkpoint,
    );

    Future<void> refusedWithoutWriting(
      Future<Object?> Function() action,
      String reason,
    ) async {
      final before = canonical(await readRoot(db));
      await expectLater(action(), refusedAs(reason));
      expect(
        canonical(await readRoot(db)),
        before,
        reason: 'a refused request must not write',
      );
    }

    test(
      'renames: the new alias is claimed, the name written, the old claim released',
      () async {
        final result = await rename(_uidA, '  Patricia  ');
        expect((result.tipperId, result.alias), ('t1', 'Patricia'));
        final root = await readRoot(db);
        expect(root['AliasIndex'], {
          aliasIndexKey('Patricia'): 't1',
          aliasIndexKey('Sam'): 't2',
        });
        expect(rowAt(root, 'AllTippers', 't1')['name'], 'Patricia');
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test(
      'only the caller\'s own record is ever changed, found from the uid',
      () async {
        await rename(_uidB, 'Samuel');
        final root = await readRoot(db);
        expect(rowAt(root, 'AllTippers', 't1')['name'], 'Pat');
        expect(rowAt(root, 'AllTippers', 't2')['name'], 'Samuel');
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test('asking for the alias already held changes nothing at all', () async {
      final before = canonical(await readRoot(db));
      final result = await rename(_uidA, 'Pat');
      expect(result.alias, 'Pat');
      expect(canonical(await readRoot(db)), before);
    }, skip: skip);

    test(
      'a different case or spacing keeps the claim and only rewrites the name',
      () async {
        await rename(_uidA, 'P A T');
        final root = await readRoot(db);
        expect(rowAt(root, 'AllTippers', 't1')['name'], 'P A T');
        expect(root['AliasIndex'], containsPair(aliasIndexKey('Pat'), 't1'));
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test(
      'an account that is not linked is told so, and nothing is written',
      () async {
        await refusedWithoutWriting(
          () => rename('stranger00000000000000000001', 'Pat Two'),
          identityReasonNotLinked,
        );
      },
      skip: skip,
    );

    test(
      'an index entry its record does not agree with is refused for repair',
      () async {
        await db.ref('/TipperPrivate/t1/authuid').set('someone-else');
        await refusedWithoutWriting(
          () => rename(_uidA, 'Patricia'),
          identityReasonNeedsAudit,
        );
      },
      skip: skip,
    );

    test(
      'an alias that cannot be used is refused, with nothing written',
      () async {
        for (final alias in ['', '   ', '🏈🏈', 'x' * 65]) {
          await refusedWithoutWriting(
            () => rename(_uidA, alias),
            identityReasonInvalidAlias,
          );
        }
      },
      skip: skip,
    );

    test(
      'a taken alias is refused, however it is spelled, and nothing changes',
      () async {
        for (final alias in ['Sam', 'SAM', 's a m', 'Sam 🏈']) {
          await refusedWithoutWriting(
            () => rename(_uidA, alias),
            identityReasonAliasTaken,
          );
        }
      },
      skip: skip,
    );

    test('a record that lost its own claim can still rename', () async {
      await db.ref('/AliasIndex/${aliasIndexKey('Pat')}').remove();
      await rename(_uidA, 'Patricia');
      expectIdentityConsistent(await readRoot(db));
    }, skip: skip);

    test(
      'a claim that is not this tipper\'s is never released, and a stale one it cannot know about is left',
      () async {
        // t1 was renamed directly by a 1.4.x client to "Sam" (a duplicate of t2's alias) and left a stale claim "oldpat".
        await db.ref('/AllTippers/t1/name').set('Sam');
        await db.ref('/AliasIndex/oldpat').set('t1');
        await db.ref('/AliasIndex/${aliasIndexKey('Pat')}').remove();

        await rename(_uidA, 'Patricia');
        final aliases = (await readRoot(db))['AliasIndex'] as Map;
        expect(
          aliases[aliasIndexKey('Sam')],
          't2',
          reason: "Sam's claim is not t1's to release",
        );
        expect(aliases[aliasIndexKey('Patricia')], 't1');
        expect(
          aliases['oldpat'],
          't1',
          reason:
              'a stale claim is left for the audit, and does not fail the rename',
        );
      },
      skip: skip,
    );

    test(
      'the final mode writes the same public name and nothing private',
      () async {
        await rename(_uidA, 'Patricia', mode: IdentityMode.finalShape);
        final root = await readRoot(db);
        expect(rowAt(root, 'AllTippers', 't1')['name'], 'Patricia');
        expect(
          rowAt(root, 'TipperPrivate', 't1').keys.toSet(),
          containsAll(['authuid', 'logon']),
        );
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    group('a crash after any step, then a retry', () {
      for (final step in [
        'move:journalled',
        'move:claimed',
        'move:written',
        'move:released',
      ]) {
        test('after $step', () async {
          await expectLater(
            rename(_uidA, 'Patricia', checkpoint: crashAfter(step)),
            throwsA(isA<SimulatedCrash>()),
          );
          expectIdentityConsistent(await readRoot(db), allowPending: true);

          await expectLater(
            rename(_uidA, 'Patricia', at: _t0 + 1000),
            refusedAs(identityReasonBusy),
          );
          await rename(
            _uidA,
            'Patricia',
            at: _t0 + tipperLeaseTtl.inMilliseconds + 1,
          );

          final root = await readRoot(db);
          expect(root['AliasIndex'], {
            aliasIndexKey('Patricia'): 't1',
            aliasIndexKey('Sam'): 't2',
          });
          expectIdentityConsistent(root);
        }, skip: skip);
      }

      test(
        'after the name changed: the retry still releases the right old claim',
        () async {
          await expectLater(
            rename(_uidA, 'Patricia', checkpoint: crashAfter('move:written')),
            throwsA(isA<SimulatedCrash>()),
          );
          expect(
            rowAt(await readRoot(db), 'AllTippers', 't1')['name'],
            'Patricia',
          );

          await rename(
            _uidA,
            'Patricia',
            at: _t0 + tipperLeaseTtl.inMilliseconds + 1,
          );
          final aliases = (await readRoot(db))['AliasIndex'] as Map;
          expect(aliases.containsKey(aliasIndexKey('Pat')), false);
          expect(aliases[aliasIndexKey('Patricia')], 't1');
        },
        skip: skip,
      );

      test(
        'a retry asking for a different alias leaves no claim from the abandoned one',
        () async {
          await expectLater(
            rename(_uidA, 'Patricia', checkpoint: crashAfter('move:claimed')),
            throwsA(isA<SimulatedCrash>()),
          );
          await rename(
            _uidA,
            'Trish',
            at: _t0 + tipperLeaseTtl.inMilliseconds + 1,
          );
          final root = await readRoot(db);
          expect(root['AliasIndex'], {
            aliasIndexKey('Trish'): 't1',
            aliasIndexKey('Sam'): 't2',
          });
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test(
        'while one rename is half done, nobody else can take the alias it claimed',
        () async {
          await expectLater(
            rename(_uidA, 'Patricia', checkpoint: crashAfter('move:claimed')),
            throwsA(isA<SimulatedCrash>()),
          );
          await expectLater(
            rename(_uidB, 'Patricia'),
            refusedAs(identityReasonAliasTaken),
          );
        },
        skip: skip,
      );
    });

    group('concurrency', () {
      test(
        'two renames of one tipper at once: one is serialised behind the other, in every round',
        () async {
          var told = 0;
          for (var round = 0; round < 12; round++) {
            await seed();
            final outcomes = await Future.wait([
              rename(
                _uidA,
                'Patricia',
              ).then<Object>((r) => r, onError: (Object e) => e),
              rename(
                _uidA,
                'Trish',
              ).then<Object>((r) => r, onError: (Object e) => e),
            ]);
            expect(outcomes.whereType<UpdateTipperAliasResult>(), isNotEmpty);
            for (final other in outcomes.whereType<HttpResponseException>()) {
              expect(reasonOf(other), identityReasonBusy);
              told += 1;
            }
            final root = await readRoot(db);
            expect(
              (root['AliasIndex'] as Map).entries.where((e) => e.value == 't1'),
              hasLength(1),
              reason: 'round $round: exactly one alias claim for the tipper',
            );
            expectIdentityConsistent(root);
          }
          expect(told, greaterThan(0), reason: 'the two did collide');
        },
        skip: skip,
      );

      test(
        'two tippers choosing the same new alias at once: one wins, the other rolls back cleanly, in every round',
        () async {
          for (var round = 0; round < 12; round++) {
            await seed();
            final outcomes = await Future.wait([
              rename(
                _uidA,
                'Brand New',
              ).then<Object>((r) => r, onError: (Object e) => e),
              rename(
                _uidB,
                'brand  new',
              ).then<Object>((r) => r, onError: (Object e) => e),
            ]);
            expect(
              outcomes.whereType<UpdateTipperAliasResult>(),
              hasLength(1),
              reason: 'round $round',
            );
            expect(
              reasonOf(outcomes.whereType<HttpResponseException>().single),
              identityReasonAliasTaken,
            );
            final root = await readRoot(db);
            expect(
              (root['AliasIndex'] as Map).length,
              2,
              reason: 'one claim each, none leaked',
            );
            expect(
              root['ClaimMoves'],
              isNull,
              reason: 'the loser dropped its journal',
            );
            expectIdentityConsistent(root);
          }
        },
        skip: skip,
      );
    });
  });
}
