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
    });

    test(
        'returns NRL GameResult.e when homeTeamScore + margin is less than awayTeamScore',
        () {
      final scoring = Scoring(homeTeamScore: 1, awayTeamScore: 14);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.e);
    });

    test(
        'returns NRL GameResult.b when homeTeamScore is greater than awayTeamScore',
        () {
      final scoring = Scoring(homeTeamScore: 10, awayTeamScore: 9);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.b);
    });

    test(
        'returns NRL GameResult.d when homeTeamScore is less than awayTeamScore',
        () {
      final scoring = Scoring(homeTeamScore: 9, awayTeamScore: 10);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.d);
    });

    test('returns NRL GameResult.c when homeTeamScore equals awayTeamScore',
        () {
      final scoring = Scoring(homeTeamScore: 10, awayTeamScore: 10);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.c);
    });

    test('returns NRL GameResult.z when homeTeamScore is null and no crowd-sourced scores', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: 10);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
    });
    test('returns NRL GameResult.z when awayTeamScore is null and no crowd-sourced scores', () {
      final scoring = Scoring(homeTeamScore: 10, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
    });
    test('returns NRL GameResult.z when both scores are null', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
    });

    // New tests for partial live scoring with crowd-sourced scores
    test('returns NRL GameResult.a when homeTeamScore from crowd-sourced and awayTeamScore assumed 0', () {
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
        croudSourcedScores: [crowdScore],
      );
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.a);
    });

    test('returns NRL GameResult.e when awayTeamScore from crowd-sourced and homeTeamScore assumed 0', () {
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
        croudSourcedScores: [crowdScore],
      );
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.e);
    });

    test('returns NRL GameResult.b when homeTeamScore from crowd-sourced wins narrowly', () {
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
        croudSourcedScores: [crowdScore],
      );
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.b);
    });

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
        croudSourcedScores: [crowdScore],
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
    });

    test(
        'returns AFL GameResult.e when homeTeamScore + margin is less than awayTeamScore',
        () {
      final scoring = Scoring(homeTeamScore: 1, awayTeamScore: 32);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.e);
    });

    test(
        'returns AFL GameResult.b when homeTeamScore is greater than awayTeamScore',
        () {
      final scoring = Scoring(homeTeamScore: 10, awayTeamScore: 9);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.b);
    });

    test(
        'returns AFL GameResult.d when homeTeamScore is less than awayTeamScore',
        () {
      final scoring = Scoring(homeTeamScore: 9, awayTeamScore: 10);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.d);
    });

    test('returns AFL GameResult.c when homeTeamScore equals awayTeamScore',
        () {
      final scoring = Scoring(homeTeamScore: 10, awayTeamScore: 10);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.c);
    });

    test('returns AFL GameResult.z when homeTeamScore is null and no crowd-sourced scores', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: 10);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
    });
    test('returns AFL GameResult.z when awayTeamScore is null and no crowd-sourced scores', () {
      final scoring = Scoring(homeTeamScore: 10, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
    });
    test('returns AFL GameResult.z when both scores are null', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
    });

    // New tests for partial live scoring with crowd-sourced scores
    test('returns AFL GameResult.a when homeTeamScore from crowd-sourced and awayTeamScore assumed 0', () {
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
        croudSourcedScores: [crowdScore],
      );
      expect(scoring.getGameResultCalculated(League.afl), GameResult.a);
    });

    test('returns AFL GameResult.e when awayTeamScore from crowd-sourced and homeTeamScore assumed 0', () {
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
        croudSourcedScores: [crowdScore],
      );
      expect(scoring.getGameResultCalculated(League.afl), GameResult.e);
    });

    test('returns AFL GameResult.b when homeTeamScore from crowd-sourced wins narrowly', () {
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
        croudSourcedScores: [crowdScore],
      );
      expect(scoring.getGameResultCalculated(League.afl), GameResult.b);
    });

    test('prefers official AFL scores over crowd-sourced when both available', () {
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
        croudSourcedScores: [crowdScore],
      );
      expect(scoring.getGameResultCalculated(League.afl), GameResult.b);
    });
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
        croudSourcedScores: [crowdScore],
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
        croudSourcedScores: [earlierScore, laterScore],
      );
      expect(scoring.currentScore(ScoringTeam.home), 15);
      expect(scoring.currentScore(ScoringTeam.away), null);
    });

    test('returns null when no scores available', () {
      final scoring = Scoring(
        homeTeamScore: null,
        awayTeamScore: null,
        croudSourcedScores: null,
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
        croudSourcedScores: [crowdScore],
      );
      expect(scoring.currentScore(ScoringTeam.home), 12);
      expect(scoring.currentScore(ScoringTeam.away), null);
    });
  });

  group('getTipScoreCalculated', () {
    test('NRL Tip was A, result was A, score should be 4', () {
      var score =
          Scoring.getTipScoreCalculated(League.nrl, GameResult.a, GameResult.a);
      expect(score, equals(4));
    });

    test('NRL Tip was E, result was A, score should be -2', () {
      var score =
          Scoring.getTipScoreCalculated(League.nrl, GameResult.a, GameResult.e);
      expect(score, equals(-2));
    });

    test('NRL Tip was C, result was C, score should be 50', () {
      var score =
          Scoring.getTipScoreCalculated(League.nrl, GameResult.c, GameResult.c);
      expect(score, equals(50));
    });

    test('AFL Tip was C, result was C, score should be 50', () {
      var score =
          Scoring.getTipScoreCalculated(League.afl, GameResult.c, GameResult.c);
      expect(score, equals(20));
    });
  });
}
