import 'dart:developer';

import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:daufootytipping/services/identity_service.dart';

/// The sign-in account being deleted, as far as deleting it needs.
abstract interface class DeletableAccount {
  /// When the account last signed in, or null if that is not known.
  DateTime? get lastSignInTime;

  /// Has the person sign in again with their provider.
  Future<void> reauthenticate();

  /// Deletes the sign-in account. Throws [RecentSignInRequired] if the provider
  /// wants a fresher sign-in first.
  Future<void> delete();
}

/// The provider will not delete the account until the person signs in again.
class RecentSignInRequired implements Exception {
  const RecentSignInRequired();

  @override
  String toString() => 'RecentSignInRequired';
}

/// Deletes the signed-in person's account.
///
/// The order matters. The tipper record outlives the sign-in account (it holds
/// the tips), and while it still names the account, signing up again with the
/// same address is refused as already claimed. So before the account goes, the
/// push token is removed and the record is unlinked; both need the account
/// signed in and linked, which is why the account is deleted last. And signing
/// in again comes first of all, so that a person who backs out of it has lost
/// nothing: it is the one step that can be cancelled.
///
/// A deletion that fails after the unlink can simply be run again. The person is
/// still signed in but no longer linked, and each step copes with that: removing
/// the token finds nothing linked, unlinking an unlinked account says so without
/// complaint, and the account is deleted.
class AccountDeletion {
  AccountDeletion({
    required IdentityService identity,
    required DeletableAccount account,
    required Future<void> Function() unregisterPushToken,
    DateTime Function()? clock,
  }) : _identity = identity,
       _account = account,
       _unregisterPushToken = unregisterPushToken,
       _clock = clock ?? DateTime.now;

  /// How recent a sign-in the provider accepts for deleting an account, with
  /// some margin. Older than this, the person is asked to sign in again before
  /// anything is unlinked.
  static const Duration recentSignIn = Duration(minutes: 4);

  static const String reauthenticationFailedMessage =
      'Re-authentication failed. Please try again.';
  static const String deletionFailedMessage =
      'Account deletion failed. Please try again.';

  final IdentityService _identity;
  final DeletableAccount _account;
  final Future<void> Function() _unregisterPushToken;
  final DateTime Function() _clock;

  /// Deletes the account. Null if it was deleted, otherwise what to tell the
  /// person.
  Future<String?> run() async {
    if (_signInIsOld && !await _reauthenticate()) {
      return reauthenticationFailedMessage;
    }
    try {
      await _removePushToken();
      await _identity.unlinkMyAccount();
    } on IdentityFailure catch (failure) {
      log('AccountDeletion: could not detach the account: ${failure.code}');
      return accountDeletionFailureMessage(failure);
    } on Object catch (error) {
      log('AccountDeletion: could not detach the account: $error');
      return deletionFailedMessage;
    }
    return _deleteSignInAccount();
  }

  bool get _signInIsOld {
    final DateTime? last = _account.lastSignInTime;
    return last == null || _clock().difference(last) > recentSignIn;
  }

  Future<bool> _reauthenticate() async {
    try {
      await _account.reauthenticate();
      return true;
    } on Object catch (error) {
      log('AccountDeletion: signing in again failed: $error');
      return false;
    }
  }

  Future<void> _removePushToken() async {
    try {
      await _unregisterPushToken();
    } on IdentityFailure catch (failure) {
      // An earlier try already unlinked the account, and removed the token first.
      if (failure.reason != reasons.identityReasonNotLinked) {
        rethrow;
      }
    }
  }

  Future<String?> _deleteSignInAccount() async {
    try {
      await _account.delete();
      return null;
    } on RecentSignInRequired {
      // The sign-in was newer than it looked, or the provider's limit is
      // shorter. The person is unlinked now, so a refusal here leaves them
      // signed in but unlinked, which running this again repairs.
      log('AccountDeletion: the provider wants a fresher sign-in');
      if (!await _reauthenticate()) {
        return reauthenticationFailedMessage;
      }
      try {
        await _account.delete();
        return null;
      } on Object catch (error) {
        log('AccountDeletion: could not delete the account: $error');
        return deletionFailedMessage;
      }
    } on Object catch (error) {
      log('AccountDeletion: could not delete the account: $error');
      return deletionFailedMessage;
    }
  }
}

/// What to tell a person whose account could not be detached before deletion,
/// from the server's machine-readable reason. Nothing was deleted.
String accountDeletionFailureMessage(IdentityFailure failure) {
  if (failure.reason == reasons.identityReasonNotAvailable) {
    return 'Deleting accounts is switched off at the moment. Nothing was '
        'deleted. Please try again later.';
  }
  if (failure.reason == reasons.identityReasonBusy) {
    return 'Another change to your profile is in progress. Wait a moment and '
        'try again.';
  }
  if (failure.kind == IdentityFailureKind.transient) {
    return 'The server could not be reached or is busy. Nothing was deleted. '
        'Check your connection and try again.';
  }
  return AccountDeletion.deletionFailedMessage;
}
