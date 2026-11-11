import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/services/identity_keys.dart' show maxAliasLength;
import 'package:daufootytipping/services/identity_service.dart';

/// What to tell a tipper who tried to change their own alias and was refused, or
/// whose request failed, from the server's machine-readable reason (never by
/// parsing its text).
String aliasFailureMessage(IdentityFailure failure) {
  switch (failure.reason) {
    case reasons.identityReasonAliasTaken:
      return 'That name is already used by another tipper, or is too similar to '
          'theirs. Please choose another.';
    case reasons.identityReasonInvalidAlias:
      return 'That name cannot be used. Please choose a name with at least one '
          'letter or number, no more than $maxAliasLength characters long.';
    case reasons.identityReasonBusy:
      return 'Another change to your profile is in progress. Wait a moment and '
          'try again.';
    case reasons.identityReasonNotAvailable:
      return 'Changing your name is switched off at the moment. Please try '
          'again later.';
    case reasons.identityReasonNotLinked:
      return 'Your sign-in is not linked to a tipper yet. Sign out and in '
          'again, then try again.';
  }
  if (failure.kind == IdentityFailureKind.transient) {
    return 'The server could not be reached or is busy. Check your connection '
        'and try again; your name was not changed.';
  }
  if (failure.kind == IdentityFailureKind.unauthenticated) {
    return 'You are not signed in. Sign out and in again, then try again.';
  }
  return 'Your name was not changed: ${failure.message}';
}
