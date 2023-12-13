import 'package:daufootytipping/models/crowdsourcedscore.dart';

enum GameResult { a, b, c, d, e, z }

extension GameResultString on GameResult {
  String get nrl {
    switch (this) {
      case GameResult.a:
        return 'Home 13+';
      case GameResult.b:
        return 'Home';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away';
      case GameResult.e:
        return 'Away 13+';
      case GameResult.z:
        return 'No Result';
    }
  }

  String get nrlTooltip {
    switch (this) {
      case GameResult.a:
        return 'Home team wins by 13 points or more';
      case GameResult.b:
        return 'Home teams wins by 0-12 point margin';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away team wins by a 0-12 point margin';
      case GameResult.e:
        return 'Away team wins by 13 points or more';
      case GameResult.z:
        return 'No Result';
    }
  }

  String get afl {
    switch (this) {
      case GameResult.a:
        return 'Home 31+';
      case GameResult.b:
        return 'Home';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away';
      case GameResult.e:
        return 'Away 31+';
      case GameResult.z:
        return 'No Result';
    }
  }

  String get aflTooltip {
    switch (this) {
      case GameResult.a:
        return 'Home team wins by 31 points or more';
      case GameResult.b:
        return 'Home teams wins by 0-30 point margin';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away team wins by a 0-30 point margin';
      case GameResult.e:
        return 'Away team wins by 31 points or more';
      case GameResult.z:
        return 'No Result';
    }
  }
}

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
