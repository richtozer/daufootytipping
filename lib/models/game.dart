import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/location_latlong.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:intl/intl.dart';

enum GameState {
  notStarted, // game start time is in the future
  startingSoon, // game start time is within 14 hours
  startedResultKnown, // game start time is in the past, but 'official' fixture game score is known
  startedResultNotKnown, // game start time is in the past, but 'official' fixture  game score is not known
}

class Game implements Comparable<Game> {
  final String dbkey;
  final League league;
  Team homeTeam;
  Team awayTeam;
  final String location;
  LatLng? locationLatLong;
  final DateTime startTimeUTC;
  final int roundNumber;
  final int matchNumber;
  Scoring? scoring; // this should be null until game kickoff

  //constructor
  Game({
    required this.dbkey,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.location,
    this.locationLatLong,
    required this.startTimeUTC,
    required this.roundNumber,
    required this.matchNumber,
    this.scoring,
  });

  // this getter will return the gamestate based on the current time and the game start time
  // the possible gamestates are: 'notStarted', 'startingSoon' , 'resultKnown', 'resultNotKnown'
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

  // find the round in the supplied comp that this game belongs to
  DAURound getDAURound(DAUComp daucomp) {
    for (var dauRound in daucomp.daurounds!) {
      if ((startTimeUTC.isAfter(dauRound.roundStartDate) ||
              startTimeUTC.isAtSameMomentAs(dauRound.roundStartDate)) &&
          (startTimeUTC.isBefore(dauRound.roundEndDate) ||
              startTimeUTC.isAtSameMomentAs(dauRound.roundEndDate))) {
        return dauRound;
      }
    }
    throw Exception('Error in Game.getDAURound: no DAURound found');
  }

  // this method will return true is the game is in the supplied round
  bool isGameInRound(DAURound round) {
    if ((startTimeUTC.isAfter(round.roundStartDate) ||
            startTimeUTC.isAtSameMomentAs(round.roundStartDate)) &&
        (startTimeUTC.isBefore(round.roundEndDate) ||
            startTimeUTC.isAtSameMomentAs(round.roundEndDate))) {
      return true;
    } else {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'League': league.name,
        'HomeTeam': homeTeam.dbkey.substring(4),
        'AwayTeam': awayTeam.dbkey.substring(4),
        'Location': location,
        'DateUtc':
            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(startTimeUTC).toString()}Z',
        'RoundNumber': roundNumber,
        'MatchNumber': matchNumber,
        'HomeTeamScore': (scoring != null) ? scoring!.homeTeamScore : null,
        "AwayTeamScore": (scoring != null) ? scoring!.awayTeamScore : null,
      };

  factory Game.fromFixtureJson(
      String dbkey, Map<String, dynamic> data, homeTeam, awayTeam) {
    //use the left 3 chars of the dbkey to determine the league
    final league = League.values.byName(dbkey.substring(0, 3));
    return Game(
      dbkey:
          '${league.name}-${data['RoundNumber'].toString().padLeft(2, '0')}-${data['MatchNumber'].toString().padLeft(3, '0')}', //create a unique based on league, roune number and match number. Pad the numbers so they sort correctly in the firebase console
      league: league,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      location: data['Location'] ?? '',
      startTimeUTC: DateTime.parse(data['DateUtc']),
      roundNumber: data['RoundNumber'] ?? 0,
      matchNumber: data['MatchNumber'] ?? 0,
    );
  }

  @override
  // method used to provide default sort for Games in a List[]
  int compareTo(Game other) {
    return startTimeUTC
        .compareTo(other.startTimeUTC); //sort by the Game start time
  }
}
