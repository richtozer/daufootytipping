import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';

double gameCardHeight = 128.0;
double leagueHeaderHeight = 56;
double emptyLeagueRoundHeight = 75;

enum RoundState {
  notStarted, // round is in the future
  started, // round is underway
  allGamesEnded, // round has finished and results known
}

class DAURound implements Comparable<DAURound> {
  final int dAUroundNumber;
  List<Game> games = [];
  CompScore? compScore;
  RoundScores? roundScores;
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

  int roundDisplayPixelHeight() {
    // count the number of nrl and afl games in this round
    int nrlGames = 0;
    int aflGames = 0;
    double totalPixelHeight = 0;
    for (var game in games) {
      if (game.league == League.nrl) {
        nrlGames++;
      } else {
        aflGames++;
      }
    }
    // calculate the height of the round
    // each round has a header of leagueHeaderHeight pixel high,
    // and a game card for each game of gameCardHeight pixels high
    // if the league has no games then the height is emptyLeagueRoundHeight

    if (nrlGames == 0) {
      totalPixelHeight += emptyLeagueRoundHeight;
    } else {
      totalPixelHeight += leagueHeaderHeight;
      totalPixelHeight += nrlGames * gameCardHeight;
    }

    if (aflGames == 0) {
      totalPixelHeight += emptyLeagueRoundHeight;
    } else {
      totalPixelHeight += leagueHeaderHeight;
      totalPixelHeight += aflGames * gameCardHeight;
    }

    return totalPixelHeight.toInt();
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
}
