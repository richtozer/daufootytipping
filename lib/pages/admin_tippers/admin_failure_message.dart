import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:daufootytipping/services/identity_service.dart';

/// What to tell an administrator when an identity callable refuses or fails, from
/// the server's machine-readable reason (never by parsing its text).
String adminFailureMessage(IdentityFailure failure) {
  switch (failure.reason) {
    case reasons.identityReasonAliasTaken:
      return 'That name is already used by another tipper, or is too similar to '
          'theirs.';
    case reasons.identityReasonInvalidAlias:
      return 'That name is not allowed. Use letters, numbers and ordinary '
          'punctuation.';
    case reasons.identityReasonInvalidEmail:
      return 'That email address is not valid.';
    case reasons.identityReasonLastAdmin:
      return 'There must be at least one administrator, so the last one cannot '
          'be changed to an ordinary tipper.';
    case reasons.identityReasonClaimed:
      return 'The login or account on one of these tippers already belongs to '
          'another record, so the change was refused.';
    case reasons.identityReasonNotAdmin:
      return 'Only administrators can change tippers.';
    case reasons.identityReasonBusy:
      return 'Another change to this tipper is in progress. Wait a moment and '
          'try again.';
    case reasons.identityReasonNotAvailable:
      return 'Changing tippers is switched off at the moment.';
  }
  if (failure.kind == IdentityFailureKind.transient) {
    return 'The server could not be reached or is busy. Check the connection '
        'and try again; nothing was changed.';
  }
  if (failure.kind == IdentityFailureKind.unauthenticated) {
    return 'You are not signed in. Sign out and in again, then try again.';
  }
  return 'The change was not made: ${failure.message}';
}
