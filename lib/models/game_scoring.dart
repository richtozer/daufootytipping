import 'package:daufootytipping/models/crowdsourcedscore.dart';

enum GameResult { a, b, c, d, e, z }

class Scoring {
  int? homeTeamScore; // will be null until official score is downloaded
  int? awayTeamScore; // will be null until official score is downloaded
  CroudSourcedScore? homeTeamCroudSourcedScore1;
  CroudSourcedScore? homeTeamCroudSourcedScore2;
  CroudSourcedScore? homeTeamCroudSourcedScore3;
  CroudSourcedScore? awayTeamCroudSourcedScore1;
  CroudSourcedScore? awayTeamCroudSourcedScore2;
  CroudSourcedScore? awayTeamCroudSourcedScore3;
  GameResult gameResult = GameResult.z; // use 'z' until game result is known

  Scoring({this.homeTeamScore, this.awayTeamScore});
}
