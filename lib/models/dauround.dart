import 'package:daufootytipping/models/round_comp_scoring.dart';

class DAURound implements Comparable<DAURound> {
  String? dbkey;
  final int dAUroundNumber;
  List<String> gamesAsKeys = [];
  CompScore? compScore;
  RoundScores? roundScores;
  bool roundStarted;

  // counstructor
  DAURound({
    required this.dAUroundNumber,
    required this.gamesAsKeys,
    required this.roundStarted,
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
        roundStarted: false);
  }

  @override
  // method used to provide default sort for DAURounds in a List[]
  int compareTo(DAURound other) {
    return dAUroundNumber.compareTo(other.dAUroundNumber);
  }
}
