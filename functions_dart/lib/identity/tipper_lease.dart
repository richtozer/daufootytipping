import 'dart:async';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/leases.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:dau_shared/constants/paths.dart' as paths;

/// How long a per-tipper lease lasts. A handler stops itself at the first step
/// boundary after its deadline (see `HandlerDeadline`), so even one whose request
/// Cloud Run has already timed out cannot go on writing for anything like this
/// long. The lease must outlast any worker, because an expired lease is taken
/// over.
const Duration tipperLeaseTtl = Duration(minutes: 5);

/// How long the lease waits for the worker's own writes to finish before it is
/// left in place. See [withTipperLease].
const Duration leaseSettleGrace = Duration(seconds: 5);

/// Runs [body] holding the lease on one tipper (`/IdentityLocks/{tipperId}`,
/// owned by this operation's unique id), so changes to one tipper are
/// serialised. A live lease held by another operation refuses the request as
/// busy.
///
/// The lease is released afterwards only once every write the worker sent has
/// finished. A write that timed out is not cancelled: it can still reach the
/// database after the body has thrown, and the next operation must not start
/// while it is on its way. If writes are still unsettled after [settleGrace] the
/// lease is left in place and released in the background when they do finish; if
/// that never happens it expires. After a [SimulatedCrash] it is left to expire,
/// as a real crash would.
Future<T> withTipperLease<T>(
  RestDatabase database, {
  required String tipperId,
  required String operationId,
  required int Function() nowMs,
  required Future<T> Function() body,
  Duration ttl = tipperLeaseTtl,
  Duration settleGrace = leaseSettleGrace,
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
      if (await database.writes.settled(timeout: settleGrace)) {
        await releaseLease(ref, owner: operationId);
      } else {
        _releaseWhenSettled(database, ref, operationId, ttl);
      }
    }
  }
}

/// Releases the lease in the background once every write on [database] has
/// finished, or gives up (the lease then expires on its own). Never throws.
void _releaseWhenSettled(
  RestDatabase database,
  RestDatabaseReference ref,
  String operationId,
  Duration wait,
) {
  unawaited(() async {
    try {
      if (await database.writes.settled(timeout: wait)) {
        await releaseLease(ref, owner: operationId);
      }
    } on Object {
      // The lease expires on its own.
    }
  }());
}
