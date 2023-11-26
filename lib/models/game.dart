import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';

class Game {
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

  factory Game.fromJson(Map<String, dynamic> data, String key) {
    return Game(
      dbkey: key,
      league: League.values.byName(data['league']),
      homeTeam: data['homeTeam'],
      awayTeam: data['awayTeam'],
      location: data['location'],
      startTimeUTC: data['startTimeUTC'],
      roundNumber: data['roundNumber'],
      matchNumber: data['matchNumber'],
      dauRoundkey: data['dauRoundkey'],
      scoring: data['scoring'],
    );
  }

  Map toJson() => {
        'league': league.name,
        'homeTeam': homeTeam.dbkey,
        'awayTeam': awayTeam.dbkey,
        'location': location,
        'startTimeUTC': startTimeUTC.toString(),
        'roundNumber': roundNumber,
        'matchNumber': matchNumber,
        'dauRoundkey': dauRoundkey,
        'scoring': scoring,
      };
}
