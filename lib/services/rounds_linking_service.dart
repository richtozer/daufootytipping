import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';

class RoundsLinkingService {
  const RoundsLinkingService();

  List<Game> finalizeRoundsAndComputeUnassigned({
    required List<DAURound> rounds,
    required List<Game> allGames,
    DateTime? nrlCutoff,
    DateTime? aflCutoff,
  }) {
    // Set round state and counts for each round
    for (final round in rounds) {
      _initRoundState(round);

      round.nrlGameCount = round.games.where((g) => g.league == League.nrl).length;
      round.aflGameCount = round.games.where((g) => g.league == League.afl).length;
    }

    // Compute unassigned: all minus assigned
    final assignedKeys = <String>{
      for (final r in rounds) ...r.games.map((g) => g.dbkey),
    };
    final unassigned = allGames.where((g) => !assignedKeys.contains(g.dbkey)).toList();

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

  void _initRoundState(DAURound round) {
    if (round.games.isEmpty) {
      round.roundState = RoundState.noGames;
      return;
    }
    final anyStarted = round.games.any((game) =>
        game.gameState == GameState.startedResultKnown ||
        game.gameState == GameState.startedResultNotKnown);
    final allEnded = round.games.every((game) => game.gameState == GameState.startedResultKnown);
    if (allEnded) {
      round.roundState = RoundState.allGamesEnded;
    } else if (anyStarted) {
      round.roundState = RoundState.started;
    } else {
      round.roundState = RoundState.notStarted;
    }
  }
}

