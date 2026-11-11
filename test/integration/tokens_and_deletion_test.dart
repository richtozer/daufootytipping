import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart'
    show deletedTipperName, tipperAccountDeletedField;
import 'package:daufootytipping/services/account_deletion.dart';
import 'package:daufootytipping/services/device_token_registrar.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/integration_support.dart';
import 'support/person.dart';

const String _token = 'dXYZ:APA91bIntegration-0001_aaaaaaaaaaaaaaaa';

/// The sign-in account, which the Firebase Auth SDK would delete on a device.
class _Account implements DeletableAccount {
  _Account(this.events);

  final List<String> events;
  final List<Object> deleteFailures = <Object>[];

  @override
  DateTime? get lastSignInTime => DateTime.now();

  @override
  Future<void> reauthenticate() async => events.add('sign in again');

  @override
  Future<void> delete() async {
    events.add('delete account');
    if (deleteFailures.isNotEmpty) {
      throw deleteFailures.removeAt(0);
    }
  }
}

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

  Future<Object?> tokensOf(String tipperId) async =>
      (await database.adminGet('${paths.tokensPath}/$tipperId')).body;

  group('push tokens', () {
    test('a registered token is stored under the tipper', () async {
      final ann = person('uidAnn0000000000000000000001');
      final tipper = await ann.signUp('Ann');

      final registered = await DeviceTokenRegistrar(identity: ann.identity)
          .register(_token);

      expect(registered, isTrue);
      expect((await tokensOf(tipper.dbkey!)) as Map, contains(_token));
    });

    test('the next tipper to register the same token takes it', () async {
      final ann = person('uidAnn0000000000000000000001');
      final bob = person('uidBob0000000000000000000002');
      final annTipper = await ann.signUp('Ann');
      final bobTipper = await bob.signUp('Bob');
      await DeviceTokenRegistrar(identity: ann.identity).register(_token);

      await DeviceTokenRegistrar(identity: bob.identity).register(_token);

      expect(await tokensOf(annTipper.dbkey!), isNull);
      expect((await tokensOf(bobTipper.dbkey!)) as Map, contains(_token));
    });

    test('removing it leaves the tipper without it', () async {
      final ann = person('uidAnn0000000000000000000001');
      final tipper = await ann.signUp('Ann');
      final registrar = DeviceTokenRegistrar(identity: ann.identity);
      await registrar.register(_token);

      await registrar.unregister(_token);

      expect(await tokensOf(tipper.dbkey!), isNull);
    });

    test('with the callables switched off nothing is stored, and the app is not stopped', () async {
      final ann = person('uidAnn0000000000000000000001');
      final tipper = await ann.signUp('Ann');
      await database.setIdentityMode('off');

      final registered = await DeviceTokenRegistrar(identity: ann.identity)
          .register(_token);

      expect(registered, isFalse);
      expect(await tokensOf(tipper.dbkey!), isNull);
    });
  });

  group('deleting the account', () {
    late Person ann;
    late String tipperId;
    late DeviceTokenRegistrar registrar;
    late List<String> events;
    late _Account account;

    AccountDeletion deletion() => AccountDeletion(
      identity: ann.identity,
      account: account,
      unregisterPushToken: () => registrar.unregister(_token),
    );

    setUp(() async {
      ann = person('uidAnn0000000000000000000001', email: 'ann@example.test');
      tipperId = (await ann.signUp('Ann')).dbkey!;
      registrar = DeviceTokenRegistrar(identity: ann.identity);
      await registrar.register(_token);
      events = <String>[];
      account = _Account(events);
    });

    Future<Object?> indexEntry() async => (await database.adminGet(
      '${paths.authIndexPath}/uidAnn0000000000000000000001',
    )).body;

    test(
      'removes the token and unlinks the tipper, before the account goes',
      () async {
        expect(await deletion().run(), isNull);

        expect(events, ['delete account']);
        expect(await tokensOf(tipperId), isNull);
        expect(await indexEntry(), isNull);
        final private = await database.adminGet(
          '${paths.tipperPrivatePath}/$tipperId',
        );
        expect(
          private.map?.containsKey('authuid'),
          isFalse,
          reason: 'free to be linked again',
        );
      },
    );

    test('keeps the record for its tips, but anonymised, and says so for the administrators', () async {
      await deletion().run();

      final public = await database.adminGet('${paths.tippersPath}/$tipperId');
      expect(public.map?['name'], deletedTipperName);
      expect(public.map?.containsKey('email'), isFalse);
      expect(public.map?.containsKey('logon'), isFalse);
      expect(public.map?.containsKey('photoURL'), isFalse);

      final private = await database.adminGet(
        '${paths.tipperPrivatePath}/$tipperId',
      );
      expect(private.map?.containsKey('email'), isFalse);
      expect(private.map?.containsKey('logon'), isFalse);
      expect(private.map?[tipperAccountDeletedField], isA<String>());
    });

    test('signing up again with the same address makes a new tipper, and the name is free', () async {
      await deletion().run();

      final again = person(
        'uidAnn0000000000000000000099',
        email: 'ann@example.test',
      );
      final tipper = await again.signUp('Ann');

      expect(tipper.dbkey, isNot(tipperId));
      expect(tipper.name, 'Ann');
      final old = await database.adminGet('${paths.tippersPath}/$tipperId');
      expect(old.map?['name'], deletedTipperName);
    });

    test(
      'a deletion that fails after the unlink is simply run again',
      () async {
        account.deleteFailures.add(StateError('the connection dropped'));

        final first = await deletion().run();
        expect(first, AccountDeletion.deletionFailedMessage);
        expect(await indexEntry(), isNull, reason: 'unlinked already');
        expect(await tokensOf(tipperId), isNull);

        events.clear();
        final second = await deletion().run();

        expect(second, isNull);
        expect(events, ['delete account']);
      },
    );

    test('with the callables switched off, nothing is deleted and the person is told', () async {
      await database.setIdentityMode('off');

      final message = await deletion().run();

      expect(message, contains('switched off'));
      expect(events, isEmpty, reason: 'the account was not deleted');
      expect(await indexEntry(), tipperId, reason: 'still linked');
    });

    test('a person who is not linked is refused by the server with the reason the flow expects', () async {
      await deletion().run();

      final failure = await ann.identity
          .unregisterDeviceToken(_token)
          .then<IdentityFailure?>(
            (_) => null,
            onError: (Object e) => e as IdentityFailure,
          );

      expect(failure?.reason, reasons.identityReasonNotLinked);
    });
  });
}
