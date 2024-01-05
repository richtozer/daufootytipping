import 'package:test/test.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';

void main() {
  group('Scoring', () {
    test('calculateScore for NRL league', () {
      expect(Scoring.calculateScore(League.nrl, GameResult.a, GameResult.a),
          equals(4));
      expect(Scoring.calculateScore(League.nrl, GameResult.a, GameResult.b),
          equals(2));
      expect(Scoring.calculateScore(League.nrl, GameResult.c, GameResult.c),
          equals(50));
      // Add more tests for different combinations of gameResult and tip
    });

    test('calculateScore for AFL league', () {
      expect(Scoring.calculateScore(League.afl, GameResult.a, GameResult.a),
          equals(4));
      expect(Scoring.calculateScore(League.afl, GameResult.a, GameResult.b),
          equals(2));
      // Add more tests for different combinations of gameResult and tip
    });
  });
}
