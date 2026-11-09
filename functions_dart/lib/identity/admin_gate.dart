import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dau_shared/constants/identity_reasons.dart';

/// Refuses anyone who is not an administrator.
///
/// Until the cutover an administrator is an account on the compile-time
/// allowlist (`config/admin-auth-uids.json`), the same list the database rules
/// and the other admin endpoints use. At the cutover the check moves to the
/// linked tipper's role (DESIGN-database-rules-phase4.md, M4c); this is the one
/// place to change, and every admin callable goes through it.
void requireAdmin(CallerToken caller, Set<String> adminUids) {
  if (!adminUids.contains(caller.uid)) {
    throw PermissionDeniedError(
      'Only an administrator can do that.',
      reason: identityReasonNotAdmin,
    );
  }
}
