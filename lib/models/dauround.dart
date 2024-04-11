import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';

enum RoundState {
  noGames, // round has no games
  notStarted, // round is in the future
  started, // round is underway
  allGamesEnded, // round has finished and results known
}

class DAURound implements Comparable<DAURound> {
  String? dbkey;
  final int dAUroundNumber;
  List<String> gamesAsKeys = []; //legacy - TODO: remove
  List<Game> games = [];
  CompScore? compScore;
  RoundScores? roundScores;
  RoundState roundState = RoundState.noGames;
  //DateTime roundStartDate;
  //DateTime roundEndDate;

  // counstructor
  DAURound({
    required this.dAUroundNumber,
    required this.gamesAsKeys,
  });

  // method to serialize DAURound to JSON
  Map<String, dynamic> toJsonForCompare() {
    return {
      'dAUroundNumber': dAUroundNumber,
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
