import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/alias_failure_message.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/integration_support.dart';
import 'support/person.dart';

void main() {
  if (integrationSkipReason != null) {
    test('client integration tests', () {}, skip: integrationSkipReason);
    return;
  }

  late EmulatorDatabase database;

  setUpAll(() => database = EmulatorDatabase.fromEnvironment());

  setUp(() async {
    await database.reset();
    await database.seedRunningApp();
  });

  Person person(String uid, {String? email}) =>
      Person(database, Account(uid, email: email ?? '$uid@example.test'));

  group('signing in', () {
    test(
      'a new account is asked for an alias, then given a new record',
      () async {
        final ann = person('uidAnn0000000000000000000001');

        final tipper = await ann.signUp('Ann');

        expect(tipper.name, 'Ann');
        expect(tipper.authuid, 'uidAnn0000000000000000000001');
        expect(tipper.tipperRole, TipperRole.tipper);
      },
    );

    test(
      'what the server wrote is what the client reads, under the rules',
      () async {
        final ann = person('uidAnn0000000000000000000001');
        final tipper = await ann.signUp('Ann');

        final index = await database.adminGet(
          '${paths.authIndexPath}/uidAnn0000000000000000000001',
        );
        final private = await database.adminGet(
          '${paths.tipperPrivatePath}/${tipper.dbkey}',
        );
        final public = await database.adminGet(
          '${paths.tippersPath}/${tipper.dbkey}',
        );

        expect(index.body, tipper.dbkey);
        expect(private.map?['authuid'], 'uidAnn0000000000000000000001');
        expect(public.map?['name'], 'Ann');
      },
    );

    test('signing in again asks the server nothing', () async {
      await person('uidAnn0000000000000000000001').signUp('Ann');
      final again = person('uidAnn0000000000000000000001');

      final tipper = await again.signIn();

      expect(tipper.name, 'Ann');
      expect(again.invoker.calls, isEmpty);
    });

    test('with the callables switched off, a new account is told so and an existing one still signs in', () async {
      final ann = person('uidAnn0000000000000000000001');
      await ann.signUp('Ann');
      await database.setIdentityMode('off');

      final newcomer = person('uidBob0000000000000000000002');
      final refused = await newcomer.resolver.resolve(newcomer.link);
      final existing = await person('uidAnn0000000000000000000001').signIn();

      expect(refused.status, LinkStatus.unavailable);
      expect(existing.name, 'Ann');
    });
  });

  group('the alias', () {
    test('a name another tipper has is refused at sign-up, whatever the case or spacing', () async {
      await person('uidAnn0000000000000000000001').signUp('The Oracle');
      final bob = person('uidBob0000000000000000000002');
      expect(
        (await bob.resolver.resolve(bob.link)).status,
        LinkStatus.needsAlias,
      );

      final refused = await bob.resolver.resolve(
        bob.link,
        alias: ' the  oracle ',
      );

      expect(refused.status, LinkStatus.refused);
      expect(refused.reason, reasons.identityReasonAliasTaken);
    });

    test(
      'changing it shows in the public record and frees the old name',
      () async {
        final ann = person('uidAnn0000000000000000000001');
        final tipper = await ann.signUp('Ann');

        final result = await ann.identity.updateTipperAlias('Annabel');

        expect(result.alias, 'Annabel');
        expect(result.tipperId, tipper.dbkey);
        final public = await database.adminGet(
          '${paths.tippersPath}/${tipper.dbkey}',
        );
        expect(public.map?['name'], 'Annabel');

        final bob = person('uidBob0000000000000000000002');
        await bob.resolver.resolve(bob.link);
        expect(
          (await bob.resolver.resolve(bob.link, alias: 'Ann')).status,
          LinkStatus.linked,
        );
      },
    );

    test('taking another tipper\'s name is refused, and the tipper is told in words', () async {
      await person('uidAnn0000000000000000000001').signUp('Ann');
      final bob = person('uidBob0000000000000000000002');
      await bob.signUp('Bob');

      final failure = await bob.identity
          .updateTipperAlias('ann')
          .then<IdentityFailure?>(
            (_) => null,
            onError: (Object e) => e as IdentityFailure,
          );

      expect(failure?.reason, reasons.identityReasonAliasTaken);
      expect(
        aliasFailureMessage(failure!),
        contains('already used by another tipper'),
      );
    });

    test('a name that is not allowed is refused', () async {
      final ann = person('uidAnn0000000000000000000001');
      await ann.signUp('Ann');

      final failure = await ann.identity
          .updateTipperAlias('!!!')
          .then<IdentityFailure?>(
            (_) => null,
            onError: (Object e) => e as IdentityFailure,
          );

      expect(failure?.reason, reasons.identityReasonInvalidAlias);
      expect(aliasFailureMessage(failure!), contains('letter or number'));
    });

    test('a person who is not linked cannot change an alias', () async {
      final stranger = person('uidZed0000000000000000000009');

      final failure = await stranger.identity
          .updateTipperAlias('Zed')
          .then<IdentityFailure?>(
            (_) => null,
            onError: (Object e) => e as IdentityFailure,
          );

      expect(failure?.reason, reasons.identityReasonNotLinked);
    });
  });
}
