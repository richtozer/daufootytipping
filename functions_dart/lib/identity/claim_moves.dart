import 'package:dart_functions/identity/claims.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// Which index a claim lives in.
enum ClaimKind {
  /// `/AliasIndex/{key}`, moved when a tipper renames.
  alias(paths.aliasIndexPath),

  /// `/LogonIndex/{hash}`, moved when the login address changes.
  logon(paths.logonIndexPath);

  const ClaimKind(this.indexPath);

  final String indexPath;
}

/// The target of a move is claimed by another tipper.
class ClaimMoveConflict implements Exception {
  const ClaimMoveConflict(this.kind);

  final ClaimKind kind;

  @override
  String toString() => 'ClaimMoveConflict(${kind.name})';
}

/// A claim being moved, as journalled at `/ClaimMoves/{tipperId}`. It records
/// the old claim and the new value up front, so a retry after a crash never has
/// to work out the old claim from a value that may already have changed.
class ClaimMove {
  const ClaimMove({
    required this.kind,
    required this.toKey,
    required this.toValue,
    required this.startedAtMs,
    this.fromKey,
  });

  final ClaimKind kind;

  /// The tipper's claim before the move, or null if it had none.
  final String? fromKey;
  final String toKey;

  /// The value that goes with the new claim: the alias as the tipper typed it,
  /// or the login address.
  final String toValue;
  final int startedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'fromKey': ?fromKey,
    'toKey': toKey,
    'toValue': toValue,
    'startedAtMs': startedAtMs,
  };

  static ClaimMove? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final kind = ClaimKind.values
        .where((candidate) => candidate.name == raw['kind'])
        .firstOrNull;
    final toKey = raw['toKey'];
    final toValue = raw['toValue'];
    final startedAt = raw['startedAtMs'];
    final fromKey = raw['fromKey'];
    if (kind == null ||
        toKey is! String ||
        toValue is! String ||
        startedAt is! num) {
      return null;
    }
    return ClaimMove(
      kind: kind,
      fromKey: fromKey is String ? fromKey : null,
      toKey: toKey,
      toValue: toValue,
      startedAtMs: startedAt.toInt(),
    );
  }
}

/// Moves a tipper's claim to [toKey] and writes the new value, recoverably. The
/// caller holds the tipper's lease.
///
/// 1. Finish any move already journalled for this tipper (a crashed earlier
///    attempt), so nothing is left half done.
/// 2. Only then work out the tipper's current claim (from its current alias or
///    login address) and journal this move. The old claim is never computed
///    before a pending move has been finished: that move may be about to change
///    the very value it is derived from, and a stale answer would release the
///    wrong claim and leak the right one.
/// 3. Claim the new key for the tipper. If another tipper holds it, drop the
///    journal and raise [ClaimMoveConflict]; nothing has changed.
/// 4. Write the new value.
/// 5. Release the old claim, only if this tipper owns it.
/// 6. Drop the journal.
///
/// A crash after any step is completed by the next call, because every step is
/// idempotent and the journal says what the move was. The tipper never loses
/// its old claim before the new one is held.
Future<void> performClaimMove(
  RestDatabase database, {
  required String tipperId,
  required ClaimKind kind,
  required String toKey,
  required String toValue,
  required ServerModeConfig mode,
  required int nowMs,
  Checkpoint? checkpoint,
}) async {
  final journal = database.ref('${paths.claimMovesPath}/$tipperId');
  final pending = ClaimMove.tryParse((await journal.once()).value);
  if (pending != null) {
    await _finish(database, tipperId, pending, mode, checkpoint);
  }
  final move = ClaimMove(
    kind: kind,
    fromKey: await currentClaimKey(database, tipperId, kind),
    toKey: toKey,
    toValue: toValue,
    startedAtMs: nowMs,
  );
  await journal.set(move.toJson());
  await checkpoint?.call('move:journalled');
  await _finish(database, tipperId, move, mode, checkpoint);
}

/// Completes a journalled move. Idempotent.
Future<void> _finish(
  RestDatabase database,
  String tipperId,
  ClaimMove move,
  ServerModeConfig mode,
  Checkpoint? checkpoint,
) async {
  final journal = database.ref('${paths.claimMovesPath}/$tipperId');
  if (move.toKey != move.fromKey) {
    final outcome = await claim(
      database.ref('${move.kind.indexPath}/${move.toKey}'),
      tipperId,
    );
    if (outcome == ClaimOutcome.heldByOther) {
      await journal.remove();
      throw ClaimMoveConflict(move.kind);
    }
  }
  await checkpoint?.call('move:claimed');

  await _writeValue(database, tipperId, move, mode);
  await checkpoint?.call('move:written');

  final fromKey = move.fromKey;
  if (fromKey != null && fromKey != move.toKey) {
    await release(database.ref('${move.kind.indexPath}/$fromKey'), tipperId);
  }
  await checkpoint?.call('move:released');

  await journal.remove();
}

Future<void> _writeValue(
  RestDatabase database,
  String tipperId,
  ClaimMove move,
  ServerModeConfig mode,
) async {
  switch (move.kind) {
    case ClaimKind.alias:
      // The alias is the tipper's public name in every mode.
      await database.ref('${paths.tippersPath}/$tipperId').update({
        'name': move.toValue,
      });
    case ClaimKind.logon:
      await database.ref('${paths.tipperPrivatePath}/$tipperId').update({
        'logon': move.toValue,
      });
      if (mode.mode.writesLegacyPublicShape) {
        await database.ref('${paths.tippersPath}/$tipperId').update({
          'logon': move.toValue,
        });
      }
  }
}

/// The claim a tipper holds now, derived from its current alias (the public
/// `name`) or login address (the private `logon`, else the public one). Null if
/// it has none that could be a key.
Future<String?> currentClaimKey(
  RestDatabase database,
  String tipperId,
  ClaimKind kind,
) async {
  switch (kind) {
    case ClaimKind.alias:
      final name =
          (await database.ref('${paths.tippersPath}/$tipperId/name').once())
              .value;
      return name is String && isValidAlias(name) ? aliasIndexKey(name) : null;
    case ClaimKind.logon:
      var logon =
          (await database
                  .ref('${paths.tipperPrivatePath}/$tipperId/logon')
                  .once())
              .value;
      logon ??=
          (await database.ref('${paths.tippersPath}/$tipperId/logon').once())
              .value;
      return logon is String && normaliseEmail(logon).isNotEmpty
          ? logonIndexKey(logon)
          : null;
  }
}
