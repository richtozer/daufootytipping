import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/dau_shared.dart' show UnlinkMyAccountResult;
import 'package:daufootytipping/services/account_deletion.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockIdentityService extends Mock implements IdentityService {}

class _FakeAccount implements DeletableAccount {
  _FakeAccount(this.events, {required this.lastSignInTime});

  final List<String> events;

  @override
  DateTime? lastSignInTime;

  /// What each call does, in turn; once the list is empty the call succeeds.
  final List<Object?> reauthenticateOutcomes = <Object?>[];
  final List<Object?> deleteOutcomes = <Object?>[];

  @override
  Future<void> reauthenticate() async {
    events.add('sign in again');
    _play(reauthenticateOutcomes);
  }

  @override
  Future<void> delete() async {
    events.add('delete account');
    _play(deleteOutcomes);
  }

  void _play(List<Object?> outcomes) {
    if (outcomes.isEmpty) {
      return;
    }
    final Object? next = outcomes.removeAt(0);
    if (next != null) {
      throw next;
    }
  }
}

void main() {
  final DateTime now = DateTime.utc(2027, 3, 12, 6);
  late _MockIdentityService identity;
  late List<String> events;
  late _FakeAccount account;
  late List<Object?> tokenOutcomes;

  IdentityFailure transient() =>
      IdentityFailure.network(Exception('no connection'));

  IdentityFailure refused(String reason) => IdentityFailure(
    kind: IdentityFailureKind.refused,
    code: 'failed-precondition',
    message: 'server words',
    reason: reason,
  );

  AccountDeletion deletion() => AccountDeletion(
    identity: identity,
    account: account,
    clock: () => now,
    unregisterPushToken: () async {
      events.add('remove push token');
      if (tokenOutcomes.isNotEmpty) {
        final Object? next = tokenOutcomes.removeAt(0);
        if (next != null) {
          throw next;
        }
      }
    },
  );

  setUp(() {
    events = <String>[];
    tokenOutcomes = <Object?>[];
    identity = _MockIdentityService();
    when(() => identity.unlinkMyAccount()).thenAnswer((_) async {
      events.add('unlink');
      return const UnlinkMyAccountResult(unlinked: true);
    });
    account = _FakeAccount(
      events,
      lastSignInTime: now.subtract(const Duration(minutes: 1)),
    );
  });

  test(
    'a recent sign-in: token, unlink, then the account, in that order',
    () async {
      expect(await deletion().run(), isNull);

      expect(events, ['remove push token', 'unlink', 'delete account']);
    },
  );

  test('an old sign-in signs in again before anything is changed', () async {
    account.lastSignInTime = now.subtract(const Duration(hours: 2));

    expect(await deletion().run(), isNull);

    expect(events, [
      'sign in again',
      'remove push token',
      'unlink',
      'delete account',
    ]);
  });

  test('a sign-in of unknown age is treated as old', () async {
    account.lastSignInTime = null;

    await deletion().run();

    expect(events.first, 'sign in again');
  });

  test('backing out of signing in again leaves everything as it was', () async {
    account.lastSignInTime = now.subtract(const Duration(hours: 2));
    account.reauthenticateOutcomes.add(const SignInAgainCancelled());

    final message = await deletion().run();

    expect(message, AccountDeletion.reauthenticationCancelledMessage);
    expect(events, ['sign in again']);
  });

  test(
    'signing in again that does not work leaves everything as it was',
    () async {
      account.lastSignInTime = now.subtract(const Duration(hours: 2));
      account.reauthenticateOutcomes.add(StateError('the sheet failed'));

      final message = await deletion().run();

      expect(message, AccountDeletion.reauthenticationFailedMessage);
      expect(events, ['sign in again']);
    },
  );

  test(
    'an account that cannot sign in again is told how to delete it',
    () async {
      account.lastSignInTime = now.subtract(const Duration(hours: 2));
      account.reauthenticateOutcomes.add(const SignInAgainUnsupported());

      final message = await deletion().run();

      expect(message, AccountDeletion.reauthenticationUnsupportedMessage);
      expect(events, ['sign in again']);
    },
  );

  test('every sign-in-again message says nothing was deleted', () {
    for (final String message in <String>[
      AccountDeletion.reauthenticationFailedMessage,
      AccountDeletion.reauthenticationCancelledMessage,
      AccountDeletion.reauthenticationUnsupportedMessage,
    ]) {
      expect(message, matches(RegExp('[Nn]othing was deleted')));
    }
  });

  group('when the server cannot detach the account', () {
    test('a token that cannot be removed stops the deletion', () async {
      tokenOutcomes.add(transient());

      final message = await deletion().run();

      expect(message, contains('Nothing was deleted'));
      expect(events, ['remove push token']);
    });

    test('an unlink that cannot be done stops the deletion', () async {
      when(() => identity.unlinkMyAccount()).thenAnswer(
        (_) async => throw refused(reasons.identityReasonNotAvailable),
      );

      final message = await deletion().run();

      expect(message, contains('switched off'));
      expect(events, ['remove push token']);
    });

    test('an unreachable server stops the deletion', () async {
      when(() => identity.unlinkMyAccount())
          .thenAnswer((_) async => throw transient());

      final message = await deletion().run();

      expect(message, contains('Nothing was deleted'));
      expect(events, ['remove push token']);
    });
  });

  group('a deletion that fails after the unlink, run again', () {
    test('finishes the job', () async {
      account.deleteOutcomes.add(StateError('network dropped'));

      final first = await deletion().run();
      expect(first, AccountDeletion.deletionFailedMessage);
      expect(events, ['remove push token', 'unlink', 'delete account']);

      // The second time the account is no longer linked: removing the token
      // finds no tipper, and unlinking finds nothing to unlink.
      events.clear();
      tokenOutcomes.add(refused(reasons.identityReasonNotLinked));
      when(() => identity.unlinkMyAccount()).thenAnswer((_) async {
        events.add('unlink');
        return const UnlinkMyAccountResult(unlinked: false);
      });

      expect(await deletion().run(), isNull);
      expect(events, ['remove push token', 'unlink', 'delete account']);
    });

    test(
      'an account that is no longer linked is not a failure at the token',
      () async {
        tokenOutcomes.add(refused(reasons.identityReasonNotLinked));

        expect(await deletion().run(), isNull);
      },
    );
  });

  group('when the provider wants a fresher sign-in at the last step', () {
    test('signs in again and deletes', () async {
      account.deleteOutcomes.add(const RecentSignInRequired());

      expect(await deletion().run(), isNull);

      expect(events, [
        'remove push token',
        'unlink',
        'delete account',
        'sign in again',
        'delete account',
      ]);
    });

    test('says so if signing in again is cancelled', () async {
      account.deleteOutcomes.add(const RecentSignInRequired());
      account.reauthenticateOutcomes.add(const SignInAgainCancelled());

      expect(
        await deletion().run(),
        AccountDeletion.reauthenticationCancelledMessage,
      );
    });

    test('says so if the second delete fails too', () async {
      account.deleteOutcomes
        ..add(const RecentSignInRequired())
        ..add(StateError('still no'));

      expect(await deletion().run(), AccountDeletion.deletionFailedMessage);
    });
  });

  group('what the person is told when the server refuses', () {
    test('another change in progress', () {
      expect(
        accountDeletionFailureMessage(refused(reasons.identityReasonBusy)),
        contains('Wait a moment'),
      );
    });

    test('anything else gets the plain failure message', () {
      expect(
        accountDeletionFailureMessage(refused(reasons.identityReasonClaimed)),
        AccountDeletion.deletionFailedMessage,
      );
    });
  });
}
