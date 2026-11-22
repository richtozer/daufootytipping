import 'dart:async';
import 'dart:io';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/leases.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:dau_shared/constants/paths.dart' as paths;

/// How long a per-tipper lease lasts. An expired lease is taken over, so this is
/// a promise the code has to keep, not just a number: nothing a worker sends may
/// land after its lease has expired. Three things keep it, and none is airtight
/// on its own:
///
/// * a handler stops starting new steps after its deadline (`HandlerDeadline`),
///   which is far inside this;
/// * while the body runs, no write is *sent* in the last [leaseWriteMargin] of
///   the lease (the write fence below), so a worker that was paused past its
///   lease and then resumes cannot go on writing; and
/// * a worker that ends with writes still on their way, or whose outcome it
///   does not know, keeps the lease past this ([unresolvedWriteHold]) or lets it
///   run out, instead of releasing it.
///
/// What remains: the Realtime Database offers no write that is conditional on
/// another location, so there is no fencing token that makes a write sent
/// *before* the lease expired harmless when it is delivered long after. The
/// code narrows that to a worker that dies or is frozen between the fence check
/// and the send, with the request then held in the network for longer than the
/// lease. The periodic audit (M4c) is what catches anything that gets through.
const Duration tipperLeaseTtl = Duration(minutes: 5);

/// How long before its expiry the write fence closes: no write is sent in the
/// body of a lease inside this margin. It covers the worst case after the last
/// permitted write: that request timing out (15 seconds), the wait for writes to
/// settle ([leaseSettleGrace], 5 seconds) and the write that extends the lease
/// for an unsettled write (up to 5 seconds), so the lease is extended, or the
/// writes are accounted for, before it can be taken over.
const Duration leaseWriteMargin = Duration(seconds: 30);

/// How long a lease is held when its worker ended with writes still unsettled.
/// A request that is given up on is not cancelled, and a request stuck in the
/// network can be delivered much later than a healthy one. Fifteen minutes is an
/// operational holding period: far longer than a healthy request takes, and
/// about as long as a stuck connection can linger. It is not a guarantee that
/// nothing arrives later. It applies only to writes still pending when the body
/// ends; a write that has finished with an unknown outcome leaves just the
/// lease's own remaining time. Once either has run out another operation can
/// proceed over unresolved state, and the in-flight marker that is kept blocks a
/// drain, not ordinary requests. The plan (section 6f, scope reset) records
/// that as an accepted limitation, repaired by hand if it ever happens.
const Duration unresolvedWriteHold = Duration(minutes: 15);

/// How long the lease waits for the worker's own writes to finish before it
/// treats them as unsettled. See [withTipperLease].
const Duration leaseSettleGrace = Duration(seconds: 5);

/// Runs [body] holding the lease on one tipper (`/IdentityLocks/{tipperId}`,
/// owned by this operation's unique id), so changes to one tipper are
/// serialised. A live lease held by another operation refuses the request as
/// busy.
///
/// **While the body runs** every write on [database] is refused before it is
/// sent once the lease is within [writeMargin] of expiring. Writes after the
/// body (releasing the lease, holding it) are not. The fence lives on the
/// handle's write ledger, so [database] must be the handle of one request, as
/// it is in the callables; two operations sharing a handle would fence each
/// other.
///
/// **Afterwards** the lease is released only when every write the worker sent
/// has finished *and* has a known outcome:
///
/// * writes still unsettled after [settleGrace]: the lease is held for [hold],
///   whatever its own ttl, because those writes can still reach the database
///   after the body has thrown, and the next operation must not start while they
///   are on their way. It is released in the background if they all finish with
///   known outcomes, and otherwise runs out;
/// * writes finished, but some without a known outcome (a lost response or a
///   5xx; see `WriteLedger.uncertainCount`): the lease is left to run out. The
///   write may have been applied, the next operation is not told which, and the
///   time left on the lease is the margin for a server still working on it;
/// * otherwise it is released at once.
///
/// After a [SimulatedCrash] it is left to expire, as a real crash would.
Future<T> withTipperLease<T>(
  RestDatabase database, {
  required String tipperId,
  required String operationId,
  required int Function() nowMs,
  required Future<T> Function() body,
  Duration ttl = tipperLeaseTtl,
  Duration settleGrace = leaseSettleGrace,
  Duration writeMargin = leaseWriteMargin,
  Duration hold = unresolvedWriteHold,
  void Function(String line)? log,
}) async {
  final write = log ?? (String line) => stdout.writeln(line);
  final ref = database.ref('${paths.identityLocksPath}/$tipperId');
  final acquiredAtMs = nowMs();
  final outcome = await acquireLease(
    ref,
    owner: operationId,
    nowMs: acquiredAtMs,
    ttl: ttl,
  );
  if (outcome == LeaseOutcome.heldByOther) {
    throw AbortedError(
      'Another change to this tipper is in progress. Please try again.',
      reason: identityReasonBusy,
    );
  }

  final fenceClosesAtMs =
      acquiredAtMs + ttl.inMilliseconds - writeMargin.inMilliseconds;
  final ledger = database.writes;
  final outerFence = ledger.fence;
  ledger.fence = () {
    outerFence?.call();
    if (nowMs() >= fenceClosesAtMs) {
      write(
        '[identity] write refused op=$operationId: the lease on $tipperId '
        'is about to expire',
      );
      throw UnavailableError(
        'That took too long. Please try again.',
        reason: identityReasonUnavailable,
      );
    }
  };

  var crashed = false;
  try {
    return await body();
  } on SimulatedCrash {
    crashed = true;
    rethrow;
  } finally {
    ledger.fence = outerFence;
    if (!crashed) {
      await _finish(
        database,
        ref,
        operationId,
        nowMs: nowMs,
        settleGrace: settleGrace,
        hold: hold,
        write: write,
      );
    }
  }
}

/// Decides what happens to the lease once the body is over: release, hold, or
/// leave to expire.
Future<void> _finish(
  RestDatabase database,
  RestDatabaseReference ref,
  String operationId, {
  required int Function() nowMs,
  required Duration settleGrace,
  required Duration hold,
  required void Function(String line) write,
}) async {
  final ledger = database.writes;
  final settled = await ledger.settled(timeout: settleGrace);
  if (settled && ledger.uncertainCount == 0) {
    await releaseLease(ref, owner: operationId);
    return;
  }
  if (settled) {
    write(
      '[identity] lease kept op=$operationId: ${ledger.uncertainCount} '
      'write(s) ended without a confirmed outcome',
    );
    return;
  }
  write(
    '[identity] lease held op=$operationId: ${ledger.pendingCount} write(s) '
    'still unsettled',
  );
  try {
    await acquireLease(ref, owner: operationId, nowMs: nowMs(), ttl: hold);
  } on Object {
    // The lease keeps its own expiry.
  }
  _releaseWhenConfirmed(database, ref, operationId, hold);
}

/// Releases the lease in the background once every write on [database] has
/// finished with a known outcome, or gives up (the lease then runs out on its
/// own). Never throws.
void _releaseWhenConfirmed(
  RestDatabase database,
  RestDatabaseReference ref,
  String operationId,
  Duration wait,
) {
  unawaited(() async {
    try {
      final settled = await database.writes.settled(timeout: wait);
      if (settled && database.writes.uncertainCount == 0) {
        await releaseLease(ref, owner: operationId);
      }
    } on Object {
      // The lease runs out on its own.
    }
  }());
}
