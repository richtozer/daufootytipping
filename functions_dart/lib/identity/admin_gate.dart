import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/caller.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/identity_reasons.dart';

/// Refuses anyone who is not an administrator.
///
/// An administrator is the tipper whose `/AuthIndex` entry names them and whose
/// private record names them back and says `admin` (see [resolveCallerTipper]):
/// the same test the R2 database rules apply, so what the rules let an
/// administrator do and what the functions let them do cannot come apart. A role
/// changed by `admin-update-tipper` takes effect at once, in both places. Nothing
/// is read from public data, and an unreadable or half-written record grants
/// nothing: a failed read refuses the call.
///
/// Before the cutover this was a list of accounts compiled into the functions
/// (`config/admin-auth-uids.json`), which the R1 rules still use; see
/// DESIGN-database-rules-phase4.md, section 8.
Future<void> requireAdmin(RestDatabase database, CallerToken caller) async {
  if (caller.isAnonymous) {
    throw _notAdmin();
  }
  await requireAdministratorUid(
    (path) async => (await database.ref(path).once()).value,
    caller.uid,
  );
}

/// [requireAdmin] for the endpoints that hold another kind of database handle:
/// [read] gives the value at a path.
Future<void> requireAdministratorUid(ReadValue read, String uid) async {
  final resolution = await resolveCallerTipperFrom(read, uid);
  if (resolution is! ResolvedCaller || !resolution.isAdmin) {
    throw _notAdmin();
  }
}

PermissionDeniedError _notAdmin() => PermissionDeniedError(
  'Only an administrator can do that.',
  reason: identityReasonNotAdmin,
);
