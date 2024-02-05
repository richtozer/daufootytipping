import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/location_latlong.dart';
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
  LatLng? locationLatLong;
  final DateTime startTimeUTC;
  final int roundNumber;
  final int matchNumber;
  int combinedRoundNumber;
  Scoring? scoring; // this should be null until game kickoff

  set setCombinedRoundNumber(int value) {
    combinedRoundNumber = value;
  }

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
    this.combinedRoundNumber = 0,
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

  factory Game.fromJson(Map<String, dynamic> data, String key, Team homeTeam,
      Team awayTeam, LatLng? locationLatLong, Scoring? scoring) {
    return Game(
        dbkey: key,
        league: League.values.byName(data['league']),
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: data['location'],
        locationLatLong: locationLatLong,
        startTimeUTC: DateTime.parse(data['startTimeUTC']),
        roundNumber: data['roundNumber'],
        matchNumber: data['matchNumber'],
        combinedRoundNumber: data['combinedRoundNumber'] ?? 0,
        scoring: scoring);
  }

  Map<String, dynamic> toJson() => {
        'league': league.name,
        'homeTeamDbKey': homeTeam.dbkey,
        'awayTeamDbKey': awayTeam.dbkey,
        'location': location,
        'locationLatLong': locationLatLong?.toJson(),
        'startTimeUTC': startTimeUTC.toString(),
        'roundNumber': roundNumber,
        'matchNumber': matchNumber,
        'combinedRoundNumber': combinedRoundNumber,
        'scoring': (scoring != null) ? scoring!.toJson() : null,
      };

  @override
  // method used to provide default sort for Games in a List[]
  int compareTo(Game other) {
    return startTimeUTC
        .compareTo(other.startTimeUTC); //sort by the Game start time
  }
}
