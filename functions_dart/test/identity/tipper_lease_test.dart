import 'dart:async';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/faults.dart';
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
  });
}
