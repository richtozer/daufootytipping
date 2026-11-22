import 'dart:async';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/handler_deadline.dart';
import 'package:dart_functions/identity/leases.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/http_faults.dart';
import '../support/identity_helpers.dart';

const int _t0 = 1700000000000;

void main() {
  final skip = emulatorSkipReason;

  group('the per-tipper lease', () {
    late final RestDatabase db = openEmulatorDatabase();

    setUp(() async {
      await clearEmulatorDatabase(db);
      await db
          .ref('/')
          .set(
            (IdentitySeed()..tipper(
                  't1',
                  name: 'Pat',
                  authuid: 'uidA',
                  logon: 'pat@example.com',
                  indexAccount: true,
                ))
                .data,
          );
    });

    Future<Object?> lockOf() async =>
        (await db.ref('/IdentityLocks/t1').once()).value;

    Future<T> holding<T>(
      String op,
      Future<T> Function() body, {
      RestDatabase? on,
      int at = _t0,
      Duration settleGrace = const Duration(milliseconds: 300),
    }) => withTipperLease(
      on ?? db,
      tipperId: 't1',
      operationId: op,
      nowMs: () => at,
      body: body,
      settleGrace: settleGrace,
    );

    test(
      'is released at once when the work finished and its writes have settled',
      () async {
        await holding('op-a', () async => db.ref('/Scratch/x').set(1));
        expect(await lockOf(), isNull);
      },
      skip: skip,
    );

    test(
      'is released when the work failed but nothing is still being written',
      () async {
        await expectLater(
          holding('op-a', () async => throw StateError('boom')),
          throwsStateError,
        );
        expect(await lockOf(), isNull);
      },
      skip: skip,
    );

    test(
      'is left to expire after a simulated crash, as a real one would leave it',
      () async {
        await expectLater(
          holding('op-a', () async => throw const SimulatedCrash('x')),
          throwsA(isA<SimulatedCrash>()),
        );
        expect(await lockOf(), isNotNull);
      },
      skip: skip,
    );

    test('a second operation is refused while the first holds it', () async {
      final release = Completer<void>();
      final first = holding('op-a', () => release.future);
      await eventually(() async => await lockOf() != null);
      await expectLater(
        holding('op-b', () async {}),
        throwsA(isA<AbortedError>()),
      );
      release.complete();
      await first;
      await holding('op-b', () async {});
    }, skip: skip);

    test(
      'a write that timed out and is still on its way keeps the lease: the next operation must not start meanwhile',
      () async {
        late HoldRequests held;
        final gated = openEmulatorDatabase(
          requestTimeout: const Duration(milliseconds: 200),
          wrap: (inner) => held = HoldRequests(
            inner,
            (request) =>
                request.method == 'PUT' &&
                request.url.path.contains('/Scratch/'),
          ),
        );

        // The first operation's write times out, so its body throws and it exits...
        await expectLater(
          holding(
            'op-a',
            () async => gated.ref('/Scratch/x').set('late'),
            on: gated,
          ),
          throwsA(isA<UnavailableError>()),
        );
        // ...but the write has not reached the database and may still arrive.
        expect((await db.ref('/Scratch/x').once()).value, isNull);
        expect(
          await lockOf(),
          isNotNull,
          reason: 'the lease stays while its write is outstanding',
        );

        // So a second operation is refused rather than starting alongside it.
        await expectLater(
          holding('op-b', () async {}),
          throwsA(
            isA<AbortedError>().having(
              (e) => e.details?.first['reason'],
              'reason',
              identityReasonBusy,
            ),
          ),
        );

        // The write arrives (the risk was real), and then the lease is released in the background.
        held.open();
        await eventually(
          () async => (await db.ref('/Scratch/x').once()).value == 'late',
        );
        await eventually(() async => await lockOf() == null);
        await holding('op-b', () async {});
      },
      skip: skip,
    );

    group('a write that is still on its way when the lease would expire', () {
      final afterExpiry = _t0 + tipperLeaseTtl.inMilliseconds + 60 * 1000;

      test(
        'is not overtaken: takeover is refused past the lease\'s own expiry, and the late write cannot clobber the successor',
        () async {
          late HoldRequests held;
          final gated = openEmulatorDatabase(
            requestTimeout: const Duration(milliseconds: 200),
            wrap: (inner) => held = HoldRequests(
              inner,
              (request) =>
                  request.method == 'PUT' &&
                  request.url.path.contains('/Scratch/'),
            ),
          );

          // The first operation's write is held in the network; it gives up and exits.
          await expectLater(
            holding(
              'op-a',
              () async => gated.ref('/Scratch/x').set('late'),
              on: gated,
            ),
            throwsA(isA<UnavailableError>()),
          );

          // Time passes beyond the lease's own five minutes. The write has still not landed.
          expect((await db.ref('/Scratch/x').once()).value, isNull);
          await expectLater(
            holding('op-b', () async {}, at: afterExpiry),
            throwsA(
              isA<AbortedError>().having(
                (e) => e.details?.first['reason'],
                'reason',
                identityReasonBusy,
              ),
            ),
            reason:
                'an expired lease whose owner has an outstanding write is not taken over',
          );

          // The write lands. Only then is the lease released, and the successor can go.
          held.open();
          await eventually(
            () async => (await db.ref('/Scratch/x').once()).value == 'late',
          );
          await eventually(() async => await lockOf() == null);
          await holding(
            'op-b',
            () async => db.ref('/Scratch/x').set('successor'),
            at: afterExpiry,
          );
          expect(
            (await db.ref('/Scratch/x').once()).value,
            'successor',
            reason:
                'the late write came first and did not overwrite the successor',
          );
        },
        skip: skip,
      );

      test(
        'is held for the hold period, not just the lease\'s own ttl',
        () async {
          late HoldRequests held;
          final gated = openEmulatorDatabase(
            requestTimeout: const Duration(milliseconds: 200),
            wrap: (inner) => held = HoldRequests(
              inner,
              (request) =>
                  request.method == 'PUT' &&
                  request.url.path.contains('/Scratch/'),
            ),
          );
          await expectLater(
            holding(
              'op-a',
              () async => gated.ref('/Scratch/x').set('late'),
              on: gated,
            ),
            throwsA(isA<UnavailableError>()),
          );

          final lease = Lease.tryParse(await lockOf());
          expect(lease, isNotNull);
          expect(
            lease!.expiresAtMs,
            _t0 + unresolvedWriteHold.inMilliseconds,
            reason: 'extended to the hold, well past its own five minutes',
          );
          held.open();
          await eventually(() async => await lockOf() == null);
        },
        skip: skip,
      );
    });

    test(
      'a write that was on its way and then loses its response does not release the lease either',
      () async {
        late HoldRequests held;
        final gated = openEmulatorDatabase(
          requestTimeout: const Duration(milliseconds: 200),
          wrap: (inner) => held = HoldRequests(
            LoseResponses(
              inner,
              (request) =>
                  request.method == 'PUT' &&
                  request.url.path.contains('/Scratch/'),
            ),
            (request) =>
                request.method == 'PUT' &&
                request.url.path.contains('/Scratch/'),
          ),
        );
        await expectLater(
          holding(
            'op-a',
            () async => gated.ref('/Scratch/x').set('late'),
            on: gated,
          ),
          throwsA(isA<UnavailableError>()),
        );

        held.open();
        await eventually(
          () async => (await db.ref('/Scratch/x').once()).value == 'late',
        );
        await eventually(() async => gated.writes.pendingCount == 0);
        // Give a background release time to happen, if it is going to.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          await lockOf(),
          isNotNull,
          reason: 'it finished, but nobody knows what happened to it',
        );
        await expectLater(
          holding('op-b', () async {}),
          throwsA(isA<AbortedError>()),
        );
      },
      skip: skip,
    );

    test(
      'a write whose response was lost keeps the lease until it expires, then the tipper can be taken over',
      () async {
        final lossy = openEmulatorDatabase(
          wrap: (inner) => LoseResponses(
            inner,
            (request) =>
                request.method == 'PUT' &&
                request.url.path.contains('/Scratch/'),
          ),
        );
        await expectLater(
          holding(
            'op-a',
            () async => lossy.ref('/Scratch/x').set('applied'),
            on: lossy,
          ),
          throwsA(anything),
        );
        expect(
          (await db.ref('/Scratch/x').once()).value,
          'applied',
          reason: 'it was applied although the caller was told it failed',
        );
        expect(
          await lockOf(),
          isNotNull,
          reason: 'not released: nobody knows whether it was applied',
        );
        await expectLater(
          holding('op-b', () async {}),
          throwsA(isA<AbortedError>()),
        );

        // Once the lease has run out, the successor takes over.
        await holding(
          'op-b',
          () async {},
          at: _t0 + tipperLeaseTtl.inMilliseconds + 1000,
        );
        expect(await lockOf(), isNull);
      },
      skip: skip,
    );

    group('the write fence', () {
      test(
        'a worker paused past its lease cannot write when it resumes, and cannot disturb its successor',
        () async {
          // Each request has a database handle of its own, and so does each of
          // these two operations.
          final dbA = openEmulatorDatabase();
          var now = _t0;
          final paused = Completer<void>();
          final reached = Completer<void>();

          Future<void> operationA() => withTipperLease(
            dbA,
            tipperId: 't1',
            operationId: 'op-a',
            nowMs: () => now,
            settleGrace: const Duration(milliseconds: 300),
            body: () async {
              await dbA.ref('/Scratch/x').set('a-before-the-pause');
              reached.complete();
              await paused.future; // the instance is frozen here
              await dbA.ref('/Scratch/x').set('a-after-the-pause');
            },
          );

          final a = operationA();
          await reached.future;

          // The pause outlasts the lease. Another operation takes it over and finishes.
          now = _t0 + tipperLeaseTtl.inMilliseconds + 60 * 1000;
          await withTipperLease(
            db,
            tipperId: 't1',
            operationId: 'op-b',
            nowMs: () => now,
            body: () async => db.ref('/Scratch/x').set('b'),
          );
          expect((await db.ref('/Scratch/x').once()).value, 'b');

          // The paused worker wakes up and carries on with its next write.
          paused.complete();
          await expectLater(a, throwsA(isA<UnavailableError>()));
          expect(
            (await db.ref('/Scratch/x').once()).value,
            'b',
            reason: 'its late write was refused before it was sent',
          );
          expect(await lockOf(), isNull);
        },
        skip: skip,
      );

      test(
        'closes before the lease expires, not at the moment it does',
        () async {
          final dbA = openEmulatorDatabase();
          var now = _t0;
          final paused = Completer<void>();
          final reached = Completer<void>();
          final a = withTipperLease(
            dbA,
            tipperId: 't1',
            operationId: 'op-a',
            nowMs: () => now,
            body: () async {
              reached.complete();
              await paused.future;
              await dbA.ref('/Scratch/x').set('too-late');
            },
          );
          await reached.future;

          // Still inside the lease, but inside the margin: nobody has taken over,
          // and the worker is already refused.
          now = _t0 + tipperLeaseTtl.inMilliseconds - 1000;
          paused.complete();
          await expectLater(a, throwsA(isA<UnavailableError>()));
          expect((await db.ref('/Scratch/x').once()).value, isNull);
        },
        skip: skip,
      );

      test(
        'does not stop a worker that is inside its window, and is lifted for the release afterwards',
        () async {
          final dbA = openEmulatorDatabase();
          var now = _t0;
          await withTipperLease(
            dbA,
            tipperId: 't1',
            operationId: 'op-a',
            nowMs: () => now,
            body: () async {
              now = _t0 + 60 * 1000;
              await dbA.ref('/Scratch/x').set('fine');
            },
          );
          expect((await db.ref('/Scratch/x').once()).value, 'fine');
          expect(await lockOf(), isNull, reason: 'released');
          expect(
            dbA.writes.fence,
            isNull,
            reason: 'the fence is only up while the body runs',
          );
        },
        skip: skip,
      );
    });
  });

  group('the lease timings', () {
    test(
      'leave room: deadline + one request + the margin fit inside the ttl',
      () {
        expect(
          handlerSoftDeadline + defaultRestRequestTimeout + leaseWriteMargin,
          lessThan(tipperLeaseTtl),
        );
      },
    );

    test(
      'the margin covers a last write timing out, the settle wait, and the hold being written',
      () {
        expect(
          leaseWriteMargin,
          greaterThanOrEqualTo(
            defaultRestRequestTimeout +
                leaseSettleGrace +
                const Duration(seconds: 5),
          ),
        );
      },
    );

    test('the hold is longer than the lease it extends', () {
      expect(unresolvedWriteHold, greaterThan(tipperLeaseTtl));
    });
  });
}
