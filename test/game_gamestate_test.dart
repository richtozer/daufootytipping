import 'package:flutter_test/flutter_test.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/scoring.dart';

void main() {
  group('Game.gameState', () {
    final nrlHome = Team(dbkey: 'nrl-h', name: 'NRL H', league: League.nrl);
    final nrlAway = Team(dbkey: 'nrl-a', name: 'NRL A', league: League.nrl);

    Game buildGame(DateTime start, {Scoring? scoring}) {
      return Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: nrlHome,
        awayTeam: nrlAway,
        location: 'Test',
        startTimeUTC: start.toUtc(),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
        scoring: scoring,
      );
    }

    test('notStarted when start in future (>14h)', () {
      final game = buildGame(DateTime.now().toUtc().add(const Duration(days: 2)));
      expect(game.gameState, GameState.notStarted);
    });

    test('startingSoon when within 14 hours', () {
      final game = buildGame(DateTime.now().toUtc().add(const Duration(hours: 1)));
      expect(game.gameState, GameState.startingSoon);
    });

    test('startedResultNotKnown when started but missing official scores', () {
      final game = buildGame(DateTime.now().toUtc().subtract(const Duration(hours: 1)));
      expect(game.gameState, GameState.startedResultNotKnown);
    });

    test('startedResultKnown when >2h past start and official scores exist', () {
      final game = buildGame(
        DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        scoring: Scoring(homeTeamScore: 10, awayTeamScore: 5),
      );
      expect(game.gameState, GameState.startedResultKnown);
    });
  });
}
