import 'dart:developer';

import 'package:daufootytipping/services/account_deletion.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The Firebase Auth user, signed in with Apple or Google, as an account that
/// can be deleted.
class FirebaseDeletableAccount implements DeletableAccount {
  FirebaseDeletableAccount([FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  User get _user {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('No account is signed in');
    }
    return user;
  }

  @override
  DateTime? get lastSignInTime => _auth.currentUser?.metadata.lastSignInTime;

  @override
  Future<void> reauthenticate() async {
    final User user = _user;
    if (user.providerData.isEmpty) {
      throw StateError('The account has no sign-in provider to sign in again');
    }
    switch (user.providerData.first.providerId) {
      case 'apple.com':
        await _reauthenticateWithApple(user);
      case 'google.com':
        await user.reauthenticateWithProvider(GoogleAuthProvider());
      case final String other:
        throw UnsupportedError('Cannot sign in again with $other');
    }
  }

  Future<void> _reauthenticateWithApple(User user) async {
    try {
      await user.reauthenticateWithProvider(AppleAuthProvider());
    } on FirebaseAuthException catch (e) {
      // These codes were let through by the delete flow before it unlinked
      // accounts, and are still. Apple reports some of them although the sign-in
      // went through; if it did not, the delete asks for a fresher sign-in and
      // says so.
      if (e.code == 'user-mismatch' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-verification-code' ||
          e.code == 'invalid-verification-id') {
        log('FirebaseDeletableAccount: Apple sign-in again said ${e.code}');
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const RecentSignInRequired();
      }
      rethrow;
    }
  }
}
