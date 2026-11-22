import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/services/identity_keys.dart' show maxAliasLength;
import 'package:daufootytipping/pages/user_home/alias_failure_message.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IdentityFailure failure({
    IdentityFailureKind kind = IdentityFailureKind.refused,
    String? reason,
  }) => IdentityFailure(
    kind: kind,
    code: 'some-code',
    message: 'server words',
    reason: reason,
  );

  test('a name already taken says so and asks for another', () {
    final message = aliasFailureMessage(
      failure(reason: reasons.identityReasonAliasTaken),
    );

    expect(message, contains('already used by another tipper'));
    expect(message, contains('choose another'));
  });

  test('a name that is not allowed gives the limit', () {
    final message = aliasFailureMessage(
      failure(reason: reasons.identityReasonInvalidAlias),
    );

    expect(message, contains('letter or number'));
    expect(message, contains('$maxAliasLength'));
  });

  test('another change in progress says to wait', () {
    expect(
      aliasFailureMessage(failure(reason: reasons.identityReasonBusy)),
      contains('Wait a moment'),
    );
  });

  test('names switched off say so', () {
    expect(
      aliasFailureMessage(failure(reason: reasons.identityReasonNotAvailable)),
      contains('switched off'),
    );
  });

  test('an account not linked to a tipper says to sign in again', () {
    expect(
      aliasFailureMessage(failure(reason: reasons.identityReasonNotLinked)),
      contains('not linked'),
    );
  });

  test('a failure to reach the server says nothing was changed', () {
    expect(
      aliasFailureMessage(failure(kind: IdentityFailureKind.transient)),
      contains('was not changed'),
    );
  });

  test('being signed out says so', () {
    expect(
      aliasFailureMessage(failure(kind: IdentityFailureKind.unauthenticated)),
      contains('not signed in'),
    );
  });

  test('anything else passes the server\'s own words on', () {
    expect(aliasFailureMessage(failure()), contains('server words'));
  });
}
