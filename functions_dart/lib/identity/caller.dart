import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';

/// Why a Firebase Auth uid does not resolve to a tipper.
enum CallerFailure {
  /// The uid cannot be used as a database key.
  invalidUid,

  /// `/AuthIndex` has no entry for the uid.
  noMapping,

  /// The entry is not a usable tipper id.
  invalidMapping,

  /// The entry points at a tipper that has no private record.
  recordMissing,

  /// The private record's `authuid` is not this uid.
  authuidMismatch,
}

/// The result of [resolveCallerTipper].
sealed class CallerResolution {
  const CallerResolution();
}

/// The uid maps to a tipper whose own record agrees.
final class ResolvedCaller extends CallerResolution {
  const ResolvedCaller({required this.tipperId, required this.role});

  final String tipperId;
  final TipperRole role;

  bool get isAdmin => role == TipperRole.admin;
}

/// The uid grants nothing. [reason] is for logs and tests, not for clients.
final class UnresolvedCaller extends CallerResolution {
  const UnresolvedCaller(this.reason);

  final CallerFailure reason;
}

/// Finds the tipper a Firebase Auth uid belongs to, checking both directions:
/// `/AuthIndex/{uid}` names the tipper, and that tipper's private record names
/// the same uid. A missing record, a missing entry or a disagreement grants
/// nothing, so partial or tampered state fails closed (DESIGN-database-rules.md,
/// D1). Admin is the validated tipper's role, never a list in public data.
Future<CallerResolution> resolveCallerTipper(
  RestDatabase database,
  String uid,
) async {
  if (!isValidRtdbKey(uid)) {
    return const UnresolvedCaller(CallerFailure.invalidUid);
  }
  final indexed = (await database.ref('$authIndexPath/$uid').once()).value;
  if (indexed == null) {
    return const UnresolvedCaller(CallerFailure.noMapping);
  }
  if (indexed is! String || !isValidRtdbKey(indexed)) {
    return const UnresolvedCaller(CallerFailure.invalidMapping);
  }
  final record =
      (await database.ref('$tipperPrivatePath/$indexed').once()).value;
  if (record is! Map) {
    return const UnresolvedCaller(CallerFailure.recordMissing);
  }
  if (record['authuid'] != uid) {
    return const UnresolvedCaller(CallerFailure.authuidMismatch);
  }
  return ResolvedCaller(tipperId: indexed, role: _roleOf(record['tipperRole']));
}

/// Anything that is not exactly a known role is an ordinary tipper.
TipperRole _roleOf(Object? raw) {
  for (final role in TipperRole.values) {
    if (role.name == raw) {
      return role;
    }
  }
  return TipperRole.tipper;
}
