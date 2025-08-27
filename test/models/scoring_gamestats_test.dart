import 'package:test/test.dart';

import 'package:daufootytipping/models/scoring_gamestats.dart';

void main() {
  group('GameStatsEntry', () {
    test('reducePrecision rounds to 3 decimals and preserves nulls', () {
      final e = GameStatsEntry(
        percentageTippedHomeMargin: 0.123456,
        percentageTippedHome: 1.23456,
        percentageTippedDraw: null,
        percentageTippedAway: 3.1415926,
        percentageTippedAwayMargin: 2.7182818,
        averageScore: 10.98765,
      );

      expect(e.percentageTippedHomeMargin, 0.123);
      expect(e.percentageTippedHome, 1.235);
      expect(e.percentageTippedDraw, isNull);
      expect(e.percentageTippedAway, 3.142);
      expect(e.percentageTippedAwayMargin, 2.718);
      expect(e.averageScore, 10.988);
    });

    test('toJson/fromJson maps all fields', () {
      final e = GameStatsEntry(
        percentageTippedHomeMargin: 0.1,
        percentageTippedHome: 0.2,
        percentageTippedDraw: 0.3,
        percentageTippedAway: 0.4,
        percentageTippedAwayMargin: 0.5,
        averageScore: 1.0,
      );
      final json = e.toJson();
      final from = GameStatsEntry.fromJson(json);

      expect(from, equals(e));
    });

    test('equality holds when fields match', () {
      final a = GameStatsEntry(percentageTippedHome: 1.0);
      final b = GameStatsEntry(percentageTippedHome: 1.0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}

