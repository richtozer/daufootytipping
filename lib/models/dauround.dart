import 'package:daufootytipping/models/consolidatedscores.dart';

class DAURound implements Comparable<DAURound> {
  String? dbkey;
  final int dAUroundNumber;
  List<String> gamesAsKeys = [];
  ConsolidatedScores? consolidatedScores;

  // counstructor
  DAURound({
    required this.dAUroundNumber,
    required this.gamesAsKeys,
  });

  // method to serialize DAURound to JSON
  Map<String, dynamic> toJsonForCompare() {
    // Serialize Game list separately

/*     for (Game game in gamesAsKeys) {
      roundGamesJson.add(game.dbkey);
    } */
    return {
      'dAUroundNumber': dAUroundNumber,
      //'roundGames': roundGamesJson,
      'roundGames': gamesAsKeys,
    };
  }

  factory DAURound.fromJson(List<String> gamesAsKeys, int roundNumber) {
    return DAURound(
      dAUroundNumber: roundNumber,
      gamesAsKeys: gamesAsKeys,
    );
  }

  @override
  // method used to provide default sort for DAURounds in a List[]
  int compareTo(DAURound other) {
    return dAUroundNumber.compareTo(other.dAUroundNumber);
  }
}
