import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/league.dart';

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
        return 'Home teams wins by 1-12 point margin';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away team wins by a 1-12 point margin';
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
        return 'Home teams wins by 1-30 point margin';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away team wins by a 1-30 point margin';
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

  static int calculateScore(
      League gameLeague, GameResult gameResult, GameResult tip) {
    //TODO consider moving these structures to firebase config
    final nrlScoreLookupTable = {
      GameResult.a: {
        GameResult.a: 4,
        GameResult.b: 2,
        GameResult.c: 0,
        GameResult.d: 0,
        GameResult.e: -2,
        GameResult.z: 0
      },
      GameResult.b: {
        GameResult.a: 1,
        GameResult.b: 2,
        GameResult.c: 0,
        GameResult.d: 0,
        GameResult.e: -2,
        GameResult.z: 0
      },
      GameResult.c: {
        GameResult.a: 0,
        GameResult.b: 1,
        GameResult.c: 50,
        GameResult.d: 1,
        GameResult.e: 0,
        GameResult.z: 0
      },
      GameResult.d: {
        GameResult.a: -2,
        GameResult.b: 0,
        GameResult.c: 0,
        GameResult.d: 2,
        GameResult.e: 1,
        GameResult.z: 0
      },
      GameResult.e: {
        GameResult.a: -2,
        GameResult.b: 0,
        GameResult.c: 0,
        GameResult.d: 2,
        GameResult.e: 4,
        GameResult.z: 0
      },
      GameResult.z: {
        GameResult.a: 0,
        GameResult.b: 0,
        GameResult.c: 0,
        GameResult.d: 0,
        GameResult.e: 0,
        GameResult.z: 0
      },
    };

    final aflScoreLookupTable = {
      GameResult.a: {
        GameResult.a: 4,
        GameResult.b: 2,
        GameResult.c: 0,
        GameResult.d: 0,
        GameResult.e: -2,
        GameResult.z: 0
      },
      GameResult.b: {
        GameResult.a: 1,
        GameResult.b: 2,
        GameResult.c: 0,
        GameResult.d: 0,
        GameResult.e: -2,
        GameResult.z: 0
      },
      GameResult.c: {
        GameResult.a: 0,
        GameResult.b: 1,
        GameResult.c: 20,
        GameResult.d: 1,
        GameResult.e: 0,
        GameResult.z: 0
      },
      GameResult.d: {
        GameResult.a: -2,
        GameResult.b: 0,
        GameResult.c: 0,
        GameResult.d: 2,
        GameResult.e: 1,
        GameResult.z: 0
      },
      GameResult.e: {
        GameResult.a: -2,
        GameResult.b: 0,
        GameResult.c: 0,
        GameResult.d: 2,
        GameResult.e: 4,
        GameResult.z: 0
      },
      GameResult.z: {
        GameResult.a: 0,
        GameResult.b: 0,
        GameResult.c: 0,
        GameResult.d: 0,
        GameResult.e: 0,
        GameResult.z: 0
      },
    };

    if (gameLeague == League.nrl) {
      return nrlScoreLookupTable[gameResult]![tip]!;
    } else {
      return aflScoreLookupTable[gameResult]![tip]!;
    }
  }
}
