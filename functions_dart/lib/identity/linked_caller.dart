import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/caller.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:dart_functions/rtdb/rest_database.dart';

/// The tipper the signed-in account is linked to, for the callables that only
/// the linked tipper may use (rename, push tokens).
///
/// An account with no link at all is "not linked": the client should call
/// `link-or-create-tipper` first. An index entry that does not check out in both
/// directions is flagged for repair and never trusted (D1, D2). Nothing is read
/// from the request: ownership comes only from the verified uid.
Future<String> requireLinkedTipper(RestDatabase database, String uid) async {
  final resolution = await resolveCallerTipper(database, uid);
  if (resolution is ResolvedCaller) {
    return resolution.tipperId;
  }
  if (resolution is UnresolvedCaller &&
      (resolution.reason == CallerFailure.noMapping ||
          resolution.reason == CallerFailure.invalidUid)) {
    throw FailedPreconditionError(
      'This account is not linked to a tipper yet.',
      reason: identityReasonNotLinked,
    );
  }
  throw FailedPreconditionError(
    'This account needs an administrator to repair it. Please contact support.',
    reason: identityReasonNeedsAudit,
  );
}
