import 'package:daufootytipping/services/account_deletion.dart';
import 'package:daufootytipping/services/firebase_deletable_account.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _FakeProvider extends Fake implements AuthProvider {}

class _FakeUserInfo extends Fake implements UserInfo {
  _FakeUserInfo(this.providerId);

  @override
  final String providerId;
}

void main() {
  late _MockAuth auth;
  late _MockUser user;

  setUpAll(() => registerFallbackValue(_FakeProvider()));

  setUp(() {
    auth = _MockAuth();
    user = _MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.providerData).thenReturn([_FakeUserInfo('apple.com')]);
  });

  FirebaseDeletableAccount account() => FirebaseDeletableAccount(auth);

  group('signing in again with Apple', () {
    test('works when Apple says it did, and asks Apple', () async {
      when(() => user.reauthenticateWithProvider(any()))
          .thenAnswer((_) async => _FakeCredential());

      await account().reauthenticate();

      final provider = verify(
        () => user.reauthenticateWithProvider(captureAny()),
      ).captured.single;
      expect(provider, isA<AppleAuthProvider>());
    });

    for (final code in [
      'user-mismatch',
      'user-not-found',
      'invalid-credential',
      'invalid-verification-code',
      'invalid-verification-id',
      'network-request-failed',
    ]) {
      test(
        'a failure with $code stops the deletion, it is not taken as success',
        () async {
          when(() => user.reauthenticateWithProvider(any()))
              .thenAnswer((_) async => throw FirebaseAuthException(code: code));

          await expectLater(
            account().reauthenticate(),
            throwsA(
              isA<FirebaseAuthException>().having((e) => e.code, 'code', code),
            ),
          );
        },
      );
    }
  });

  group('signing in again with Google', () {
    test('passes a failure on', () async {
      when(() => user.providerData).thenReturn([_FakeUserInfo('google.com')]);
      when(() => user.reauthenticateWithProvider(any())).thenAnswer(
        (_) async => throw FirebaseAuthException(code: 'invalid-credential'),
      );

      await expectLater(
        account().reauthenticate(),
        throwsA(isA<FirebaseAuthException>()),
      );
    });
  });

  group('an account that cannot sign in again', () {
    test('one with another provider throws', () async {
      when(() => user.providerData).thenReturn([_FakeUserInfo('password')]);

      await expectLater(
        account().reauthenticate(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('one with no provider throws', () async {
      when(() => user.providerData).thenReturn(const <UserInfo>[]);

      await expectLater(account().reauthenticate(), throwsStateError);
    });

    test('nobody signed in throws', () async {
      when(() => auth.currentUser).thenReturn(null);

      await expectLater(account().reauthenticate(), throwsStateError);
    });
  });

  group('deleting the account', () {
    test('a provider that wants a fresher sign-in is told apart', () async {
      when(() => user.delete()).thenAnswer(
        (_) async => throw FirebaseAuthException(code: 'requires-recent-login'),
      );

      await expectLater(
        account().delete(),
        throwsA(isA<RecentSignInRequired>()),
      );
    });

    test('any other failure is passed on as it is', () async {
      when(() => user.delete()).thenAnswer(
        (_) async =>
            throw FirebaseAuthException(code: 'network-request-failed'),
      );

      await expectLater(
        account().delete(),
        throwsA(isA<FirebaseAuthException>()),
      );
    });

    test('succeeds when the provider deletes it', () async {
      when(() => user.delete()).thenAnswer((_) async {});

      await account().delete();

      verify(() => user.delete()).called(1);
    });
  });

  test('the last sign-in time comes from the account\'s metadata', () {
    final signedIn = DateTime.utc(2027, 3, 12, 6);
    when(() => user.metadata).thenReturn(
      UserMetadata(
        signedIn.millisecondsSinceEpoch,
        signedIn.millisecondsSinceEpoch,
      ),
    );

    expect(account().lastSignInTime?.toUtc(), signedIn);
  });
}

class _FakeCredential extends Fake implements UserCredential {}
