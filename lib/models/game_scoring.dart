import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/league.dart';

enum GameResult { a, b, c, d, e, z }

extension GameResultString on GameResult {
  String get nrl {
    switch (this) {
      case GameResult.a:
        return 'Home ${League.nrl.margin}+';
      case GameResult.b:
        return 'Home';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away';
      case GameResult.e:
        return 'Away ${League.nrl.margin}+';
      case GameResult.z:
        return 'No Result';
    }
  }

  String get nrlTooltip {
    switch (this) {
      case GameResult.a:
        return 'Home team wins by ${League.nrl.margin} points or more';
      case GameResult.b:
        return 'Home teams wins by 1-${League.nrl.margin - 1}  point margin';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away team wins by a 1-${League.nrl.margin - 1} point margin';
      case GameResult.e:
        return 'Away team wins by ${League.nrl.margin} points or more';
      case GameResult.z:
        return 'No Result';
    }
  }

  String get afl {
    switch (this) {
      case GameResult.a:
        return 'Home ${League.afl.margin}+';
      case GameResult.b:
        return 'Home';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away';
      case GameResult.e:
        return 'Away ${League.afl.margin}+';
      case GameResult.z:
        return 'No Result';
    }
  }

  String get aflTooltip {
    switch (this) {
      case GameResult.a:
        return 'Home team wins by ${League.afl.margin} points or more';
      case GameResult.b:
        return 'Home teams wins by 1-${League.afl.margin - 1} point margin';
      case GameResult.c:
        return 'Draw';
      case GameResult.d:
        return 'Away team wins by a 1-${League.afl.margin - 1} point margin';
      case GameResult.e:
        return 'Away team wins by ${League.afl.margin} points or more';
      case GameResult.z:
        return 'No Result';
    }
  }
}

class Scoring {
  int? homeTeamScore; // will be null until official score is downloaded
  int? awayTeamScore; // will be null until official score is downloaded
  List<CrowdSourcedScore>? croudSourcedScores;

  //constructor
  Scoring({
    this.homeTeamScore,
    this.awayTeamScore,
    this.croudSourcedScores,
  });

  int currentHomeScore() {
    //always return the official score from fixture if available
    if (homeTeamScore != null) {
      return homeTeamScore!;
    }
    //if official score is not available, return the latest crowd sourced score
    if (croudSourcedScores != null && croudSourcedScores!.isNotEmpty) {
      // find the latest crowd sourced score for ScroringTeam.home with the most
      //recent submittedTimeUTC timestamp
      final homeScores = croudSourcedScores!
          .where((element) => element.scoreTeam == ScoreTeam.home)
          .toList();
      if (homeScores.isNotEmpty) {
        homeScores
            .sort((a, b) => b.submittedTimeUTC.compareTo(a.submittedTimeUTC));
        return homeScores.first.interimScore;
      }
    }
    return 0;
  }

  int currentAwayScore() {
    //always return the official score from fixture if available
    if (awayTeamScore != null) {
      return awayTeamScore!;
    }
    //if official score is not available, return the latest crowd sourced score
    if (croudSourcedScores != null && croudSourcedScores!.isNotEmpty) {
      // find the latest crowd sourced score for ScroringTeam.away with the most
      //recent submittedTimeUTC timestamp
      final awayScores = croudSourcedScores!
          .where((element) => element.scoreTeam == ScoreTeam.away)
          .toList();
      if (awayScores.isNotEmpty) {
        awayScores
            .sort((a, b) => b.submittedTimeUTC.compareTo(a.submittedTimeUTC));
        return awayScores.first.interimScore;
      }
    }
    return 0;
  }

  bool didHomeTeamWin() {
    if (homeTeamScore != null && awayTeamScore != null) {
      return homeTeamScore! >= awayTeamScore!;
    }
    return false;
  }

  bool didAwayTeamWin() {
    if (homeTeamScore != null && awayTeamScore != null) {
      return awayTeamScore! >= homeTeamScore!;
    }
    return false;
  }

  //calcualte the game result based on homeTeamScore and awayTeamScore
  GameResult getGameResultCalculated(League league) {
    if (homeTeamScore != null && awayTeamScore != null) {
      switch (league) {
        case League.nrl:
          if (homeTeamScore! >= awayTeamScore! + League.nrl.margin) {
            return GameResult.a;
          } else if (homeTeamScore! + League.nrl.margin <= awayTeamScore!) {
            return GameResult.e;
          } else if (homeTeamScore! > awayTeamScore!) {
            return GameResult.b;
          } else if (homeTeamScore! < awayTeamScore!) {
            return GameResult.d;
          } else {
            return GameResult.c;
          }
        case League.afl:
          if (homeTeamScore! >= awayTeamScore! + League.afl.margin) {
            return GameResult.a;
          } else if (homeTeamScore! + League.afl.margin <= awayTeamScore!) {
            return GameResult.e;
          } else if (homeTeamScore! > awayTeamScore!) {
            return GameResult.b;
          } else if (homeTeamScore! < awayTeamScore!) {
            return GameResult.d;
          } else {
            return GameResult.c;
          }
      }
    }
    return GameResult.z;
  }

  // tojson method
  Map<String, dynamic> toJson() {
    return {
      'homeTeamScore': homeTeamScore,
      'awayTeamScore': awayTeamScore,
      'croudSourcedScores': croudSourcedScores?.map((x) => x.toJson()).toList(),
    };
  }

  // fromjson method
  factory Scoring.fromJson(Map<String, dynamic> data) {
    return Scoring(
      homeTeamScore: data['homeTeamScore'],
      awayTeamScore: data['awayTeamScore'],
      croudSourcedScores: data['croudSourcedScores'] != null
          ? List<CrowdSourcedScore>.from((data['croudSourcedScores'] as List)
              .where((x) => x != null)
              .map((x) => CrowdSourcedScore.fromJson(x as Map))
              .toList())
          : null,
    );
  }

  static int getTipScoreCalculated(
      League gameLeague, GameResult gameResult, GameResult tip) {
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
