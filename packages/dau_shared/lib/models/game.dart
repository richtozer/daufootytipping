import 'dart:developer';

import 'daucomp.dart';
import 'dauround.dart';
import 'scoring.dart';
import 'league.dart';
import '../services/kickoff_time.dart';
import 'scoring_gamestats.dart';
import 'team.dart';

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

  // time-injectable status evaluator
  GameState getGameState(DateTime now) {
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

  // backward-compatible getter
  GameState get gameState => getGameState(DateTime.now().toUtc());

  bool get hasOfficialScore =>
      scoring?.homeTeamScore != null && scoring?.awayTeamScore != null;

  /// Assigns a kickoff time to the round with the latest effective start at or
  /// before [kickoffUTC], subject to per-league cutoffs. When
  /// [boundFinalRoundByEndDate] is true (historical cross-comp lookup), a
  /// game past the final round's stored `lastGameKickOffUTC` returns null.
  static DAURound? roundForKickoff({
    required DateTime kickoffUTC,
    required League league,
    required List<DAURound> rounds,
    DateTime? aflCutoffUTC,
    DateTime? nrlCutoffUTC,
    bool boundFinalRoundByEndDate = false,
  }) {
    if (league == League.nrl &&
        nrlCutoffUTC != null &&
        kickoffUTC.isAfter(nrlCutoffUTC)) {
      return null;
    }
    if (league == League.afl &&
        aflCutoffUTC != null &&
        kickoffUTC.isAfter(aflCutoffUTC)) {
      return null;
    }
    if (rounds.isEmpty) {
      return null;
    }
    DAURound? matched;
    for (var i = rounds.length - 1; i >= 0; i--) {
      final round = rounds[i];
      if (!kickoffUTC.isBefore(round.getRoundStartDate())) {
        matched = round;
        break;
      }
    }
    if (matched == null) {
      return null;
    }
    if (boundFinalRoundByEndDate &&
        identical(matched, rounds.last) &&
        kickoffUTC.isAfter(rounds.last.lastGameKickOffUTC)) {
      return null;
    }
    return matched;
  }

  DAURound? getDAURound(DAUComp daucomp) {
    final matched = roundForKickoff(
      kickoffUTC: startTimeUTC,
      league: league,
      rounds: daucomp.daurounds,
      aflCutoffUTC: daucomp.aflRegularCompEndDateUTC,
      nrlCutoffUTC: daucomp.nrlRegularCompEndDateUTC,
    );
    if (matched == null) {
      log(
        'Game.getDAURound: WARNING, no DAURound found for game $dbkey. Check that the game start time is within the round boundaries and cutoffs.',
      );
    }
    return matched;
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
    dateUtcKey: dateUtcFromDateTime(startTimeUTC),
    dateUtcEpochMsKey: kickoffEpochMsFromDateUtc(
      dateUtcFromDateTime(startTimeUTC),
    ),
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
