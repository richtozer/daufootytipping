import 'package:test/test.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';

void main() {
  group('getNRLGameResultCalculated', () {
    test(
      'returns NRL GameResult.a when homeTeamScore is greater than awayTeamScore + margin',
      () {
        final scoring = Scoring(homeTeamScore: 14, awayTeamScore: 1);
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.a);
      },
    );

    test(
      'returns NRL GameResult.e when homeTeamScore + margin is less than awayTeamScore',
      () {
        final scoring = Scoring(homeTeamScore: 1, awayTeamScore: 14);
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.e);
      },
    );

    test(
      'returns NRL GameResult.b when homeTeamScore is greater than awayTeamScore',
      () {
        final scoring = Scoring(homeTeamScore: 10, awayTeamScore: 9);
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.b);
      },
    );

    test(
      'returns NRL GameResult.d when homeTeamScore is less than awayTeamScore',
      () {
        final scoring = Scoring(homeTeamScore: 9, awayTeamScore: 10);
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.d);
      },
    );

    test(
      'returns NRL GameResult.c when homeTeamScore equals awayTeamScore',
      () {
        final scoring = Scoring(homeTeamScore: 10, awayTeamScore: 10);
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.c);
      },
    );

    test(
      'returns NRL GameResult.z when homeTeamScore is null and no crowd-sourced scores',
      () {
        final scoring = Scoring(homeTeamScore: null, awayTeamScore: 10);
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
      },
    );
    test(
      'returns NRL GameResult.z when awayTeamScore is null and no crowd-sourced scores',
      () {
        final scoring = Scoring(homeTeamScore: 10, awayTeamScore: null);
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
      },
    );
    test('returns NRL GameResult.z when both scores are null', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
    });

    // New tests for partial live scoring with crowd-sourced scores
    test(
      'returns NRL GameResult.a when homeTeamScore from crowd-sourced and awayTeamScore assumed 0',
      () {
        final crowdScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.home,
          'tipper1',
          14,
          false,
        );
        final scoring = Scoring(
          homeTeamScore: null,
          awayTeamScore: null,
          crowdSourcedScores: [crowdScore],
        );
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.a);
      },
    );

    test(
      'returns NRL GameResult.e when awayTeamScore from crowd-sourced and homeTeamScore assumed 0',
      () {
        final crowdScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.away,
          'tipper1',
          14,
          false,
        );
        final scoring = Scoring(
          homeTeamScore: null,
          awayTeamScore: null,
          crowdSourcedScores: [crowdScore],
        );
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.e);
      },
    );

    test(
      'returns NRL GameResult.b when homeTeamScore from crowd-sourced wins narrowly',
      () {
        final crowdScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.home,
          'tipper1',
          10,
          false,
        );
        final scoring = Scoring(
          homeTeamScore: null,
          awayTeamScore: null,
          crowdSourcedScores: [crowdScore],
        );
        expect(scoring.getGameResultCalculated(League.nrl), GameResult.b);
      },
    );

    test('prefers official scores over crowd-sourced when both available', () {
      final crowdScore = CrowdSourcedScore(
        DateTime.now().toUtc(),
        ScoringTeam.home,
        'tipper1',
        50, // This would suggest GameResult.a
        false,
      );
      final scoring = Scoring(
        homeTeamScore: 10, // Official score suggests GameResult.b
        awayTeamScore: 9,
        crowdSourcedScores: [crowdScore],
      );
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.b);
    });
  });

  group('getAFLGameResultCalculated', () {
    test(
      'returns AFL GameResult.a when homeTeamScore is greater than awayTeamScore + margin',
      () {
        final scoring = Scoring(homeTeamScore: 32, awayTeamScore: 1);
        expect(scoring.getGameResultCalculated(League.afl), GameResult.a);
      },
    );

    test(
      'returns AFL GameResult.e when homeTeamScore + margin is less than awayTeamScore',
      () {
        final scoring = Scoring(homeTeamScore: 1, awayTeamScore: 32);
        expect(scoring.getGameResultCalculated(League.afl), GameResult.e);
      },
    );

    test(
      'returns AFL GameResult.b when homeTeamScore is greater than awayTeamScore',
      () {
        final scoring = Scoring(homeTeamScore: 10, awayTeamScore: 9);
        expect(scoring.getGameResultCalculated(League.afl), GameResult.b);
      },
    );

    test(
      'returns AFL GameResult.d when homeTeamScore is less than awayTeamScore',
      () {
        final scoring = Scoring(homeTeamScore: 9, awayTeamScore: 10);
        expect(scoring.getGameResultCalculated(League.afl), GameResult.d);
      },
    );

    test(
      'returns AFL GameResult.c when homeTeamScore equals awayTeamScore',
      () {
        final scoring = Scoring(homeTeamScore: 10, awayTeamScore: 10);
        expect(scoring.getGameResultCalculated(League.afl), GameResult.c);
      },
    );

    test(
      'returns AFL GameResult.z when homeTeamScore is null and no crowd-sourced scores',
      () {
        final scoring = Scoring(homeTeamScore: null, awayTeamScore: 10);
        expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
      },
    );
    test(
      'returns AFL GameResult.z when awayTeamScore is null and no crowd-sourced scores',
      () {
        final scoring = Scoring(homeTeamScore: 10, awayTeamScore: null);
        expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
      },
    );
    test('returns AFL GameResult.z when both scores are null', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
    });

    // New tests for partial live scoring with crowd-sourced scores
    test(
      'returns AFL GameResult.a when homeTeamScore from crowd-sourced and awayTeamScore assumed 0',
      () {
        final crowdScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.home,
          'tipper1',
          40, // AFL margin is 39+
          false,
        );
        final scoring = Scoring(
          homeTeamScore: null,
          awayTeamScore: null,
          crowdSourcedScores: [crowdScore],
        );
        expect(scoring.getGameResultCalculated(League.afl), GameResult.a);
      },
    );

    test(
      'returns AFL GameResult.e when awayTeamScore from crowd-sourced and homeTeamScore assumed 0',
      () {
        final crowdScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.away,
          'tipper1',
          40, // AFL margin is 39+
          false,
        );
        final scoring = Scoring(
          homeTeamScore: null,
          awayTeamScore: null,
          crowdSourcedScores: [crowdScore],
        );
        expect(scoring.getGameResultCalculated(League.afl), GameResult.e);
      },
    );

    test(
      'returns AFL GameResult.b when homeTeamScore from crowd-sourced wins narrowly',
      () {
        final crowdScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.home,
          'tipper1',
          20, // Less than AFL margin of 39
          false,
        );
        final scoring = Scoring(
          homeTeamScore: null,
          awayTeamScore: null,
          crowdSourcedScores: [crowdScore],
        );
        expect(scoring.getGameResultCalculated(League.afl), GameResult.b);
      },
    );

    test(
      'prefers official AFL scores over crowd-sourced when both available',
      () {
        final crowdScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.home,
          'tipper1',
          100, // This would suggest GameResult.a
          false,
        );
        final scoring = Scoring(
          homeTeamScore: 80, // Official score suggests GameResult.b
          awayTeamScore: 75,
          crowdSourcedScores: [crowdScore],
        );
        expect(scoring.getGameResultCalculated(League.afl), GameResult.b);
      },
    );
  });

  group('currentScore with crowd-sourced scores', () {
    test('returns official score when available, ignoring crowd-sourced', () {
      final crowdScore = CrowdSourcedScore(
        DateTime.now().toUtc(),
        ScoringTeam.home,
        'tipper1',
        50, // Crowd-sourced score
        false,
      );
      final scoring = Scoring(
        homeTeamScore: 12, // Official score
        awayTeamScore: 8,
        crowdSourcedScores: [crowdScore],
      );
      expect(scoring.currentScore(ScoringTeam.home), 12);
      expect(scoring.currentScore(ScoringTeam.away), 8);
    });

    test('returns latest crowd-sourced score when official not available', () {
      final earlierScore = CrowdSourcedScore(
        DateTime.now().toUtc().subtract(Duration(minutes: 5)),
        ScoringTeam.home,
        'tipper1',
        10,
        false,
      );
      final laterScore = CrowdSourcedScore(
        DateTime.now().toUtc(),
        ScoringTeam.home,
        'tipper2',
        15, // Latest score
        false,
      );
      final scoring = Scoring(
        homeTeamScore: null,
        awayTeamScore: null,
        crowdSourcedScores: [earlierScore, laterScore],
      );
      expect(scoring.currentScore(ScoringTeam.home), 15);
      expect(scoring.currentScore(ScoringTeam.away), null);
    });

    test('returns null when no scores available', () {
      final scoring = Scoring(
        homeTeamScore: null,
        awayTeamScore: null,
        crowdSourcedScores: null,
      );
      expect(scoring.currentScore(ScoringTeam.home), null);
      expect(scoring.currentScore(ScoringTeam.away), null);
    });

    test('returns null when no crowd-sourced scores for specified team', () {
      final crowdScore = CrowdSourcedScore(
        DateTime.now().toUtc(),
        ScoringTeam.home, // Only home team has score
        'tipper1',
        12,
        false,
      );
      final scoring = Scoring(
        homeTeamScore: null,
        awayTeamScore: null,
        crowdSourcedScores: [crowdScore],
      );
      expect(scoring.currentScore(ScoringTeam.home), 12);
      expect(scoring.currentScore(ScoringTeam.away), null);
    });
  });

  group('margin boundary edge cases', () {
    test('NRL score at exact margin boundary (13) is result a, not b', () {
      // Home wins by exactly 13 = margin win (GameResult.a)
      final scoring = Scoring(homeTeamScore: 25, awayTeamScore: 12);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.a);
    });

    test('NRL score one below margin boundary (12) is result b, not a', () {
      // Home wins by exactly 12 = non-margin win (GameResult.b)
      final scoring = Scoring(homeTeamScore: 24, awayTeamScore: 12);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.b);
    });

    test(
      'NRL 1-point score shift at draw/win boundary causes 1-point tip points change',
      () {
        // Scenario: Tipper tipped Home (b). Score shifts from draw to
        // narrow home win. Their points change by 1 (1 -> 2).
        // This documents the exact edge case that can cause a production
        // game score shift: result c (draw) vs b (narrow home win).
        final draw = Scoring(homeTeamScore: 12, awayTeamScore: 12);
        final narrowWin = Scoring(homeTeamScore: 13, awayTeamScore: 12);

        expect(draw.getGameResultCalculated(League.nrl), GameResult.c);
        expect(narrowWin.getGameResultCalculated(League.nrl), GameResult.b);

        // Tip was Home (b): draw gives 1, narrow win gives 2 = delta of 1
        final scoreDraw = Scoring.getTipPointsCalculated(
          League.nrl,
          GameResult.c,
          GameResult.b,
        );
        final scoreNarrowWin = Scoring.getTipPointsCalculated(
          League.nrl,
          GameResult.b,
          GameResult.b,
        );

        expect(scoreDraw, 1);
        expect(scoreNarrowWin, 2);
        expect(scoreNarrowWin - scoreDraw, 1);
      },
    );

    test('AFL score at exact margin boundary (31) is result a, not b', () {
      final scoring = Scoring(homeTeamScore: 80, awayTeamScore: 49);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.a);
    });

    test('AFL score one below margin boundary (30) is result b, not a', () {
      final scoring = Scoring(homeTeamScore: 79, awayTeamScore: 49);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.b);
    });

    test(
      'crowd-sourced score crossing margin boundary changes result vs official score',
      () {
        // Crowd-sourced says home won by 14 (margin win)
        final crowdScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.home,
          'tipper1',
          14,
          true,
        );
        final crowdAwayScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.away,
          'tipper1',
          0,
          true,
        );

        // Without official scores, uses crowd-sourced: 14-0 = margin win
        final withCrowdOnly = Scoring(
          homeTeamScore: null,
          awayTeamScore: null,
          crowdSourcedScores: [crowdScore, crowdAwayScore],
        );
        expect(withCrowdOnly.getGameResultCalculated(League.nrl), GameResult.a);

        // Official scores arrive showing 14-2 = still margin win (diff=12, NOT margin)
        final withOfficial = Scoring(
          homeTeamScore: 14,
          awayTeamScore: 2,
          crowdSourcedScores: [crowdScore, crowdAwayScore],
        );
        expect(
          withOfficial.getGameResultCalculated(League.nrl),
          GameResult.b, // 12 < 13, so NOT margin win
        );
      },
    );

    test(
      'default tip (Away/d) gets 1 point when result is Draw (c), 0 when Home (b)',
      () {
        // Default tip is GameResult.d (Away). If game result shifts from
        // draw to narrow home win, the default tip points drops by 1.
        final scoreResultC = Scoring.getTipPointsCalculated(
          League.nrl,
          GameResult.c,
          GameResult.d,
        );
        final scoreResultB = Scoring.getTipPointsCalculated(
          League.nrl,
          GameResult.b,
          GameResult.d,
        );

        expect(scoreResultC, 1);
        expect(scoreResultB, 0);
        expect(scoreResultC - scoreResultB, 1);
      },
    );
  });

  group('getTipPointsCalculated', () {
    test('NRL Tip was A, result was A, points should be 4', () {
      var points = Scoring.getTipPointsCalculated(
        League.nrl,
        GameResult.a,
        GameResult.a,
      );
      expect(points, equals(4));
    });

    test('NRL Tip was E, result was A, points should be -2', () {
      var points = Scoring.getTipPointsCalculated(
        League.nrl,
        GameResult.a,
        GameResult.e,
      );
      expect(points, equals(-2));
    });

    test('NRL Tip was C, result was C, points should be 50', () {
      var points = Scoring.getTipPointsCalculated(
        League.nrl,
        GameResult.c,
        GameResult.c,
      );
      expect(points, equals(50));
    });

    test('AFL Tip was C, result was C, points should be 20', () {
      var points = Scoring.getTipPointsCalculated(
        League.afl,
        GameResult.c,
        GameResult.c,
      );
      expect(points, equals(20));
    });
  });
}
