import 'package:dart_functions/identity/leases.dart';
import 'package:dart_functions/identity/operation_id.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';

void main() {
  group('Lease value', () {
    test('round trips owner and expiry', () {
      const lease = Lease(owner: 'admin-1', expiresAtMs: 1700000000000);
      final parsed = Lease.tryParse(lease.encode());

      expect(parsed?.owner, 'admin-1');
      expect(parsed?.expiresAtMs, 1700000000000);
    });

    test('rejects values that are not leases', () {
      for (final raw in <Object?>[
        null,
        42,
        '',
        'no-separator',
        '|123',
        'owner|',
        'owner|abc',
        {'owner': 'x'},
      ]) {
        expect(Lease.tryParse(raw), isNull, reason: '$raw');
      }
    });

    test('is live up to, but not including, its expiry instant', () {
      const lease = Lease(owner: 'a', expiresAtMs: 1000);
      expect(lease.isExpiredAt(999), isFalse);
      expect(lease.isExpiredAt(1000), isTrue);
    });
  });

  group('identity leases against the emulator', skip: emulatorSkipReason, () {
    late final database = openEmulatorDatabase();
    const ttl = Duration(minutes: 5);

    setUp(() async {
      await clearEmulatorDatabase(database);
    });

    test(
      'an empty lease is acquired, and a live one is refused to others',
      () async {
        final lease = database.ref('/IdentityLocks/t1');

        expect(
          await acquireLease(lease, owner: 'admin-1', nowMs: 1000, ttl: ttl),
          LeaseOutcome.acquired,
        );
        expect(
          await acquireLease(lease, owner: 'admin-2', nowMs: 2000, ttl: ttl),
          LeaseOutcome.heldByOther,
        );
        expect(
          (await lease.once()).value,
          Lease(
            owner: 'admin-1',
            expiresAtMs: 1000 + ttl.inMilliseconds,
          ).encode(),
        );
      },
    );

    test('the owner renews and the expiry moves', () async {
      final lease = database.ref('/IdentityLocks/t1');
      await acquireLease(lease, owner: 'admin-1', nowMs: 1000, ttl: ttl);

      expect(
        await acquireLease(lease, owner: 'admin-1', nowMs: 5000, ttl: ttl),
        LeaseOutcome.renewed,
      );
      expect(
        Lease.tryParse((await lease.once()).value)?.expiresAtMs,
        5000 + ttl.inMilliseconds,
      );
    });

    test('an expired lease is taken over by the next owner', () async {
      final lease = database.ref('/IdentityLocks/t1');
      await acquireLease(lease, owner: 'admin-1', nowMs: 1000, ttl: ttl);
      final afterExpiry = 1000 + ttl.inMilliseconds;

      expect(
        await acquireLease(
          lease,
          owner: 'admin-2',
          nowMs: afterExpiry,
          ttl: ttl,
        ),
        LeaseOutcome.tookOverExpired,
      );
      expect(Lease.tryParse((await lease.once()).value)?.owner, 'admin-2');
    });

    test(
      'of 10 owners finding the same stale lease exactly one takes over',
      () async {
        final lease = database.ref('/IdentityLocks/t1');
        await acquireLease(lease, owner: 'old-admin', nowMs: 1000, ttl: ttl);
        final later = 1000 + ttl.inMilliseconds + 1;

        final outcomes = await Future.wait(
          List.generate(
            10,
            (index) => acquireLease(
              lease,
              owner: 'admin-$index',
              nowMs: later,
              ttl: ttl,
            ),
          ),
        );

        expect(
          outcomes.where((outcome) => outcome == LeaseOutcome.tookOverExpired),
          hasLength(1),
        );
        expect(
          outcomes.where((outcome) => outcome == LeaseOutcome.heldByOther),
          hasLength(9),
        );
      },
    );

    test('a stored value that is not a lease is never replaced', () async {
      final lease = database.ref('/IdentityLocks/t1');
      await lease.set('corrupt');

      expect(
        await acquireLease(lease, owner: 'admin-1', nowMs: 1000, ttl: ttl),
        LeaseOutcome.heldByOther,
      );
      expect((await lease.once()).value, 'corrupt');
    });

    test('only the owner can release', () async {
      final lease = database.ref('/IdentityLocks/t1');
      await acquireLease(lease, owner: 'admin-1', nowMs: 1000, ttl: ttl);

      expect(await releaseLease(lease, owner: 'admin-2'), isFalse);
      expect((await lease.once()).value, isNotNull);
      expect(await releaseLease(lease, owner: 'admin-1'), isTrue);
      expect((await lease.once()).value, isNull);
    });

    group('a worker that was taken over', () {
      test('holdsLease is true only for the live holder', () async {
        final lease = database.ref('/IdentityLocks/t1');
        await acquireLease(lease, owner: 'op-1', nowMs: 1000, ttl: ttl);

        expect(await holdsLease(lease, owner: 'op-1', nowMs: 2000), isTrue);
        expect(await holdsLease(lease, owner: 'op-2', nowMs: 2000), isFalse);
        expect(
          await holdsLease(
            lease,
            owner: 'op-1',
            nowMs: 1000 + ttl.inMilliseconds,
          ),
          isFalse,
          reason: 'expired',
        );
      });

      test(
        'the stale holder learns it lost the lease and cannot regain it',
        () async {
          final lease = database.ref('/IdentityLocks/t1');
          await acquireLease(lease, owner: 'stale-op', nowMs: 1000, ttl: ttl);
          final later = 1000 + ttl.inMilliseconds + 1;
          expect(
            await acquireLease(lease, owner: 'new-op', nowMs: later, ttl: ttl),
            LeaseOutcome.tookOverExpired,
          );

          // The stale worker wakes up and checks before its next step.
          expect(
            await holdsLease(lease, owner: 'stale-op', nowMs: later),
            isFalse,
          );
          expect(
            await acquireLease(
              lease,
              owner: 'stale-op',
              nowMs: later + 1,
              ttl: ttl,
            ),
            LeaseOutcome.heldByOther,
          );
          expect(await releaseLease(lease, owner: 'stale-op'), isFalse);
          expect(Lease.tryParse((await lease.once()).value)?.owner, 'new-op');
        },
      );

      test(
        'it stays locked out after the successor finishes and releases',
        () async {
          final lease = database.ref('/IdentityLocks/t1');
          await acquireLease(lease, owner: 'stale-op', nowMs: 1000, ttl: ttl);
          final later = 1000 + ttl.inMilliseconds + 1;
          await acquireLease(lease, owner: 'new-op', nowMs: later, ttl: ttl);
          await releaseLease(lease, owner: 'new-op');

          expect(
            await holdsLease(lease, owner: 'stale-op', nowMs: later),
            isFalse,
          );

          // A third operation takes the free lease; the stale one is still out.
          await acquireLease(lease, owner: 'third-op', nowMs: later, ttl: ttl);
          expect(
            await holdsLease(lease, owner: 'stale-op', nowMs: later),
            isFalse,
          );
          expect(
            await holdsLease(lease, owner: 'third-op', nowMs: later),
            isTrue,
          );
        },
      );

      test(
        'two operations from one admin cannot both hold the lease',
        () async {
          final lease = database.ref('/IdentityLocks/t1');
          final first = newOperationId();
          final second = newOperationId();

          expect(
            await acquireLease(lease, owner: first, nowMs: 1, ttl: ttl),
            LeaseOutcome.acquired,
          );
          expect(
            await acquireLease(lease, owner: second, nowMs: 2, ttl: ttl),
            LeaseOutcome.heldByOther,
          );
          expect(await holdsLease(lease, owner: second, nowMs: 2), isFalse);
        },
      );

      test('a corrupt stored value is held by nobody', () async {
        final lease = database.ref('/IdentityLocks/t1');
        await lease.set('corrupt');

        expect(await holdsLease(lease, owner: 'op-1', nowMs: 1), isFalse);
      });
    });

    test('an owner that would corrupt the encoding is refused', () async {
      final lease = database.ref('/IdentityLocks/t1');
      await expectLater(
        acquireLease(lease, owner: 'a|b', nowMs: 1, ttl: ttl),
        throwsArgumentError,
      );
      await expectLater(
        acquireLease(lease, owner: 'a', nowMs: 1, ttl: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}
