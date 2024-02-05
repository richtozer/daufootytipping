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

  Scoring(
      {this.homeTeamScore,
      this.awayTeamScore,
      this.homeTeamCroudSourcedScore1,
      this.homeTeamCroudSourcedScore2,
      this.homeTeamCroudSourcedScore3,
      this.awayTeamCroudSourcedScore1,
      this.awayTeamCroudSourcedScore2,
      this.awayTeamCroudSourcedScore3});

  // tojson method
  Map<String, dynamic> toJson() {
    return {
      'homeTeamScore': homeTeamScore,
      'awayTeamScore': awayTeamScore,
      'homeTeamCroudSourcedScore1': homeTeamCroudSourcedScore1?.toJson(),
      'homeTeamCroudSourcedScore2': homeTeamCroudSourcedScore2?.toJson(),
      'homeTeamCroudSourcedScore3': homeTeamCroudSourcedScore3?.toJson(),
      'awayTeamCroudSourcedScore1': awayTeamCroudSourcedScore1?.toJson(),
      'awayTeamCroudSourcedScore2': awayTeamCroudSourcedScore2?.toJson(),
      'awayTeamCroudSourcedScore3': awayTeamCroudSourcedScore3?.toJson(),
      'gameResult': gameResult.toString(),
    };
  }

  // fromjson method
  factory Scoring.fromJson(Map<String, dynamic> data) {
    return Scoring(
      homeTeamScore: data['homeTeamScore'],
      awayTeamScore: data['awayTeamScore'],
      homeTeamCroudSourcedScore1: data['homeTeamCroudSourcedScore1'] != null
          ? CroudSourcedScore.fromJson(
              data['homeTeamCroudSourcedScore1'], data['tipper'])
          : null,
      homeTeamCroudSourcedScore2: data['homeTeamCroudSourcedScore2'] != null
          ? CroudSourcedScore.fromJson(
              data['homeTeamCroudSourcedScore2'], data['tipper'])
          : null,
      homeTeamCroudSourcedScore3: data['homeTeamCroudSourcedScore3'] != null
          ? CroudSourcedScore.fromJson(
              data['homeTeamCroudSourcedScore3'], data['tipper'])
          : null,
      awayTeamCroudSourcedScore1: data['awayTeamCroudSourcedScore1'] != null
          ? CroudSourcedScore.fromJson(
              data['awayTeamCroudSourcedScore1'], data['tipper'])
          : null,
      awayTeamCroudSourcedScore2: data['awayTeamCroudSourcedScore2'] != null
          ? CroudSourcedScore.fromJson(
              data['awayTeamCroudSourcedScore2'], data['tipper'])
          : null,
      awayTeamCroudSourcedScore3: data['awayTeamCroudSourcedScore3'] != null
          ? CroudSourcedScore.fromJson(
              data['awayTeamCroudSourcedScore3'], data['tipper'])
          : null,
    );
  }

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
