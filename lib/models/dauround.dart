import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';

enum RoundState {
  notStarted, // round is in the future
  started, // round is underway
  allGamesEnded, // round has finished and results known
  noGames, // this is an error state, all DAU combnied rounds should have games
}

class DAURound implements Comparable<DAURound> {
  final int dAUroundNumber; // 1 based index round number
  List<Game> games = [];
  RoundState roundState = RoundState.notStarted;
  DateTime firstGameKickOffUTC;
  DateTime lastGameKickOffUTC;
  DateTime? adminOverrideRoundStartDate;
  DateTime? adminOverrideRoundEndDate;

  int nrlGameCount = 0;
  int aflGameCount = 0;

  static final double leagueHeaderHeight = 103;
  static final double leagueHeaderEndedHeight = 104;
  static final double noGamesCardheight = 75;

  // counstructor
  DAURound({
    required this.dAUroundNumber,
    required this.firstGameKickOffUTC,
    required this.lastGameKickOffUTC,
    this.adminOverrideRoundStartDate,
    this.adminOverrideRoundEndDate,
    this.games = const [],
  });

  factory DAURound.fromJson(Map<String, dynamic> data, int roundNumber) {
    return DAURound(
      dAUroundNumber: roundNumber,
      firstGameKickOffUTC: DateTime.parse(data['roundStartDate']),
      lastGameKickOffUTC: DateTime.parse(data['roundEndDate']),
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
    return adminOverrideRoundStartDate ?? firstGameKickOffUTC;
  }

  // method returns admin overriden round end data if it exists, otherwise the round end date
  DateTime getRoundEndDate() {
    return adminOverrideRoundEndDate ?? lastGameKickOffUTC;
  }

  // method to return games filtered on supplied league
  List<Game> getGamesForLeague(League league) {
    return games.where((game) => game.league == league).toList();
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
        other.firstGameKickOffUTC == firstGameKickOffUTC &&
        other.lastGameKickOffUTC == lastGameKickOffUTC &&
        other.adminOverrideRoundStartDate == adminOverrideRoundStartDate &&
        other.adminOverrideRoundEndDate == adminOverrideRoundEndDate;
  }

  @override
  int get hashCode =>
      dAUroundNumber.hashCode ^
      firstGameKickOffUTC.hashCode ^
      lastGameKickOffUTC.hashCode ^
      adminOverrideRoundStartDate.hashCode ^
      adminOverrideRoundEndDate.hashCode;
}
