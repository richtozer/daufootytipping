import 'package:daufootytipping/models/game.dart';

double gameCardHeight = 128.0;
double leagueHeaderHeight = 56;
double emptyLeagueRoundHeight = 75;

enum RoundState {
  notStarted, // round is in the future
  started, // round is underway
  allGamesEnded, // round has finished and results known
  noGames, // this is an error state, all rounds should have games
}

class DAURound implements Comparable<DAURound> {
  final int dAUroundNumber;
  List<Game> games = [];
  RoundState roundState = RoundState.notStarted;
  DateTime roundStartDate;
  DateTime roundEndDate;
  DateTime? adminOverrideRoundStartDate;
  DateTime? adminOverrideRoundEndDate;

  // counstructor
  DAURound({
    required this.dAUroundNumber,
    required this.roundStartDate,
    required this.roundEndDate,
    this.adminOverrideRoundStartDate,
    this.adminOverrideRoundEndDate,
    this.games = const [],
  });

  // method to serialize DAURound to JSON
  Map<String, dynamic> toJsonForCompare() {
    return {
      'dAUroundNumber': dAUroundNumber,
      'roundStartDate': roundStartDate.toIso8601String(),
      'roundEndDate': roundEndDate.toIso8601String(),
      'adminOverrideRoundStartDate':
          adminOverrideRoundStartDate?.toIso8601String(),
      'adminOverrideRoundEndDate': adminOverrideRoundEndDate?.toIso8601String(),
    };
  }

  factory DAURound.fromJson(Map<String, dynamic> data, int roundNumber) {
    return DAURound(
      dAUroundNumber: roundNumber,
      roundStartDate: DateTime.parse(data['roundStartDate']),
      roundEndDate: DateTime.parse(data['roundEndDate']),
      adminOverrideRoundStartDate: data['adminOverrideRoundStartDate'] != null
          ? DateTime.parse(data['adminOverrideRoundStartDate'])
          : null,
      adminOverrideRoundEndDate: data['adminOverrideRoundEndDate'] != null
          ? DateTime.parse(data['adminOverrideRoundEndDate'])
          : null,
    );
  }

  // method returns admin overriden round start data if it exists, otherwise the round start date
  DateTime getRoundStartDate() {
    return adminOverrideRoundStartDate ?? roundStartDate;
  }

  // method returns admin overriden round end data if it exists, otherwise the round end date
  DateTime getRoundEndDate() {
    return adminOverrideRoundEndDate ?? roundEndDate;
  }

  @override
  // method used to provide default sort for DAURounds in a List[]
  int compareTo(DAURound other) {
    return dAUroundNumber.compareTo(other.dAUroundNumber);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DAURound &&
        other.dAUroundNumber == dAUroundNumber &&
        other.roundStartDate == roundStartDate &&
        other.roundEndDate == roundEndDate &&
        other.adminOverrideRoundStartDate == adminOverrideRoundStartDate &&
        other.adminOverrideRoundEndDate == adminOverrideRoundEndDate;
  }

  @override
  int get hashCode =>
      dAUroundNumber.hashCode ^
      roundStartDate.hashCode ^
      roundEndDate.hashCode ^
      adminOverrideRoundStartDate.hashCode ^
      adminOverrideRoundEndDate.hashCode;
}
