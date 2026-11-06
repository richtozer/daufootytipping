import 'dart:async';

import 'package:dart_functions/identity/device_tokens.dart';
import 'package:dart_functions/identity/faults.dart';
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
const String _uidC = 'uidC00000000000000000000003';
const String _token = 'dXYZ:APA91bExample-0001_aaaaaaaaaaaaaaaa';
const String _other = 'dXYZ:APA91bExample-0002_bbbbbbbbbbbbbbbb';
const String _legacy = 'dXYZ:APA91bLegacy-0003_cccccccccccccccc';

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

void main() {
  final skip = emulatorSkipReason;

  group('device tokens', () {
    late final RestDatabase db = openEmulatorDatabase();

    /// Three linked tippers; t3 holds a token written directly by a 1.4.x client,
    /// so the ownership index has never heard of it.
    IdentitySeed baseline() {
      final seed = IdentitySeed()
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
        )
        ..tipper(
          't3',
          name: 'Lou',
          authuid: _uidC,
          logon: 'lou@example.com',
          indexAccount: true,
        );
      seed.data['AllTippersTokens'] = {
        't3': {_legacy: '2026-03-01T00:00:00.000'},
      };
      return seed;
    }

    Future<void> seed([IdentitySeed? seed]) async {
      await clearEmulatorDatabase(db);
      await db.ref('/').set((seed ?? baseline()).data);
    }

    setUp(seed);

    Future<RegisterDeviceTokenResult> register(
      String uid,
      String token, {
      int at = _t0,
      Checkpoint? checkpoint,
    }) => registerDeviceToken(
      database: db,
      caller: callerToken(uid, 'x@example.com'),
      request: DeviceTokenRequest(token: token),
      nowMs: () => at,
      checkpoint: checkpoint,
    );

    Future<UnregisterDeviceTokenResult> unregister(
      String uid,
      String token, {
      Checkpoint? checkpoint,
    }) => unregisterDeviceToken(
      database: db,
      caller: callerToken(uid, 'x@example.com'),
      request: DeviceTokenRequest(token: token),
      checkpoint: checkpoint,
    );

    Map<String, Object?> tokensOf(Map<String, Object?> root, String tipperId) {
      final value = (root['AllTippersTokens'] as Map?)?[tipperId];
      return value is Map
          ? Map<String, Object?>.from(value)
          : <String, Object?>{};
    }

    Object? ownerOf(Map<String, Object?> root, String token) =>
        (root['TokenOwners'] as Map?)?[token];

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

    group('registering', () {
      test(
        'writes the caller\'s entry and records the caller as the owner',
        () async {
          final result = await register(_uidA, _token, at: _t0 + 5);
          expect(result.tipperId, 't1');
          final root = await readRoot(db);
          expect(tokensOf(root, 't1'), {_token: _iso(_t0 + 5)});
          expect(ownerOf(root, _token), 't1');
          expectTokensConsistent(root);
        },
        skip: skip,
      );

      test(
        'moves the token from the tipper that had it, and from a holder the index never knew about',
        () async {
          await register(_uidA, _token);
          await register(_uidB, _token);
          var root = await readRoot(db);
          expect(tokensOf(root, 't1'), isEmpty);
          expect(tokensOf(root, 't2').keys, [_token]);
          expect(ownerOf(root, _token), 't2');

          await register(_uidA, _legacy); // t3 wrote this one directly
          root = await readRoot(db);
          expect(
            tokensOf(root, 't3'),
            isEmpty,
            reason: 'the unindexed legacy holder is cleared too',
          );
          expect(tokensOf(root, 't1').keys, [_legacy]);
          expectTokensConsistent(root);
        },
        skip: skip,
      );

      test(
        'registering again refreshes the time and leaves one entry',
        () async {
          await register(_uidA, _token, at: _t0);
          await register(_uidA, _token, at: _t0 + 9000);
          final root = await readRoot(db);
          expect(tokensOf(root, 't1'), {_token: _iso(_t0 + 9000)});
          expectTokensConsistent(root);
        },
        skip: skip,
      );

      test('the caller\'s other tokens are left alone', () async {
        await register(_uidA, _token);
        await register(_uidA, _other);
        expect(tokensOf(await readRoot(db), 't1').keys.toSet(), {
          _token,
          _other,
        });
      }, skip: skip);

      test(
        'a token that cannot be a database key is refused, with nothing written',
        () async {
          for (final bad in [
            '',
            'a.b',
            'a/b',
            'a#b',
            r'a$b',
            'a[b]',
            'a]b',
            'tab\there',
            'x' * (maxDeviceTokenLength + 1),
          ]) {
            await refusedWithoutWriting(
              () => register(_uidA, bad),
              identityReasonInvalidToken,
            );
          }
        },
        skip: skip,
      );

      test(
        'an account that is not linked is told so, and nothing is written',
        () async {
          await refusedWithoutWriting(
            () => register('stranger00000000000000000001', _token),
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
            () => register(_uidA, _token),
            identityReasonNeedsAudit,
          );
        },
        skip: skip,
      );

      test(
        'ACCEPTED LIMITATION: knowing another tipper\'s token is enough to take it',
        () async {
          // Possession of a push token does not prove control of the device. This documents the behaviour
          // (the token moves to the caller, as it does today when a 1.4.x client writes it directly).
          await register(_uidA, _token);
          await register(_uidB, _token);
          final root = await readRoot(db);
          expect(tokensOf(root, 't1'), isEmpty);
          expect(ownerOf(root, _token), 't2');
        },
        skip: skip,
      );
    });

    group('unregistering', () {
      test('removes the caller\'s entry and gives up the ownership', () async {
        await register(_uidA, _token);
        final result = await unregister(_uidA, _token);
        expect(result.removed, true);
        final root = await readRoot(db);
        expect(tokensOf(root, 't1'), isEmpty);
        expect(ownerOf(root, _token), isNull);
        expectTokensConsistent(root);
      }, skip: skip);

      test(
        'removing a token the tipper does not hold is not an error',
        () async {
          final result = await unregister(_uidA, _token);
          expect(result.removed, false);
        },
        skip: skip,
      );

      test('removes an entry the index never knew about', () async {
        final result = await unregister(_uidC, _legacy);
        expect(result.removed, true);
        expect(tokensOf(await readRoot(db), 't3'), isEmpty);
      }, skip: skip);

      test('only ever touches the caller\'s own entry', () async {
        await register(_uidA, _token);
        final result = await unregister(_uidB, _token);
        expect(result.removed, false);
        final root = await readRoot(db);
        expect(tokensOf(root, 't1').keys, [_token]);
        expect(
          ownerOf(root, _token),
          't1',
          reason: 'only the owner can give up the ownership',
        );
      }, skip: skip);

      test(
        'a DELAYED unregister from a former owner leaves the later owner\'s registration intact',
        () async {
          await register(_uidA, _token);
          await register(_uidB, _token); // B took the token over
          final late = await unregister(
            _uidA,
            _token,
          ); // A's unregister arrives afterwards
          expect(late.removed, false, reason: 'A no longer held it');
          final root = await readRoot(db);
          expect(tokensOf(root, 't2').keys, [_token]);
          expect(ownerOf(root, _token), 't2');
          expectTokensConsistent(root);
        },
        skip: skip,
      );

      test(
        'invalid tokens and unlinked accounts are refused here too',
        () async {
          await refusedWithoutWriting(
            () => unregister(_uidA, 'a.b'),
            identityReasonInvalidToken,
          );
          await refusedWithoutWriting(
            () => unregister('stranger00000000000000000001', _token),
            identityReasonNotLinked,
          );
        },
        skip: skip,
      );
    });

    group('two callers at once', () {
      test(
        'registering the same absent token: exactly one holder and a matching owner, in every round',
        () async {
          var losersTold = 0;
          for (var round = 0; round < 15; round++) {
            await seed();
            final outcomes = await Future.wait([
              register(
                _uidA,
                _token,
              ).then<Object>((r) => r, onError: (Object e) => e),
              register(
                _uidB,
                _token,
              ).then<Object>((r) => r, onError: (Object e) => e),
            ]);
            expect(
              outcomes.whereType<HttpResponseException>(),
              isEmpty,
              reason: 'round $round: both calls succeed',
            );
            final root = await readRoot(db);
            final holders = [
              for (final id in ['t1', 't2', 't3'])
                if (tokensOf(root, id).containsKey(_token)) id,
            ];
            expect(holders, hasLength(1), reason: 'round $round: one holder');
            expect(
              ownerOf(root, _token),
              holders.single,
              reason: 'round $round: the owner is the holder',
            );
            expectTokensConsistent(root);
            losersTold += 1;
          }
          expect(losersTold, 15);
        },
        skip: skip,
      );

      test(
        'five callers at once for one token, and the unindexed legacy holder, end with one holder',
        () async {
          final uids = [_uidA, _uidB, _uidC];
          for (var round = 0; round < 10; round++) {
            await seed();
            await Future.wait([
              for (final uid in uids) register(uid, _legacy),
              for (final uid in uids) register(uid, _legacy),
            ]);
            final root = await readRoot(db);
            final holders = [
              for (final id in ['t1', 't2', 't3'])
                if (tokensOf(root, id).containsKey(_legacy)) id,
            ];
            expect(holders, hasLength(1), reason: 'round $round');
            expect(ownerOf(root, _legacy), holders.single);
            expectTokensConsistent(root);
          }
        },
        skip: skip,
      );

      test(
        'a register racing an unregister of the same token ends consistent',
        () async {
          for (var round = 0; round < 10; round++) {
            await seed();
            await register(_uidA, _token);
            await Future.wait([
              register(_uidB, _token),
              unregister(_uidA, _token),
            ]);
            expectTokensConsistent(await readRoot(db));
          }
        },
        skip: skip,
      );
    });

    group('a crash after any step, then a retry', () {
      for (final step in [
        'token:owner',
        'token:others-removed',
        'token:entry',
      ]) {
        test('after $step', () async {
          await register(
            _uidB,
            _token,
          ); // B holds it first, so there is something to clear
          await expectLater(
            register(_uidA, _token, checkpoint: crashAfter(step)),
            throwsA(isA<SimulatedCrash>()),
          );
          expectTokensConsistent(await readRoot(db), allowPending: true);

          await register(_uidA, _token);
          final root = await readRoot(db);
          expect(tokensOf(root, 't1').keys, [_token]);
          expect(tokensOf(root, 't2'), isEmpty);
          expect(ownerOf(root, _token), 't1');
          expectTokensConsistent(root);
        }, skip: skip);
      }

      test('a crash while unregistering, then a retry', () async {
        await register(_uidA, _token);
        await expectLater(
          unregister(_uidA, _token, checkpoint: crashAfter('untoken:released')),
          throwsA(isA<SimulatedCrash>()),
        );
        final result = await unregister(_uidA, _token);
        expect(result.removed, true);
        final root = await readRoot(db);
        expect(tokensOf(root, 't1'), isEmpty);
        expect(ownerOf(root, _token), isNull);
      }, skip: skip);
    });
  });
}
