import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:test/test.dart';

void main() {
  group('RoundScores', () {
    test('toJson should return a valid JSON map', () {
      final roundScores = RoundStats(
        roundNumber: 1,
        aflScore: 10,
        aflMaxScore: 20,
        aflMarginTips: 5,
        aflMarginUPS: 3,
        nrlScore: 15,
        nrlMaxScore: 25,
        nrlMarginTips: 7,
        nrlMarginUPS: 4,
        rank: 1,
        rankChange: 0,
        nrlTipsOutstanding: 0,
        aflTipsOutstanding: 0,
      );

      final json = roundScores.toJson();

      expect(json, {
        'nbr': 1,
        'aS': 10,
        'aMs': 20,
        'aMt': 5,
        'aMu': 3,
        'nS': 15,
        'nMs': 25,
        'nMt': 7,
        'nMu': 4,
        'nTo': 0,
        'aTo': 0,
      });
    });

    test('fromJson should create a valid RoundScores object', () {
      final json = {
        'nbr': 1,
        'aS': 10,
        'aMs': 20,
        'aMt': 5,
        'aMu': 3,
        'nS': 15,
        'nMs': 25,
        'nMt': 7,
        'nMu': 4,
        'nTo': 0,
        'aTo': 0,
      };

      final roundScores = RoundStats.fromJson(json);

      expect(roundScores.roundNumber, 1);
      expect(roundScores.aflScore, 10);
      expect(roundScores.aflMaxScore, 20);
      expect(roundScores.aflMarginTips, 5);
      expect(roundScores.aflMarginUPS, 3);
      expect(roundScores.nrlScore, 15);
      expect(roundScores.nrlMaxScore, 25);
      expect(roundScores.nrlMarginTips, 7);
      expect(roundScores.nrlMarginUPS, 4);
      expect(roundScores.rank, 0); // fromJson sets these to 0
      expect(roundScores.rankChange, 0);
      expect(roundScores.nrlTipsOutstanding, 0);
      expect(roundScores.aflTipsOutstanding, 0);
    });

    test('toCsv should return a valid CSV list', () {
      final roundScores = RoundStats(
        roundNumber: 1,
        aflScore: 10,
        aflMaxScore: 20,
        aflMarginTips: 5,
        aflMarginUPS: 3,
        nrlScore: 15,
        nrlMaxScore: 25,
        nrlMarginTips: 7,
        nrlMarginUPS: 4,
        rank: 1,
        rankChange: 0,
        nrlTipsOutstanding: 0,
        aflTipsOutstanding: 0,
      );

      final csv = roundScores.toCsv();

      expect(csv, [10, 20, 5, 3, 15, 25, 7, 4, 1, 0, 0, 0]);
    });

    test(
      'equality operator should compare two RoundScores objects correctly',
      () {
        final roundScores1 = RoundStats(
          roundNumber: 1,
          aflScore: 10,
          aflMaxScore: 20,
          aflMarginTips: 5,
          aflMarginUPS: 3,
          nrlScore: 15,
          nrlMaxScore: 25,
          nrlMarginTips: 7,
          nrlMarginUPS: 4,
          rank: 1,
          rankChange: 0,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        final roundScores2 = RoundStats(
          roundNumber: 1,
          aflScore: 10,
          aflMaxScore: 20,
          aflMarginTips: 5,
          aflMarginUPS: 3,
          nrlScore: 15,
          nrlMaxScore: 25,
          nrlMarginTips: 7,
          nrlMarginUPS: 4,
          rank: 1,
          rankChange: 0,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        final roundScores3 = RoundStats(
          roundNumber: 2,
          aflScore: 20,
          aflMaxScore: 30,
          aflMarginTips: 10,
          aflMarginUPS: 6,
          nrlScore: 30,
          nrlMaxScore: 40,
          nrlMarginTips: 14,
          nrlMarginUPS: 8,
          rank: 2,
          rankChange: 1,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        expect(roundScores1 == roundScores2, true);
        expect(roundScores1 == roundScores3, false);
      },
    );

    test(
      'hashCode should return the same value for equal RoundScores objects',
      () {
        final roundScores1 = RoundStats(
          roundNumber: 1,
          aflScore: 10,
          aflMaxScore: 20,
          aflMarginTips: 5,
          aflMarginUPS: 3,
          nrlScore: 15,
          nrlMaxScore: 25,
          nrlMarginTips: 7,
          nrlMarginUPS: 4,
          rank: 1,
          rankChange: 0,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        final roundScores2 = RoundStats(
          roundNumber: 1,
          aflScore: 10,
          aflMaxScore: 20,
          aflMarginTips: 5,
          aflMarginUPS: 3,
          nrlScore: 15,
          nrlMaxScore: 25,
          nrlMarginTips: 7,
          nrlMarginUPS: 4,
          rank: 1,
          rankChange: 0,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        expect(roundScores1.hashCode == roundScores2.hashCode, true);
      },
    );
  });
}
