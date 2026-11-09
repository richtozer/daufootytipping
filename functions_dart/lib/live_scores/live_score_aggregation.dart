import 'dart:io';

import 'package:dart_functions/live_scores/live_score_aggregate.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';

/// Where the aggregator's mode is kept: `/ServerConfig/liveScores/mode`. Closed to
/// every client by every ruleset (`/ServerConfig` is named in none of them).
final String liveScoresModePath = '${paths.serverConfigPath}/liveScores/mode';

/// What the aggregator is allowed to do (DESIGN-database-rules-phase4.md,
/// sections 3 and 5).
enum LiveScoresMode {
  /// Compute, compare with the `current` that is there, and log. **Writes
  /// nothing.** The default, and what anything unrecognised means.
  shadow,

  /// Write `current` from `history`. For use once no client can write it (after
  /// the R2 rules deploy).
  active,

  /// Write `current` while legacy clients still may. The same write as [active],
  /// enabled by the owner only as the fallback of section 3; the version guard
  /// and the convergence tests are what make it safe.
  compat,
}

/// The mode, failing safe: a missing, unreadable or unrecognised value is
/// [LiveScoresMode.shadow], which cannot change anything.
Future<LiveScoresMode> readLiveScoresMode(RestDatabase database) async {
  try {
    final value = (await database.ref(liveScoresModePath).once()).value;
    for (final mode in LiveScoresMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
  } on Object {
    // Fall through to the safe default.
  }
  return LiveScoresMode.shadow;
}

/// What a run came to.
enum AggregationOutcome {
  /// `history` has nothing usable in it.
  nothingToDo,

  /// The game has an official score, which overrides all of this. Nothing is
  /// touched.
  skippedOfficial,

  /// Shadow: the snapshot already there shows the same game.
  shadowMatch,

  /// Shadow: it does not. Logged; nothing is changed.
  shadowDiffers,

  /// `current` was written.
  written,

  /// `current` was left alone: it already shows this game, or a computation that
  /// saw at least as much history got there first.
  unchanged,

  /// `current` was written, an official score arrived while it was being
  /// written, and `current` was removed again.
  clearedForOfficial,
}

class AggregationResult {
  const AggregationResult(this.outcome, {this.differences = const <String>[]});

  final AggregationOutcome outcome;

  /// For [AggregationOutcome.shadowDiffers], how the two differ.
  final List<String> differences;
}

/// Derives a game's `current` snapshot from its `history`.
///
/// - An official score (both teams) overrides the crowd-sourced one, and the
///   fixture import clears the game's whole live node when it writes one, so a
///   game that has one is left alone. If one arrives *while* this is writing, the
///   snapshot is removed again, so an in-flight run cannot leave a stale one
///   behind.
/// - In `shadow` nothing is written; the result of the comparison with the
///   `current` already there is logged.
/// - In `active` and `compat` the write is a compare-and-set that is **skipped**
///   when `current` already shows this game (so an unchanged snapshot is never
///   rewritten, which would only trigger another rescore), or when it records
///   that it was computed from at least as much history (`basedOnCount`), so a
///   slow, older computation cannot undo a newer one. A snapshot a legacy client
///   wrote has no count and is simply replaced if it differs.
///
/// Every run recomputes from the whole of `history`, so duplicated, shuffled or
/// concurrent runs agree.
Future<AggregationResult> runLiveScoreAggregation({
  required RestDatabase database,
  required String compKey,
  required String gameKey,
  LiveScoresMode? mode,
  void Function(String line)? log,
  Future<void> Function()? beforeWrite,
}) async {
  final write = log ?? (String line) => stdout.writeln(line);
  if (!isValidRtdbKey(compKey) || !isValidRtdbKey(gameKey)) {
    throw ArgumentError('not a competition and game key: $compKey, $gameKey');
  }
  final effectiveMode = mode ?? await readLiveScoresMode(database);
  final live = database.ref(
    '${paths.statsPathRoot}/$compKey/${paths.liveScoresBackendRoot}/$gameKey',
  );

  if (await _hasOfficialScore(database, compKey, gameKey)) {
    write('[liveScores] skipped comp=$compKey game=$gameKey: official score');
    return const AggregationResult(AggregationOutcome.skippedOfficial);
  }

  final node = (await live.once()).value;
  final history = node is Map ? node['history'] : null;
  final current = node is Map ? node['current'] : null;
  final aggregate = computeLiveScoreAggregate(history);
  final snapshot = aggregate.snapshot;
  if (snapshot == null) {
    write(
      '[liveScores] nothing to do comp=$compKey game=$gameKey '
      'ignored=${aggregate.ignored}',
    );
    return const AggregationResult(AggregationOutcome.nothingToDo);
  }

  if (effectiveMode == LiveScoresMode.shadow) {
    final differences = liveScoreDifferences(current, snapshot);
    write(
      '[liveScores] shadow comp=$compKey game=$gameKey '
      'match=${differences.isEmpty} basedOn=${aggregate.basedOnCount} '
      'ignored=${aggregate.ignored} differences=${differences.join('; ')}',
    );
    return AggregationResult(
      differences.isEmpty
          ? AggregationOutcome.shadowMatch
          : AggregationOutcome.shadowDiffers,
      differences: differences,
    );
  }

  await beforeWrite?.call();
  final result = await live.child('current').atomicUpdate((existing) {
    if (liveScoreDifferences(existing, snapshot).isEmpty) {
      return keepCurrentValue;
    }
    final seen = existing is Map ? existing['basedOnCount'] : null;
    if (seen is num && seen >= aggregate.basedOnCount) {
      return keepCurrentValue;
    }
    return snapshot;
  });
  if (!result.applied) {
    write('[liveScores] unchanged comp=$compKey game=$gameKey');
    return const AggregationResult(AggregationOutcome.unchanged);
  }

  // An official score may have arrived while this was writing. The import clears
  // the live node in the same update that writes it, so a write that lands after
  // would leave a snapshot behind for a finished game.
  if (await _hasOfficialScore(database, compKey, gameKey)) {
    await live.child('current').remove();
    write('[liveScores] cleared comp=$compKey game=$gameKey: official arrived');
    return const AggregationResult(AggregationOutcome.clearedForOfficial);
  }
  write(
    '[liveScores] wrote comp=$compKey game=$gameKey '
    '${effectiveMode.name} basedOn=${aggregate.basedOnCount}',
  );
  return const AggregationResult(AggregationOutcome.written);
}

/// Whether the game has both official scores, as the scoring worker decides.
Future<bool> _hasOfficialScore(
  RestDatabase database,
  String compKey,
  String gameKey,
) async {
  final game =
      (await database.ref('${paths.gamesPathRoot}/$compKey/$gameKey').once())
          .value;
  return game is Map &&
      game['HomeTeamScore'] is num &&
      game['AwayTeamScore'] is num;
}
