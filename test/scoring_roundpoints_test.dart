import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:test/test.dart';

void main() {
  group('RoundPoints', () {
    test('toJson should return a valid JSON map', () {
      final roundPoints = RoundStats(
        roundNumber: 1,
        aflPoints: 10,
        aflMaxPoints: 20,
        aflMarginTips: 5,
        aflMarginUPS: 3,
        nrlPoints: 15,
        nrlMaxPoints: 25,
        nrlMarginTips: 7,
        nrlMarginUPS: 4,
        rank: 1,
        rankChange: 0,
        nrlTipsOutstanding: 0,
        aflTipsOutstanding: 0,
      );

      final json = roundPoints.toJson();

      expect(json, {
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

    test('fromJson should create a valid RoundPoints object', () {
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

      final roundPoints = RoundStats.fromJson(json);

      expect(roundPoints.roundNumber, 1);
      expect(roundPoints.aflPoints, 10);
      expect(roundPoints.aflMaxPoints, 20);
      expect(roundPoints.aflMarginTips, 5);
      expect(roundPoints.aflMarginUPS, 3);
      expect(roundPoints.nrlPoints, 15);
      expect(roundPoints.nrlMaxPoints, 25);
      expect(roundPoints.nrlMarginTips, 7);
      expect(roundPoints.nrlMarginUPS, 4);
      expect(roundPoints.rank, 0); // fromJson sets these to 0
      expect(roundPoints.rankChange, 0);
      expect(roundPoints.nrlTipsOutstanding, 0);
      expect(roundPoints.aflTipsOutstanding, 0);
    });

    test('fromJson should fall back to the supplied round number', () {
      final json = {
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

      final roundPoints = RoundStats.fromJson(
        json,
        fallbackRoundNumber: 2,
      );

      expect(roundPoints.roundNumber, 2);
      expect(roundPoints.aflPoints, 10);
      expect(roundPoints.nrlPoints, 15);
    });

    test('toCsv should return a valid CSV list', () {
      final roundPoints = RoundStats(
        roundNumber: 1,
        aflPoints: 10,
        aflMaxPoints: 20,
        aflMarginTips: 5,
        aflMarginUPS: 3,
        nrlPoints: 15,
        nrlMaxPoints: 25,
        nrlMarginTips: 7,
        nrlMarginUPS: 4,
        rank: 1,
        rankChange: 0,
        nrlTipsOutstanding: 0,
        aflTipsOutstanding: 0,
      );

      final csv = roundPoints.toCsv();

      expect(csv, [10, 20, 5, 3, 15, 25, 7, 4, 1, 0, 0, 0]);
    });

    test(
      'equality operator should compare two RoundPoints objects correctly',
      () {
        final roundPoints1 = RoundStats(
          roundNumber: 1,
          aflPoints: 10,
          aflMaxPoints: 20,
          aflMarginTips: 5,
          aflMarginUPS: 3,
          nrlPoints: 15,
          nrlMaxPoints: 25,
          nrlMarginTips: 7,
          nrlMarginUPS: 4,
          rank: 1,
          rankChange: 0,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        final roundPoints2 = RoundStats(
          roundNumber: 1,
          aflPoints: 10,
          aflMaxPoints: 20,
          aflMarginTips: 5,
          aflMarginUPS: 3,
          nrlPoints: 15,
          nrlMaxPoints: 25,
          nrlMarginTips: 7,
          nrlMarginUPS: 4,
          rank: 1,
          rankChange: 0,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        final roundPoints3 = RoundStats(
          roundNumber: 2,
          aflPoints: 20,
          aflMaxPoints: 30,
          aflMarginTips: 10,
          aflMarginUPS: 6,
          nrlPoints: 30,
          nrlMaxPoints: 40,
          nrlMarginTips: 14,
          nrlMarginUPS: 8,
          rank: 2,
          rankChange: 1,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        expect(roundPoints1 == roundPoints2, true);
        expect(roundPoints1 == roundPoints3, false);
      },
    );

    test(
      'hashCode should return the same value for equal RoundPoints objects',
      () {
        final roundPoints1 = RoundStats(
          roundNumber: 1,
          aflPoints: 10,
          aflMaxPoints: 20,
          aflMarginTips: 5,
          aflMarginUPS: 3,
          nrlPoints: 15,
          nrlMaxPoints: 25,
          nrlMarginTips: 7,
          nrlMarginUPS: 4,
          rank: 1,
          rankChange: 0,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        final roundPoints2 = RoundStats(
          roundNumber: 1,
          aflPoints: 10,
          aflMaxPoints: 20,
          aflMarginTips: 5,
          aflMarginUPS: 3,
          nrlPoints: 15,
          nrlMaxPoints: 25,
          nrlMarginTips: 7,
          nrlMarginUPS: 4,
          rank: 1,
          rankChange: 0,
          nrlTipsOutstanding: 0,
          aflTipsOutstanding: 0,
        );

        expect(roundPoints1.hashCode == roundPoints2.hashCode, true);
      },
    );
  });
}
