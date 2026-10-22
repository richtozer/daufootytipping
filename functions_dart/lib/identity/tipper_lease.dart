import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/leases.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:dau_shared/constants/paths.dart' as paths;

/// How long a per-tipper lease lasts. Longer than the callables' hard timeout
/// (60 seconds), so a worker that still holds it has, by construction, already
/// been killed except for a platform pause.
const Duration tipperLeaseTtl = Duration(minutes: 5);

/// Runs [body] holding the lease on one tipper (`/IdentityLocks/{tipperId}`,
/// owned by this operation's unique id), so changes to one tipper are
/// serialised. A live lease held by another operation refuses the request as
/// busy. The lease is released afterwards, except after a [SimulatedCrash],
/// which must leave it to expire as a real crash would.
Future<T> withTipperLease<T>(
  RestDatabase database, {
  required String tipperId,
  required String operationId,
  required int Function() nowMs,
  required Future<T> Function() body,
  Duration ttl = tipperLeaseTtl,
}) async {
  final ref = database.ref('${paths.identityLocksPath}/$tipperId');
  final outcome = await acquireLease(
    ref,
    owner: operationId,
    nowMs: nowMs(),
    ttl: ttl,
  );
  if (outcome == LeaseOutcome.heldByOther) {
    throw AbortedError(
      'Another change to this tipper is in progress. Please try again.',
      reason: identityReasonBusy,
    );
  }
  var crashed = false;
  try {
    return await body();
  } on SimulatedCrash {
    crashed = true;
    rethrow;
  } finally {
    if (!crashed) {
      await releaseLease(ref, owner: operationId);
    }
  }
}
