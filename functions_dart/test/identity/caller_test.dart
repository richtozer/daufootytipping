import 'package:dart_functions/identity/caller.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';

Future<void> _seed(
  RestDatabase database, {
  String uid = 'uid-1',
  String tipperId = 'tipper-1',
  Object? indexed = const _Same(),
  Object? record = const _Same(),
}) async {
  final index = indexed is _Same ? tipperId : indexed;
  final privateRecord = record is _Same
      ? <String, Object?>{'authuid': uid, 'tipperRole': 'tipper'}
      : record;
  if (index != null) {
    await database.ref('$authIndexPath/$uid').set(index);
  }
  if (privateRecord != null) {
    await database.ref('$tipperPrivatePath/$tipperId').set(privateRecord);
  }
}

/// "Use the default" marker, so a test can still pass an explicit null.
class _Same {
  const _Same();
}

void main() {
  group('resolveCallerTipper', skip: emulatorSkipReason, () {
    late final database = openEmulatorDatabase();

    setUp(() async {
      await clearEmulatorDatabase(database);
    });

    Future<CallerResolution> resolve([String uid = 'uid-1']) =>
        resolveCallerTipper(database, uid);

    test('a consistent mapping resolves to the tipper and role', () async {
      await _seed(database);

      final resolution = await resolve();

      expect(resolution, isA<ResolvedCaller>());
      final caller = resolution as ResolvedCaller;
      expect(caller.tipperId, 'tipper-1');
      expect(caller.role, TipperRole.tipper);
      expect(caller.isAdmin, isFalse);
    });

    test('the admin role comes from the validated private record', () async {
      await _seed(
        database,
        record: {'authuid': 'uid-1', 'tipperRole': 'admin'},
      );

      final caller = await resolve() as ResolvedCaller;

      expect(caller.isAdmin, isTrue);
    });

    test(
      'an unknown or missing role is an ordinary tipper, never an admin',
      () async {
        for (final role in <Object?>['Admin', 'superuser', 7, null]) {
          await clearEmulatorDatabase(database);
          await _seed(
            database,
            record: {'authuid': 'uid-1', 'tipperRole': role},
          );

          final caller = await resolve() as ResolvedCaller;

          expect(caller.isAdmin, isFalse, reason: '$role');
        }
      },
    );

    test('no index entry grants nothing', () async {
      await _seed(database, indexed: null);

      expect(
        (await resolve() as UnresolvedCaller).reason,
        CallerFailure.noMapping,
      );
    });

    test('an entry pointing at a missing record grants nothing', () async {
      await _seed(database, record: null);

      expect(
        (await resolve() as UnresolvedCaller).reason,
        CallerFailure.recordMissing,
      );
    });

    test(
      'a record that names another uid grants nothing (tampered index)',
      () async {
        await _seed(
          database,
          record: {'authuid': 'someone-else', 'tipperRole': 'admin'},
        );

        expect(
          (await resolve() as UnresolvedCaller).reason,
          CallerFailure.authuidMismatch,
        );
      },
    );

    test('a record with no authuid grants nothing', () async {
      await _seed(database, record: {'tipperRole': 'admin'});

      expect(
        (await resolve() as UnresolvedCaller).reason,
        CallerFailure.authuidMismatch,
      );
    });

    test('an entry that is not a usable tipper id grants nothing', () async {
      for (final bad in <Object?>[
        42,
        true,
        {'a': 1},
        'has.dot',
        'a/b',
        '',
      ]) {
        await clearEmulatorDatabase(database);
        await _seed(database, indexed: bad, record: null);

        expect(
          (await resolve() as UnresolvedCaller).reason,
          CallerFailure.invalidMapping,
          reason: '$bad',
        );
      }
    });

    test(
      'a uid that cannot be a database key is refused before any read',
      () async {
        for (final bad in ['', 'a/b', 'a.b', r'a$b', 'a#b', 'a[0]']) {
          expect(
            (await resolve(bad) as UnresolvedCaller).reason,
            CallerFailure.invalidUid,
            reason: bad,
          );
        }
      },
    );

    test('a role in the public record is ignored', () async {
      await _seed(database);
      await database.ref('$tippersPath/tipper-1').set({
        'authuid': 'uid-1',
        'tipperRole': 'admin',
      });

      final caller = await resolve() as ResolvedCaller;

      expect(caller.isAdmin, isFalse);
    });
  });
}
