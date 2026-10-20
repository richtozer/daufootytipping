import '../models/daucomp.dart';
import '../models/dauround.dart';
import 'combined_rounds_service.dart';
import 'kickoff_time.dart';

class GameUpdate {
  final String dbkey;
  final String league; // 'nrl' or 'afl'
  final Map<String, dynamic> attributes;

  GameUpdate({required this.dbkey, required this.league, required this.attributes});
}

class FixtureImportApplier {
  const FixtureImportApplier();

  static const Set<String> _persistedGameAttributeKeys = <String>{
    'League',
    'HomeTeam',
    'AwayTeam',
    'Location',
    'DateUtc',
    'RoundNumber',
    'MatchNumber',
    'HomeTeamScore',
    'AwayTeamScore',
  };

  List<GameUpdate> buildGameUpdates(List<dynamic> nrlGames, List<dynamic> aflGames) {
    final updates = <GameUpdate>[];

    void addUpdates(List<dynamic> games, String league) {
      for (final gamejson in games.cast<Map<dynamic, dynamic>>()) {
        final dbkey =
            '$league-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        final attributes = Map<String, dynamic>.fromEntries(
          gamejson.entries
              .where(
                (entry) =>
                    _persistedGameAttributeKeys.contains(entry.key.toString()),
              )
              .map(
                (entry) => MapEntry<String, dynamic>(
                  entry.key.toString(),
                  entry.value,
                ),
              ),
        );
        _addKickoffEpoch(dbkey, attributes);
        updates.add(
          GameUpdate(dbkey: dbkey, league: league, attributes: attributes),
        );
      }
    }

    addUpdates(nrlGames, 'nrl');
    addUpdates(aflGames, 'afl');
    return updates;
  }

  /// Writes the numeric kickoff beside `DateUtc`, in the same attribute set so
  /// that every writer puts them in the same database update. A `DateUtc` that
  /// cannot be read fails the whole import, naming the game, instead of writing
  /// a game whose kickoff the rules cannot use.
  void _addKickoffEpoch(String dbkey, Map<String, dynamic> attributes) {
    if (!attributes.containsKey(dateUtcKey)) {
      return;
    }
    final dateUtc = attributes[dateUtcKey];
    if (dateUtc is! String) {
      throw FormatException(
        'Game $dbkey has a DateUtc that is not text',
        dateUtc?.toString(),
      );
    }
    try {
      attributes[dateUtcEpochMsKey] = kickoffEpochMsFromDateUtc(dateUtc);
    } on FormatException catch (error) {
      throw FormatException(
        'Game $dbkey has an unusable DateUtc: ${error.message}',
        dateUtc,
      );
    }
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
