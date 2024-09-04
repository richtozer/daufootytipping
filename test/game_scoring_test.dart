import 'package:test/test.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';

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

    test('returns NRL GameResult.z when homeTeamScore is null', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: 10);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
    });
    test('returns NRL GameResult.z when awayTeamScore is null', () {
      final scoring = Scoring(homeTeamScore: 10, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
    });
    test('returns NRL GameResult.z when both scores are null', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.nrl), GameResult.z);
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

    test('returns AFL GameResult.z when homeTeamScore is null', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: 10);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
    });
    test('returns AFL GameResult.z when awayTeamScore is null', () {
      final scoring = Scoring(homeTeamScore: 10, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
    });
    test('returns AFL GameResult.z when both scores are null', () {
      final scoring = Scoring(homeTeamScore: null, awayTeamScore: null);
      expect(scoring.getGameResultCalculated(League.afl), GameResult.z);
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
