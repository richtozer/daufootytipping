import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:daufootytipping/pages/admin_tippers/admin_failure_message.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IdentityFailure refused(String reason) => IdentityFailure(
    kind: IdentityFailureKind.refused,
    code: 'failed-precondition',
    message: 'server text that must not be shown for a known reason',
    reason: reason,
  );

  group('says what went wrong in words, from the reason', () {
    final expected = <String, String>{
      reasons.identityReasonAliasTaken: 'already used',
      reasons.identityReasonInvalidAlias: 'not allowed',
      reasons.identityReasonInvalidEmail: 'not valid',
      reasons.identityReasonLastAdmin: 'at least one administrator',
      reasons.identityReasonClaimed: 'already belongs',
      reasons.identityReasonNotAdmin: 'Only administrators',
      reasons.identityReasonBusy: 'in progress',
      reasons.identityReasonNotAvailable: 'switched off',
    };
    for (final entry in expected.entries) {
      test(entry.key, () {
        final message = adminFailureMessage(refused(entry.key));
        expect(message, contains(entry.value));
        expect(message, isNot(contains('server text')));
      });
    }
  });

  test('a failure to reach the server says nothing was changed', () {
    final message = adminFailureMessage(
      IdentityFailure.network(Exception('offline')),
    );

    expect(message, contains('nothing was changed'));
  });

  test('an unknown refusal passes the server\'s own words along', () {
    final message = adminFailureMessage(
      const IdentityFailure(
        kind: IdentityFailureKind.refused,
        code: 'failed-precondition',
        message: 'something new',
      ),
    );

    expect(message, contains('something new'));
  });

  test('a lost session says to sign in again', () {
    final message = adminFailureMessage(
      const IdentityFailure(
        kind: IdentityFailureKind.unauthenticated,
        code: 'unauthenticated',
        message: 'no session',
      ),
    );

    expect(message, contains('Sign out and in again'));
  });
}
