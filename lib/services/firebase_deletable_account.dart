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

  /// Has the person sign in again. Any failure is passed on: the deletion goes
  /// on to remove the push token and unlink the tipper, and must not do either
  /// unless signing in again is known to have worked, which is only when this
  /// returns without an error.
  @override
  Future<void> reauthenticate() async {
    final User user = _user;
    if (user.providerData.isEmpty) {
      throw const SignInAgainUnsupported();
    }
    try {
      switch (user.providerData.first.providerId) {
        case 'apple.com':
          await user.reauthenticateWithProvider(AppleAuthProvider());
        case 'google.com':
          await user.reauthenticateWithProvider(GoogleAuthProvider());
        default:
          throw const SignInAgainUnsupported();
      }
    } on FirebaseAuthException catch (e) {
      if (_cancelledCodes.contains(e.code)) {
        throw const SignInAgainCancelled();
      }
      rethrow;
    }
  }

  /// What Firebase Auth reports when the person closes the sign-in sheet.
  static const Set<String> _cancelledCodes = <String>{
    'web-context-canceled',
    'web-context-cancelled',
    'canceled',
    'cancelled',
    'user-cancelled',
    'popup-closed-by-user',
    'cancelled-popup-request',
  };

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
