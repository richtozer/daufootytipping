import '../models/daucomp.dart';
import '../models/dauround.dart';
import '../models/game.dart';
import '../models/league.dart';

class SplitRoundGame {
  final Game game;
  final int assignedRoundNumber;
  final int homeRoundNumber;

  const SplitRoundGame({
    required this.game,
    required this.assignedRoundNumber,
    required this.homeRoundNumber,
  });
}

class RoundsLinkingService {
  const RoundsLinkingService();

  List<Game> finalizeRoundsAndComputeUnassigned({
    required List<DAURound> rounds,
    required List<Game> allGames,
    DateTime? nrlCutoff,
    DateTime? aflCutoff,
    DateTime? now,
  }) {
    final DateTime targetTime = now ?? DateTime.now().toUtc();
    // Set round state and counts for each round
    for (final round in rounds) {
      _initRoundState(round, targetTime);

      round.nrlGameCount = round.games
          .where((g) => g.league == League.nrl)
          .length;
      round.aflGameCount = round.games
          .where((g) => g.league == League.afl)
          .length;
    }

    // Compute unassigned: all minus assigned
    final assignedKeys = <String>{
      for (final r in rounds) ...r.games.map((g) => g.dbkey),
    };
    final unassigned = allGames
        .where((g) => !assignedKeys.contains(g.dbkey))
        .toList();

    // Remove games beyond cutoffs
    unassigned.removeWhere((game) {
      if (game.league == League.nrl && nrlCutoff != null) {
        return game.startTimeUTC.isAfter(nrlCutoff);
      }
      if (game.league == League.afl && aflCutoff != null) {
        return game.startTimeUTC.isAfter(aflCutoff);
      }
      return false;
    });

    return unassigned;
  }

  void _initRoundState(DAURound round, DateTime now) {
    if (round.games.isEmpty) {
      round.roundState = RoundState.noGames;
      return;
    }
    final anyStarted = round.games.any(
      (game) =>
          game.getGameState(now) == GameState.startedResultKnown ||
          game.getGameState(now) == GameState.startedResultNotKnown,
    );
    final allEnded = round.games.every(
      (game) => game.getGameState(now) == GameState.startedResultKnown,
    );
    if (allEnded) {
      round.roundState = RoundState.allGamesEnded;
    } else if (anyStarted) {
      round.roundState = RoundState.started;
    } else {
      round.roundState = RoundState.notStarted;
    }
  }

  /// Finds unstarted games within regular comp cutoffs whose fixture league
  /// round has its plurality of games in a different DAU round (tie broken
  /// toward the earlier DAU round).
  List<SplitRoundGame> computeSplitRoundGames({
    required List<DAURound> rounds,
    DateTime? nrlCutoff,
    DateTime? aflCutoff,
    DateTime? now,
  }) {
    final targetTime = (now ?? DateTime.now()).toUtc();
    final countsByLeagueRound =
        <({League league, int fixtureRound}), Map<int, int>>{};
    final assignedEntries = <({Game game, int assignedRoundNumber})>[];

    for (final round in rounds) {
      for (final game in round.games) {
        final key = (
          league: game.league,
          fixtureRound: game.fixtureRoundNumber,
        );
        final counts = countsByLeagueRound.putIfAbsent(key, () => <int, int>{});
        counts[round.dAUroundNumber] = (counts[round.dAUroundNumber] ?? 0) + 1;
        assignedEntries.add((
          game: game,
          assignedRoundNumber: round.dAUroundNumber,
        ));
      }
    }

    final homeRoundByLeagueRound = <({League league, int fixtureRound}), int>{};
    for (final entry in countsByLeagueRound.entries) {
      var bestRound = entry.value.keys.first;
      var bestCount = entry.value[bestRound]!;
      for (final countEntry in entry.value.entries) {
        if (countEntry.value > bestCount ||
            (countEntry.value == bestCount && countEntry.key < bestRound)) {
          bestRound = countEntry.key;
          bestCount = countEntry.value;
        }
      }
      homeRoundByLeagueRound[entry.key] = bestRound;
    }

    final result = <SplitRoundGame>[];
    for (final entry in assignedEntries) {
      final game = entry.game;
      final cutoff = game.league == League.nrl ? nrlCutoff : aflCutoff;
      if (cutoff != null && game.startTimeUTC.isAfter(cutoff)) {
        continue;
      }
      if (!targetTime.isBefore(game.startTimeUTC)) {
        continue;
      }
      final homeRound =
          homeRoundByLeagueRound[(
            league: game.league,
            fixtureRound: game.fixtureRoundNumber,
          )]!;
      if (entry.assignedRoundNumber != homeRound) {
        result.add(
          SplitRoundGame(
            game: game,
            assignedRoundNumber: entry.assignedRoundNumber,
            homeRoundNumber: homeRound,
          ),
        );
      }
    }

    result.sort((a, b) {
      final timeCmp = a.game.startTimeUTC.compareTo(b.game.startTimeUTC);
      if (timeCmp != 0) return timeCmp;
      return a.game.dbkey.compareTo(b.game.dbkey);
    });
    return result;
  }

  /// Validates an admin start-date override on [editedRoundNumber]. Returns a
  /// user-facing error message when rejected, or null when valid.
  String? validateRoundStartDateEdit({
    required DAUComp comp,
    required List<DAURound> rounds,
    required int editedRoundNumber,
    required DateTime newStartDateUTC,
    required List<Game> allGames,
  }) {
    final editedIndex = rounds.indexWhere(
      (r) => r.dAUroundNumber == editedRoundNumber,
    );
    if (editedIndex == -1) {
      return 'Round $editedRoundNumber was not found.';
    }

    if (editedIndex > 0) {
      final prevRound = rounds[editedIndex - 1];
      if (!newStartDateUTC.isAfter(prevRound.getRoundStartDate())) {
        return 'Round $editedRoundNumber start must be after Round ${prevRound.dAUroundNumber} start.';
      }
    }

    if (editedIndex + 1 < rounds.length) {
      final nextRound = rounds[editedIndex + 1];
      if (!newStartDateUTC.isBefore(nextRound.getRoundStartDate())) {
        return 'Round $editedRoundNumber start must be before Round ${nextRound.dAUroundNumber} start.';
      }
    }

    final candidateRounds = <DAURound>[
      for (var i = 0; i < rounds.length; i++)
        if (i == editedIndex)
          DAURound(
            dAUroundNumber: rounds[i].dAUroundNumber,
            firstGameKickOffUTC: rounds[i].firstGameKickOffUTC,
            lastGameKickOffUTC: rounds[i].lastGameKickOffUTC,
            adminOverrideRoundStartDate: newStartDateUTC,
          )
        else
          rounds[i],
    ];

    for (final game in allGames) {
      if (!game.hasOfficialScore) {
        continue;
      }
      final beforeRound = Game.roundForKickoff(
        kickoffUTC: game.startTimeUTC,
        league: game.league,
        rounds: rounds,
        aflCutoffUTC: comp.aflRegularCompEndDateUTC,
        nrlCutoffUTC: comp.nrlRegularCompEndDateUTC,
      );
      final afterRound = Game.roundForKickoff(
        kickoffUTC: game.startTimeUTC,
        league: game.league,
        rounds: candidateRounds,
        aflCutoffUTC: comp.aflRegularCompEndDateUTC,
        nrlCutoffUTC: comp.nrlRegularCompEndDateUTC,
      );
      if (beforeRound?.dAUroundNumber != afterRound?.dAUroundNumber) {
        return 'Cannot move scored game ${game.dbkey} from Round ${beforeRound?.dAUroundNumber ?? 'none'} to Round ${afterRound?.dAUroundNumber ?? 'none'}.';
      }
    }

    return null;
  }

  /// Validates a regular-comp cutoff edit for [league]. Returns a user-facing
  /// error message if it would exclude any officially scored game in [league]
  /// that is currently included under [oldCutoffUTC].
  String? validateLeagueCutoffEdit({
    required League league,
    DateTime? oldCutoffUTC,
    required DateTime? newCutoffUTC,
    required List<Game> allGames,
  }) {
    if (newCutoffUTC == null) {
      return null;
    }
    for (final game in allGames) {
      if (game.league != league || !game.hasOfficialScore) {
        continue;
      }
      final wasIncluded =
          oldCutoffUTC == null || !game.startTimeUTC.isAfter(oldCutoffUTC);
      if (wasIncluded && game.startTimeUTC.isAfter(newCutoffUTC)) {
        return '${league.name.toUpperCase()} cutoff cannot be earlier than scored game ${game.dbkey}.';
      }
    }
    return null;
  }
}
