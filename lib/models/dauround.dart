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
  //List<String> gamesAsKeys = []; //legacy - TODO: remove
  List<Game> games = [];
  CompScore? compScore;
  RoundScores? roundScores;
  RoundState roundState = RoundState.noGames;
  DateTime roundStartDate;
  DateTime roundEndDate;

  // counstructor
  DAURound({
    required this.dAUroundNumber,
    //required this.gamesAsKeys,
    required this.roundStartDate,
    required this.roundEndDate,
  });

  // method to serialize DAURound to JSON
  Map<String, dynamic> toJsonForCompare() {
    return {
      'dAUroundNumber': dAUroundNumber,
      //'roundGames': gamesAsKeys,
      'roundStartDate': roundStartDate.toIso8601String(),
      'roundEndDate': roundEndDate.toIso8601String(),
    };
  }

  factory DAURound.fromJson(List<String> gamesAsKeys, int roundNumber,
      DateTime roundStartDate, DateTime roundEndDate) {
    return DAURound(
      dAUroundNumber: roundNumber,
      //gamesAsKeys: gamesAsKeys,
      roundStartDate: roundStartDate,
      roundEndDate: roundEndDate,
    );
  }

  @override
  // method used to provide default sort for DAURounds in a List[]
  int compareTo(DAURound other) {
    return dAUroundNumber.compareTo(other.dAUroundNumber);
  }
}
