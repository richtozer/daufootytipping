import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:intl/intl.dart';

enum GameState {
  notStarted, // game start time is in the future
  startingSoon, // game start time is within 14 hours
  startedResultKnown, // game start time is in the past, and 'official' fixture game score is known
  startedResultNotKnown, // game start time is in the past, but 'official' fixture  game score is not known
}

class Game implements Comparable<Game> {
  final String dbkey;
  final League league;
  Team homeTeam;
  Team awayTeam;
  final String location;
  final DateTime startTimeUTC;
  final int fixtureRoundNumber;
  final int fixtureMatchNumber;
  Scoring? scoring; // this should be null until game kickoff
  GameStatsEntry? gameStats;
  static final double gameCardHeight = 128;
  static final double teamVersusTeamWidth = 135;
  //constructor
  Game({
    required this.dbkey,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.location,
    required this.startTimeUTC,
    required this.fixtureRoundNumber,
    required this.fixtureMatchNumber,
    this.scoring,
  });

  // this getter will return the gamestate based on the current time and the game start time
  // the possible gameStates are: 'notStarted', 'startingSoon' , 'startedResultNotKnown', 'startedResultKnown'
  GameState get gameState {
    final now = DateTime.now().toUtc();
    if (now.isBefore(startTimeUTC)) {
      if (now.isAfter(startTimeUTC.subtract(const Duration(hours: 14)))) {
        return GameState.startingSoon;
      }
      return GameState.notStarted;
    } else if (now.isAfter(startTimeUTC.add(const Duration(hours: 2))) &&
        scoring != null &&
        scoring?.awayTeamScore != null &&
        scoring?.homeTeamScore != null) {
      return GameState.startedResultKnown;
    } else {
      return GameState.startedResultNotKnown;
    }
  }

  DAURound? getDAURound(DAUComp daucomp) {
    for (var dauRound in daucomp.daurounds) {
      if (_isDateInRound(startTimeUTC, dauRound)) {
        return dauRound;
      }
    }
    log(
      'Game.getDAURound: WARNING, no DAURound found for game $dbkey. Check that the game start time is within the round start and end dates.',
    );
    return null;
  }

  bool isGameInRound(DAURound round) {
    return _isDateInRound(startTimeUTC, round);
  }

  bool _isDateInRound(DateTime date, DAURound round) {
    final startDate = round.getRoundStartDate();
    final endDate = round.getRoundEndDate();

    return ((date.isAfter(startDate) || date.isAtSameMomentAs(startDate)) &&
        (date.isBefore(endDate) || date.isAtSameMomentAs(endDate)));
  }

  double getGameResultPercentage(GameResult gameResult) {
    if (scoring == null) {
      return 0.0;
    }
    switch (gameResult) {
      case GameResult.a:
        return gameStats!.percentageTippedAwayMargin ?? 0.0;
      case GameResult.b:
        return gameStats!.percentageTippedHome ?? 0.0;
      case GameResult.c:
        return gameStats!.percentageTippedDraw ?? 0.0;
      case GameResult.d:
        return gameStats!.percentageTippedAway ?? 0.0;
      case GameResult.e:
        return gameStats!.percentageTippedAwayMargin ?? 0.0;
      default:
        return 0.0;
    }
  }

  Map<String, dynamic> toJson() => {
    'League': league.name,
    'HomeTeam': homeTeam.dbkey.substring(4),
    'AwayTeam': awayTeam.dbkey.substring(4),
    'Location': location,
    'DateUtc':
        '${DateFormat('yyyy-MM-dd HH:mm:ss').format(startTimeUTC).toString()}Z',
    'RoundNumber': fixtureRoundNumber,
    'MatchNumber': fixtureMatchNumber,
    'HomeTeamScore': (scoring != null) ? scoring!.homeTeamScore : null,
    "AwayTeamScore": (scoring != null) ? scoring!.awayTeamScore : null,
  };

  factory Game.fromJson(
    String dbkey,
    Map<String, dynamic> data,
    homeTeam,
    awayTeam,
  ) {
    //use the left 3 chars of the dbkey to determine the league
    final league = League.values.byName(dbkey.substring(0, 3));
    return Game(
      dbkey:
          '${league.name}-${data['RoundNumber'].toString().padLeft(2, '0')}-${data['MatchNumber'].toString().padLeft(3, '0')}', //create a unique based on league, round number and match number. Pad the numbers so they sort correctly in the firebase console
      league: league,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      location: data['Location'] ?? '',
      startTimeUTC: DateTime.parse(data['DateUtc']),
      fixtureRoundNumber: data['RoundNumber'] ?? 0,
      fixtureMatchNumber: data['MatchNumber'] ?? 0,
    );
  }

  @override
  // method used to provide default sort for Games in a List[]
  int compareTo(Game other) {
    // sort by league descending i.e. NRL first, and then by match number
    // this is to support legacy round sorting
    if (league == other.league) {
      //sort by game start time first, then by match number
      if (startTimeUTC.isBefore(other.startTimeUTC)) {
        return -1;
      } else if (startTimeUTC.isAfter(other.startTimeUTC)) {
        return 1;
      } else {
        return fixtureMatchNumber.compareTo(other.fixtureMatchNumber);
      }
    } else {
      return league.index.compareTo(other.league.index);
    }
  }
}
