import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';

enum GameState {
  notStarted,
  resultKnown,
  resultNotKnown,
}

class Game implements Comparable<Game> {
  final String dbkey;
  final League league;
  final Team homeTeam;
  final Team awayTeam;
  final String location;
  final DateTime startTimeUTC;
  final int roundNumber;
  final int matchNumber;
  String? dauRoundkey;
  Scoring? scoring; // this should be null until game kickoff

  //constructor
  Game({
    required this.dbkey,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.location,
    required this.startTimeUTC,
    required this.roundNumber,
    required this.matchNumber,
    this.dauRoundkey,
    this.scoring,
  });

  // this getter will return the gamestate based on the current time and the game start time
  // the possible gamestates are: 'notStarted', 'resultKnown', 'resultNotKnown'
  GameState get gameState {
    final now = DateTime.now().toUtc();
    if (now.isBefore(startTimeUTC)) {
      return GameState.notStarted;
    } else if (now.isAfter(startTimeUTC.add(const Duration(hours: 2))) &&
        scoring != null &&
        scoring?.awayTeamScore != null &&
        scoring?.homeTeamScore != null) {
      return GameState.resultKnown;
    } else {
      return GameState.resultNotKnown;
    }
  }

  factory Game.fromJson(
      Map<String, dynamic> data, String key, Team homeTeam, Team awayTeam) {
    return Game(
      dbkey: key,
      league: League.values.byName(data['league']),
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      location: data['location'],
      startTimeUTC: DateTime.parse(data['startTimeUTC']),
      roundNumber: data['roundNumber'],
      matchNumber: data['matchNumber'],
      dauRoundkey: data['dauRoundkey'],
      scoring: data['scoring'],
    );
  }

  Map toJson() => {
        'league': league.name,
        'homeTeamDbKey': homeTeam.dbkey,
        'awayTeamDbKey': awayTeam.dbkey,
        'location': location,
        'startTimeUTC': startTimeUTC.toString(),
        'roundNumber': roundNumber,
        'matchNumber': matchNumber,
        'dauRoundkey': dauRoundkey,
        'scoring': scoring,
      };

  @override
  // method used to provide default sort for Games in a List[]
  int compareTo(Game other) {
    return startTimeUTC
        .compareTo(other.startTimeUTC); //sort by the Game start time
  }
}
