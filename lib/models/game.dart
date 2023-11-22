import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';

class Game {
  League league;
  Team homeTeam;
  Team awayTeam;
  String location;
  DateTime startTimeUTC;
  int round;
  int match;
  DAURound dAUround;
  int? homeTeamsScore; // will be null until official score is downloaded
  int? awayTeamScore; // will be null until official score is downloaded
  List<CroudSourcedScore> croudSourcedScores = [];
  int homeTeamOdds;
  int awayTeamOdds;
  GameResult gameResult = GameResult.z; // use 'z' until game result is known

  //constructor
  Game(
      this.league,
      this.homeTeam,
      this.awayTeam,
      this.location,
      this.startTimeUTC,
      this.round,
      this.match,
      this.dAUround,
      this.homeTeamOdds,
      this.awayTeamOdds);
}
