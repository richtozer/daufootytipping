import 'game.dart';
import 'league.dart';
import '../constants/paths.dart' as p;

enum RoundState {
  notStarted, // round is in the future
  started, // round is underway
  allGamesEnded, // round has finished and results known
  noGames, // this is an error state, all DAU combined rounds should have games
}

class DAURound implements Comparable<DAURound> {
  final int dAUroundNumber; // 1 based index round number
  List<Game> games = [];
  RoundState roundState = RoundState.notStarted;
  DateTime firstGameKickOffUTC;
  DateTime lastGameKickOffUTC;
  DateTime? adminOverrideRoundStartDate;

  int nrlGameCount = 0;
  int aflGameCount = 0;

  static final double leagueHeaderHeight = 103;
  static final double leagueHeaderEndedHeight = 104;
  static final double noGamesCardHeight = 75;

  // constructor
  DAURound({
    required this.dAUroundNumber,
    required this.firstGameKickOffUTC,
    required this.lastGameKickOffUTC,
    this.adminOverrideRoundStartDate,
    this.games = const [],
  });

  factory DAURound.fromJson(Map<String, dynamic> data, int roundNumber) {
    return DAURound(
      dAUroundNumber: roundNumber,
      firstGameKickOffUTC: DateTime.parse(data[p.roundStartDateKey]),
      lastGameKickOffUTC: DateTime.parse(data[p.roundEndDateKey]),
      adminOverrideRoundStartDate:
          data[p.adminOverrideRoundStartDateKey] != null
          ? DateTime.parse(data[p.adminOverrideRoundStartDateKey])
          : null,
    );
  }

  /// Effective round start boundary: 0:00 UTC on the UTC calendar date of
  /// [adminOverrideRoundStartDate] (if set) or [firstGameKickOffUTC]. Any
  /// time-of-day component on either value is ignored.
  DateTime getRoundStartDate() =>
      roundStartDateWithOverride(adminOverrideRoundStartDate);

  /// The effective start this round would have with [override] as its admin
  /// override (or none, when null). Used to tell whether an edit changed the
  /// round's start, since a timed override and 0:00 UTC on the same date are
  /// the same start.
  DateTime roundStartDateWithOverride(DateTime? override) {
    final raw = (override ?? firstGameKickOffUTC).toUtc();
    return DateTime.utc(raw.year, raw.month, raw.day);
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
        other.adminOverrideRoundStartDate == adminOverrideRoundStartDate;
  }

  @override
  int get hashCode =>
      dAUroundNumber.hashCode ^
      firstGameKickOffUTC.hashCode ^
      lastGameKickOffUTC.hashCode ^
      adminOverrideRoundStartDate.hashCode;
}
