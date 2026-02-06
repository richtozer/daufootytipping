import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/services/combined_rounds_service.dart';

class GameUpdate {
  final String dbkey;
  final String league; // 'nrl' or 'afl'
  final Map<String, dynamic> attributes;

  GameUpdate({required this.dbkey, required this.league, required this.attributes});
}

class FixtureImportApplier {
  const FixtureImportApplier();

  List<GameUpdate> buildGameUpdates(List<dynamic> nrlGames, List<dynamic> aflGames) {
    final updates = <GameUpdate>[];

    void addUpdates(List<dynamic> games, String league) {
      for (final gamejson in games.cast<Map<dynamic, dynamic>>()) {
        final dbkey =
            '$league-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        updates.add(
          GameUpdate(
            dbkey: dbkey,
            league: league,
            attributes: Map<String, dynamic>.from(gamejson),
          ),
        );
      }
    }

    addUpdates(nrlGames, 'nrl');
    addUpdates(aflGames, 'afl');
    return updates;
  }

  void tagGamesWithLeagueInPlace(List<dynamic> games, String league) {
    for (final game in games) {
      if (game is Map) {
        game['league'] = league;
      }
    }
  }

  List<DAURound>? computeCombinedRoundsIfMissing(DAUComp comp, List<dynamic> allGames) {
    if (comp.daurounds.isNotEmpty) return null;
    final roundsBuilder = CombinedRoundsService();
    return roundsBuilder.buildCombinedRounds(allGames);
  }
}

