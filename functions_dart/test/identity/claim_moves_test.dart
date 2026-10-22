import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/claim_moves.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/identity_invariants.dart';

const int _t0 = 1700000000000;
const ServerModeConfig _coexist = ServerModeConfig(mode: IdentityMode.coexist);

Checkpoint _crashAfter(String step) =>
    (reached) async => reached == step ? throw SimulatedCrash(step) : null;

void main() {
  final skip = emulatorSkipReason;

  group('moving a claim', () {
    late final RestDatabase db = openEmulatorDatabase();

    /// Pat (t1) has the alias "Pat" and Sam (t2) has "Sam".
    Future<void> reseed() async {
      await clearEmulatorDatabase(db);
      await db.ref('/').set({
        'AllTippers': {
          't1': {'name': 'Pat', 'authuid': 'uid1'},
          't2': {'name': 'Sam', 'authuid': 'uid2'},
        },
        'TipperPrivate': {
          't1': {'authuid': 'uid1', 'logon': 'pat@example.com'},
          't2': {'authuid': 'uid2', 'logon': 'sam@example.com'},
        },
        'AuthIndex': {'uid1': 't1', 'uid2': 't2'},
        'AliasIndex': {aliasIndexKey('Pat'): 't1', aliasIndexKey('Sam'): 't2'},
        'LogonIndex': {
          logonIndexKey('pat@example.com'): 't1',
          logonIndexKey('sam@example.com'): 't2',
        },
      });
    }

    setUp(reseed);

    /// A rename of t1, holding the tipper's lease as a handler would.
    Future<void> rename(
      String to, {
      String operationId = 'op-one',
      int at = _t0,
      Checkpoint? checkpoint,
    }) => withTipperLease(
      db,
      tipperId: 't1',
      operationId: operationId,
      nowMs: () => at,
      body: () => performClaimMove(
        db,
        tipperId: 't1',
        kind: ClaimKind.alias,
        toKey: aliasIndexKey(to),
        toValue: to,
        mode: _coexist,
        nowMs: at,
        checkpoint: checkpoint,
      ),
    );

    test(
      'renames: the new alias is claimed, the name written and the old claim released',
      () async {
        await rename('Patricia');
        final root = await readRoot(db);
        expect(root['AliasIndex'], {
          aliasIndexKey('Patricia'): 't1',
          aliasIndexKey('Sam'): 't2',
        });
        expect((root['AllTippers'] as Map)['t1']['name'], 'Patricia');
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test(
      'a spelling change that keeps the same key leaves the claim and updates the name',
      () async {
        await rename('PAT');
        final root = await readRoot(db);
        expect(root['AliasIndex'], containsPair(aliasIndexKey('Pat'), 't1'));
        expect((root['AllTippers'] as Map)['t1']['name'], 'PAT');
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test(
      'a name another tipper holds is refused and nothing changes',
      () async {
        final before = canonical(await readRoot(db));
        await expectLater(rename('s a m'), throwsA(isA<ClaimMoveConflict>()));
        expect(canonical(await readRoot(db)), before);
      },
      skip: skip,
    );

    for (final step in [
      'move:journalled',
      'move:claimed',
      'move:written',
      'move:released',
    ]) {
      test('a crash after $step, then a retry of the same rename', () async {
        await expectLater(
          rename('Patricia', checkpoint: _crashAfter(step)),
          throwsA(isA<SimulatedCrash>()),
        );
        expectIdentityConsistent(await readRoot(db), allowPending: true);

        // The retry is a new operation after the crashed one's lease has run out.
        await rename(
          'Patricia',
          operationId: 'op-two',
          at: _t0 + tipperLeaseTtl.inMilliseconds + 1,
        );
        final root = await readRoot(db);
        expect(root['AliasIndex'], {
          aliasIndexKey('Patricia'): 't1',
          aliasIndexKey('Sam'): 't2',
        });
        expect((root['AllTippers'] as Map)['t1']['name'], 'Patricia');
        expectIdentityConsistent(root);
      }, skip: skip);
    }

    test(
      'a crash AFTER the name changed, then a retry: the right old claim is still released',
      () async {
        // The reviewer's scenario: the name is already the new one, so it could not be used to find the old alias.
        await expectLater(
          rename('Patricia', checkpoint: _crashAfter('move:written')),
          throwsA(isA<SimulatedCrash>()),
        );
        expect(
          ((await readRoot(db))['AllTippers'] as Map)['t1']['name'],
          'Patricia',
        );
        expect(
          ((await readRoot(db))['AliasIndex'] as Map).keys,
          containsAll([aliasIndexKey('Pat'), aliasIndexKey('Patricia')]),
        );

        await rename(
          'Patricia',
          operationId: 'op-two',
          at: _t0 + tipperLeaseTtl.inMilliseconds + 1,
        );
        final root = await readRoot(db);
        expect(
          (root['AliasIndex'] as Map).containsKey(aliasIndexKey('Pat')),
          false,
          reason: 'the old claim, from the journal, was released',
        );
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test(
      'a crash, then a retry that asks for a different alias: the first move finishes, then the second',
      () async {
        await expectLater(
          rename('Patricia', checkpoint: _crashAfter('move:claimed')),
          throwsA(isA<SimulatedCrash>()),
        );

        // The second request must find the old claim AFTER finishing the first move, not before.
        await withTipperLease(
          db,
          tipperId: 't1',
          operationId: 'op-two',
          nowMs: () => _t0 + tipperLeaseTtl.inMilliseconds + 1,
          body: () async {
            await performClaimMove(
              db,
              tipperId: 't1',
              kind: ClaimKind.alias,
              toKey: aliasIndexKey('Trish'),
              toValue: 'Trish',
              mode: _coexist,
              nowMs: _t0 + tipperLeaseTtl.inMilliseconds + 1,
            );
          },
        );
        final root = await readRoot(db);
        expect(root['AliasIndex'], {
          aliasIndexKey('Trish'): 't1',
          aliasIndexKey('Sam'): 't2',
        }, reason: 'no claim leaked from the first, abandoned target');
        expect((root['AllTippers'] as Map)['t1']['name'], 'Trish');
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test(
      'two renames of one tipper at once are serialised: no leaked claim, in every one of many rounds',
      () async {
        var losersTold = 0;
        for (var round = 0; round < 12; round++) {
          await reseed();
          final outcomes = await Future.wait([
            rename(
              'Patricia',
              operationId: 'op-a',
            ).then<Object>((_) => 'done', onError: (Object e) => e),
            rename(
              'Trish',
              operationId: 'op-b',
            ).then<Object>((_) => 'done', onError: (Object e) => e),
          ]);
          expect(outcomes.where((o) => o == 'done'), isNotEmpty);
          for (final other in outcomes.where((o) => o != 'done')) {
            expect(
              other,
              isA<AbortedError>(),
              reason: 'the loser is told to try again',
            );
            losersTold += 1;
          }
          final root = await readRoot(db);
          final mine = (root['AliasIndex'] as Map).entries.where(
            (e) => e.value == 't1',
          );
          expect(
            mine,
            hasLength(1),
            reason: 'round $round: exactly one alias claim for the tipper',
          );
          expectIdentityConsistent(root);
        }
        expect(losersTold, greaterThan(0), reason: 'the two did collide');
      },
      skip: skip,
    );

    test(
      'a login address moves the same way, into the private record and the legacy public one',
      () async {
        await withTipperLease(
          db,
          tipperId: 't1',
          operationId: 'op-one',
          nowMs: () => _t0,
          body: () => performClaimMove(
            db,
            tipperId: 't1',
            kind: ClaimKind.logon,
            toKey: logonIndexKey('new@example.com'),
            toValue: 'new@example.com',
            mode: _coexist,
            nowMs: _t0,
          ),
        );
        final root = await readRoot(db);
        expect(
          (root['TipperPrivate'] as Map)['t1']['logon'],
          'new@example.com',
        );
        expect((root['AllTippers'] as Map)['t1']['logon'], 'new@example.com');
        expect(
          (root['LogonIndex'] as Map).containsKey(
            logonIndexKey('pat@example.com'),
          ),
          false,
        );
        expectIdentityConsistent(root);
      },
      skip: skip,
    );

    test('in the final mode the public record gets no login', () async {
      await withTipperLease(
        db,
        tipperId: 't1',
        operationId: 'op-one',
        nowMs: () => _t0,
        body: () => performClaimMove(
          db,
          tipperId: 't1',
          kind: ClaimKind.logon,
          toKey: logonIndexKey('new@example.com'),
          toValue: 'new@example.com',
          mode: const ServerModeConfig(mode: IdentityMode.finalShape),
          nowMs: _t0,
        ),
      );
      final root = await readRoot(db);
      expect((root['TipperPrivate'] as Map)['t1']['logon'], 'new@example.com');
      expect((root['AllTippers'] as Map)['t1'].containsKey('logon'), false);
    }, skip: skip);

    test('a tipper with no earlier claim just claims the new key', () async {
      await db.ref('/LogonIndex/${logonIndexKey('pat@example.com')}').remove();
      await withTipperLease(
        db,
        tipperId: 't1',
        operationId: 'op-one',
        nowMs: () => _t0,
        body: () => performClaimMove(
          db,
          tipperId: 't1',
          kind: ClaimKind.logon,
          toKey: logonIndexKey('pat@example.com'),
          toValue: 'pat@example.com',
          mode: _coexist,
          nowMs: _t0,
        ),
      );
      expectIdentityConsistent(await readRoot(db));
    }, skip: skip);
  });

  test(
    'ClaimMove survives its journal form, and a damaged journal is ignored, not trusted',
    () {
      const move = ClaimMove(
        kind: ClaimKind.alias,
        fromKey: 'a',
        toKey: 'b',
        toValue: 'B',
        startedAtMs: 5,
      );
      final copy = ClaimMove.tryParse(move.toJson())!;
      expect(
        (copy.kind, copy.fromKey, copy.toKey, copy.toValue, copy.startedAtMs),
        (ClaimKind.alias, 'a', 'b', 'B', 5),
      );
      for (final bad in [
        null,
        'x',
        <String, Object?>{},
        {'kind': 'alias'},
        {'kind': 'nope', 'toKey': 'b', 'toValue': 'B', 'startedAtMs': 1},
      ]) {
        expect(ClaimMove.tryParse(bad), isNull, reason: '$bad');
      }
    },
  );
}
