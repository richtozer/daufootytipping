import 'package:dart_functions/rtdb/rest_database.dart';

/// What happened to an [acquireLease] call.
enum LeaseOutcome {
  /// Nobody held the lease; the caller now does.
  acquired,

  /// The caller already held it; the expiry was extended.
  renewed,

  /// Another owner's lease had expired and the caller replaced it.
  tookOverExpired,

  /// Another owner holds a live lease, or the stored value is not a lease.
  heldByOther,
}

/// A merge, reassign or delete lease on one tipper record, stored at
/// `/IdentityLocks/{tipperId}` as `"{owner}|{expiresAtMs}"`.
///
/// The owner is a unique **operation id** (see `newOperationId`), never an
/// admin's uid: two requests from the same admin are different operations and
/// must not both believe they hold the lease, and a worker that was taken over
/// can never be mistaken for its successor.
class Lease {
  const Lease({required this.owner, required this.expiresAtMs});

  final String owner;
  final int expiresAtMs;

  /// Parses a stored lease, or returns null if [raw] is not one.
  static Lease? tryParse(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final separator = raw.lastIndexOf('|');
    if (separator <= 0) {
      return null;
    }
    final expiresAtMs = int.tryParse(raw.substring(separator + 1));
    if (expiresAtMs == null) {
      return null;
    }
    return Lease(owner: raw.substring(0, separator), expiresAtMs: expiresAtMs);
  }

  String encode() => '$owner|$expiresAtMs';

  /// A lease is live up to, and not including, its expiry instant.
  bool isExpiredAt(int nowMs) => nowMs >= expiresAtMs;
}

/// Takes the lease at [ref] for [owner] for [ttl].
///
/// An expired lease is replaced by a compare-and-set against its exact stored
/// value, so when several contenders find the same stale lease only one wins.
/// A stored value that is not a lease is never replaced; the audit job reports
/// it. [nowMs] is the caller's clock, passed in so tests control time.
Future<LeaseOutcome> acquireLease(
  RestDatabaseReference ref, {
  required String owner,
  required int nowMs,
  required Duration ttl,
}) async {
  _requireOwner(owner);
  if (ttl <= Duration.zero) {
    throw ArgumentError.value(ttl, 'ttl', 'must be positive');
  }
  final wanted = Lease(owner: owner, expiresAtMs: nowMs + ttl.inMilliseconds);
  var outcome = LeaseOutcome.heldByOther;
  final result = await ref.atomicUpdate((current) {
    if (current == null) {
      outcome = LeaseOutcome.acquired;
      return wanted.encode();
    }
    final held = Lease.tryParse(current);
    if (held == null) {
      outcome = LeaseOutcome.heldByOther;
      return keepCurrentValue;
    }
    if (held.owner == owner) {
      outcome = LeaseOutcome.renewed;
      return wanted.encode();
    }
    if (held.isExpiredAt(nowMs)) {
      outcome = LeaseOutcome.tookOverExpired;
      return wanted.encode();
    }
    outcome = LeaseOutcome.heldByOther;
    return keepCurrentValue;
  });
  return result.applied ? outcome : LeaseOutcome.heldByOther;
}

/// Whether [owner] holds a live lease at [ref] at [nowMs].
///
/// A worker that may have paused (a slow request, a throttled instance) calls
/// this before every step. If another operation took the lease over, or it
/// expired, or it was released, the answer is false and the worker must stop.
/// Because owners are unique operation ids, this stays false even after the
/// successor has finished and released the lease or a third operation has
/// acquired it. It narrows the window; each step's own write must still be a
/// compare-and-set on the exact value it expects, so a stale step cannot
/// overwrite what its successor did.
Future<bool> holdsLease(
  RestDatabaseReference ref, {
  required String owner,
  required int nowMs,
}) async {
  _requireOwner(owner);
  final held = Lease.tryParse((await ref.once()).value);
  return held != null && held.owner == owner && !held.isExpiredAt(nowMs);
}

/// Releases the lease at [ref] if [owner] holds it. Returns whether it did.
Future<bool> releaseLease(
  RestDatabaseReference ref, {
  required String owner,
}) async {
  _requireOwner(owner);
  final result = await ref.atomicUpdate((current) {
    final held = Lease.tryParse(current);
    return held != null && held.owner == owner ? null : keepCurrentValue;
  });
  return result.applied;
}

void _requireOwner(String owner) {
  if (owner.isEmpty || owner.contains('|')) {
    throw ArgumentError.value(
      owner,
      'owner',
      'must be non-empty and must not contain "|"',
    );
  }
}
