import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_failure_message.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/integration_support.dart';
import 'support/person.dart';

Future<IdentityFailure> _failureOf(Future<Object?> call) =>
    call.then<IdentityFailure>(
      (_) => throw StateError('the call was expected to fail'),
      onError: (Object e) => e as IdentityFailure,
    );

void main() {
  if (integrationSkipReason != null) {
    test('client integration tests', () {}, skip: integrationSkipReason);
    return;
  }

  late EmulatorDatabase database;
  late Person admin;
  late Person ann;
  late Person bob;
  late Tipper adminTipper;
  late Tipper annTipper;
  late Tipper bobTipper;

  setUpAll(() => database = EmulatorDatabase.fromEnvironment());

  setUp(() async {
    await database.reset();
    await database.seedRunningApp();
    // The server accepts the admin callables only from the accounts compiled into
    // it, which is also what the real administrators are.
    admin = Person(
      database,
      Account(serverAdminUid(), email: 'admin@example.test'),
    );
    ann = Person(
      database,
      const Account('uidAnn0000000000000000000001', email: 'ann@example.test'),
    );
    bob = Person(
      database,
      const Account('uidBob0000000000000000000002', email: 'bob@example.test'),
    );
    adminTipper = await admin.signUp('Admin');
    annTipper = await ann.signUp('Ann');
    bobTipper = await bob.signUp('Bob');
    await admin.identity.adminUpdateTipper(
      tipperId: adminTipper.dbkey!,
      role: TipperRole.admin,
    );
  });

  group('editing a tipper', () {
    test('changes name, email and role in one call, and says which', () async {
      final result = await admin.identity.adminUpdateTipper(
        tipperId: annTipper.dbkey!,
        name: 'Annabel',
        email: 'annabel@example.test',
        role: TipperRole.admin,
      );

      expect(result.changed, unorderedEquals(['name', 'email', 'role']));
      final public = await database.adminGet(
        '${paths.tippersPath}/${annTipper.dbkey}',
      );
      final private = await database.adminGet(
        '${paths.tipperPrivatePath}/${annTipper.dbkey}',
      );
      expect(public.map?['name'], 'Annabel');
      expect(private.map?['email'], 'annabel@example.test');
      expect(private.map?['tipperRole'], 'admin');
    });

    test(
      'a field that already holds the value is not reported as changed',
      () async {
        final result = await admin.identity.adminUpdateTipper(
          tipperId: annTipper.dbkey!,
          name: 'Ann',
        );

        expect(result.changed, isEmpty);
      },
    );

    test(
      'a name another tipper has is refused, in words an administrator can use',
      () async {
        final failure = await _failureOf(
          admin.identity.adminUpdateTipper(
            tipperId: annTipper.dbkey!,
            name: 'bob',
          ),
        );

        expect(failure.reason, reasons.identityReasonAliasTaken);
        expect(
          adminFailureMessage(failure),
          contains('already used by another tipper'),
        );
      },
    );

    test('an email address that is not valid is refused', () async {
      final failure = await _failureOf(
        admin.identity.adminUpdateTipper(
          tipperId: annTipper.dbkey!,
          email: 'not an address',
        ),
      );

      expect(failure.reason, reasons.identityReasonInvalidEmail);
      expect(adminFailureMessage(failure), contains('not valid'));
    });

    test('the only administrator cannot be made an ordinary tipper', () async {
      final failure = await _failureOf(
        admin.identity.adminUpdateTipper(
          tipperId: adminTipper.dbkey!,
          role: TipperRole.tipper,
        ),
      );

      expect(failure.reason, reasons.identityReasonLastAdmin);
      expect(
        adminFailureMessage(failure),
        contains('at least one administrator'),
      );
    });

    test(
      'once another administrator can sign in, the first can step down',
      () async {
        await admin.identity.adminUpdateTipper(
          tipperId: bobTipper.dbkey!,
          role: TipperRole.admin,
        );

        final result = await admin.identity.adminUpdateTipper(
          tipperId: adminTipper.dbkey!,
          role: TipperRole.tipper,
        );

        expect(result.changed, ['role']);
      },
    );

    test('someone who is not an administrator is refused', () async {
      final failure = await _failureOf(
        ann.identity.adminUpdateTipper(
          tipperId: bobTipper.dbkey!,
          name: 'Robert',
        ),
      );

      expect(failure.reason, reasons.identityReasonNotAdmin);
      expect(adminFailureMessage(failure), contains('Only administrators'));
    });
  });

  group('merging two tippers', () {
    const comp = 'comp1';

    Future<void> seedTips() async {
      // The merge looks for tips in the competitions the database lists.
      await database.adminPut('${paths.daucompsPath}/$comp', {
        'name': 'Comp 1',
      });
      await database.adminPatch('/', {
        '${paths.tipsPathRoot}/$comp/${annTipper.dbkey}/g1': {
          'r': 'a',
          't': 1700000000,
        },
        '${paths.tipsPathRoot}/$comp/${annTipper.dbkey}/g2': {
          'r': 'e',
          't': 1700000100,
        },
        '${paths.tipsPathRoot}/$comp/${bobTipper.dbkey}/g1': {
          'r': 'b',
          't': 1700000200,
        },
      });
    }

    Future<Map<String, dynamic>?> tipsOf(Tipper tipper) async =>
        (await database.adminGet('${paths.tipsPathRoot}/$comp/${tipper.dbkey}'))
            .map;

    test('a dry run reports what would move and changes nothing', () async {
      await seedTips();

      final preview = await admin.identity.adminMergeTippers(
        originalId: annTipper.dbkey!,
        targetId: bobTipper.dbkey!,
        mergeTips: true,
        mergeLogon: true,
        dryRun: true,
      );

      expect(preview.dryRun, isTrue);
      expect(preview.tipsMoved, 2);
      expect(preview.tipsReplaced, 1, reason: 'game g1 is tipped by both');
      expect((await tipsOf(annTipper))?.keys, unorderedEquals(['g1', 'g2']));
      expect((await tipsOf(bobTipper))?['g1'], containsPair('r', 'b'));
      expect(
        (await database.adminGet('${paths.tippersPath}/${annTipper.dbkey}'))
            .map,
        isNotNull,
      );
    });

    test(
      'the merge moves the tips to the target and removes the source',
      () async {
        await seedTips();

        final done = await admin.identity.adminMergeTippers(
          originalId: annTipper.dbkey!,
          targetId: bobTipper.dbkey!,
          mergeTips: true,
          mergeLogon: true,
        );

        expect(done.dryRun, isFalse);
        expect(done.targetId, bobTipper.dbkey);
        final bobTips = await tipsOf(bobTipper);
        expect(bobTips?.keys, unorderedEquals(['g1', 'g2']));
        expect(
          bobTips?['g1'],
          containsPair('r', 'a'),
          reason: 'the source\'s tip replaces the target\'s',
        );
        expect(await tipsOf(annTipper), isNull);
        expect(
          (await database.adminGet('${paths.tippersPath}/${annTipper.dbkey}'))
              .body,
          isNull,
        );
        expect(
          (await database.adminGet(
            '${paths.tipperPrivatePath}/${annTipper.dbkey}',
          )).body,
          isNull,
        );
      },
    );

    test(
      'moves the sign-in with it, so the source\'s account reaches the target',
      () async {
        await seedTips();

        await admin.identity.adminMergeTippers(
          originalId: annTipper.dbkey!,
          targetId: bobTipper.dbkey!,
          mergeTips: true,
          mergeLogon: true,
        );

        final index = await database.adminGet(
          '${paths.authIndexPath}/${ann.account.uid}',
        );
        expect(
          index.body,
          bobTipper.dbkey,
          reason: 'Ann\'s account now signs in as the merged tipper',
        );
      },
    );

    test('someone who is not an administrator cannot merge', () async {
      final failure = await _failureOf(
        ann.identity.adminMergeTippers(
          originalId: bobTipper.dbkey!,
          targetId: annTipper.dbkey!,
          dryRun: true,
        ),
      );

      expect(failure.reason, reasons.identityReasonNotAdmin);
    });
  });
}
