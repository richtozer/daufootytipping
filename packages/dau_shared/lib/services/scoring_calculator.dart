import '../models/game.dart';
import '../models/tipper.dart';
import '../models/tip.dart';
import '../models/scoring_roundstats.dart';
import '../models/scoring_gamestats.dart';
import '../models/league.dart';
import '../models/scoring.dart';

class ScoringCalculator {
  /// Pure deterministic mathematical calculator for round stats of a tipper.
  static RoundStats calculateRoundStatsForTipper({
    required int roundNumber,
    required List<Game> games,
    required Map<String, Tip> tipsByGameKey,
    required DateTime now,
  }) {
    final stats = RoundStats(
      roundNumber: roundNumber,
      aflPoints: 0,
      nrlPoints: 0,
      aflMaxPoints: 0,
      nrlMaxPoints: 0,
      aflMarginTips: 0,
      nrlMarginTips: 0,
      aflMarginUPS: 0,
      nrlMarginUPS: 0,
      aflTipsOutstanding: 0,
      nrlTipsOutstanding: 0,
      rank: 0,
      rankChange: 0,
    );

    for (var game in games) {
      Tip? tip = tipsByGameKey[game.dbkey];

      if (tip == null) {
        if (game.league == League.afl) {
          stats.aflTipsOutstanding++;
        } else {
          stats.nrlTipsOutstanding++;
        }
        continue;
      }

      int marginTip = (tip.tip == GameResult.a || tip.tip == GameResult.e) ? 1 : 0;
      if (game.league == League.afl) {
        stats.aflMarginTips += marginTip;
      } else {
        stats.nrlMarginTips += marginTip;
      }

      // Using the time-injected game state evaluator
      final gameStatus = game.getGameState(now);
      if (gameStatus != GameState.notStarted && gameStatus != GameState.startingSoon) {
        int points = Scoring.getTipPointsCalculated(
          game.league,
          game.scoring!.getGameResultCalculated(game.league),
          tip.tip,
        );
        int maxPoints = Scoring.getTipPointsCalculated(
          game.league,
          game.scoring!.getGameResultCalculated(game.league),
          game.scoring!.getGameResultCalculated(game.league),
        );

        if (game.league == League.afl) {
          stats.aflPoints += points;
          stats.aflMaxPoints += maxPoints;
        } else {
          stats.nrlPoints += points;
          stats.nrlMaxPoints += maxPoints;
        }

        int marginUPS = 0;
        if (game.scoring != null) {
          marginUPS =
              (game.scoring!.getGameResultCalculated(game.league) == GameResult.a && tip.tip == GameResult.a) ||
              (game.scoring!.getGameResultCalculated(game.league) == GameResult.e && tip.tip == GameResult.e)
              ? 1
              : 0;

          if (game.league == League.afl) {
            stats.aflMarginUPS += marginUPS;
          } else {
            stats.nrlMarginUPS += marginUPS;
          }
        }
      }
    }

    return stats;
  }

  /// Pure deterministic mathematical calculator for game tipped statistics.
  /// Preserves the historical behavior where:
  /// 1. Denominator for average points is the total count of the cohort (tipsForCohort.length), including null/untipped slots.
  /// 2. `averagePointsTipCount` is the count of non-null tips.
  static GameStatsEntry calculateGameStatsEntry({
    required List<Tipper> cohortTippers,
    required List<Tip?> tipsForCohort,
    required League league,
  }) {
    if (cohortTippers.length != tipsForCohort.length) {
      throw ArgumentError(
        'cohortTippers (length ${cohortTippers.length}) and tipsForCohort (length ${tipsForCohort.length}) '
        'lists must have the same length and be aligned.',
      );
    }

    double runningAveragePointsTotal = 0.0;
    int runningAveragePointsCountTips = 0;
    for (final Tip? tip in tipsForCohort) {
      runningAveragePointsCountTips++;
      runningAveragePointsTotal += tip?.getTipPointsCalculated() ?? 0;
    }

    final gameStatsEntry = GameStatsEntry(
      percentageTippedHomeMargin: 0.0,
      percentageTippedHome: 0.0,
      percentageTippedDraw: 0.0,
      percentageTippedAway: 0.0,
      percentageTippedAwayMargin: 0.0,
    );

    int totalTippers = cohortTippers.length;
    if (totalTippers > 0) {
      for (GameResult gameResult in GameResult.values) {
        int totalTippersTipped = 0;
        for (final Tip? tip in tipsForCohort) {
          if (tip?.tip == gameResult) {
            totalTippersTipped++;
          }
        }

        double val = totalTippersTipped / totalTippers;
        switch (gameResult) {
          case GameResult.a:
            gameStatsEntry.percentageTippedHomeMargin = gameStatsEntry.reducePrecision(val);
            break;
          case GameResult.b:
            gameStatsEntry.percentageTippedHome = gameStatsEntry.reducePrecision(val);
            break;
          case GameResult.c:
            gameStatsEntry.percentageTippedDraw = gameStatsEntry.reducePrecision(val);
            break;
          case GameResult.d:
            gameStatsEntry.percentageTippedAway = gameStatsEntry.reducePrecision(val);
            break;
          case GameResult.e:
            gameStatsEntry.percentageTippedAwayMargin = gameStatsEntry.reducePrecision(val);
            break;
          case GameResult.z:
            break;
        }
      }
    }

    if (runningAveragePointsCountTips > 0) {
      gameStatsEntry.averagePoints = gameStatsEntry.reducePrecision(
        runningAveragePointsTotal / runningAveragePointsCountTips,
      );
    } else {
      gameStatsEntry.averagePoints = 0.0;
    }
    gameStatsEntry.averagePointsTipCount = tipsForCohort.where((tip) => tip != null).length;

    return gameStatsEntry;
  }
}
