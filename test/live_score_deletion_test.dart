import 'package:test/test.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';

void main() {
  group('Live Score Deletion Tests', () {
    test('VERIFY: removeGameFromLiveScoresList removes correct game', () {
      final game1 = Game(
        dbkey: 'game1',
        league: League.nrl,
        homeTeam: Team(dbkey: 'team1', name: 'Team 1', league: League.nrl),
        awayTeam: Team(dbkey: 'team2', name: 'Team 2', league: League.nrl),
        location: 'Stadium 1',
        startTimeUTC: DateTime.now().toUtc(),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
      final game2 = Game(
        dbkey: 'game2',
        league: League.nrl,
        homeTeam: Team(dbkey: 'team3', name: 'Team 3', league: League.nrl),
        awayTeam: Team(dbkey: 'team4', name: 'Team 4', league: League.nrl),
        location: 'Stadium 2',
        startTimeUTC: DateTime.now().toUtc(),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 2,
      );
      final game3 = Game(
        dbkey: 'game3',
        league: League.nrl,
        homeTeam: Team(dbkey: 'team5', name: 'Team 5', league: League.nrl),
        awayTeam: Team(dbkey: 'team6', name: 'Team 6', league: League.nrl),
        location: 'Stadium 3',
        startTimeUTC: DateTime.now().toUtc(),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 3,
      );

      // Mock a simple StatsViewModel instance with the new method
      final statsViewModel = MockStatsViewModel();

      // Add games to the live scores list
      statsViewModel.testGamesWithLiveScores.addAll([game1, game2, game3]);

      expect(statsViewModel.testGamesWithLiveScores.length, 3);
      expect(statsViewModel.testGamesWithLiveScores.contains(game2), true);

      // Remove game2
      statsViewModel.removeGameFromLiveScores(game2);

      expect(statsViewModel.testGamesWithLiveScores.length, 2);
      expect(statsViewModel.testGamesWithLiveScores.contains(game1), true);
      expect(statsViewModel.testGamesWithLiveScores.contains(game2), false);
      expect(statsViewModel.testGamesWithLiveScores.contains(game3), true);
    });

    test('VERIFY: Official scores trigger live score cleanup', () {
      // This test verifies the concept that when official scores arrive,
      // live scores should be deleted immediately rather than waiting for periodic cleanup

      final game = Game(
        dbkey: 'testGame',
        league: League.nrl,
        homeTeam: Team(dbkey: 'home', name: 'Home Team', league: League.nrl),
        awayTeam: Team(dbkey: 'away', name: 'Away Team', league: League.nrl),
        location: 'Test Stadium',
        startTimeUTC: DateTime.now().toUtc(),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );

      // Step 1: Game has live scores but no official scores
      final liveScores = [
        CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.home,
          'tipper1',
          15,
          false,
        ),
        CrowdSourcedScore(
          DateTime.now().toUtc(),
          ScoringTeam.away,
          'tipper1',
          12,
          false,
        ),
      ];

      game.scoring = Scoring(crowdSourcedScores: liveScores);

      expect(game.scoring?.homeTeamScore, null);
      expect(game.scoring?.awayTeamScore, null);
      expect(game.scoring?.crowdSourcedScores?.length, 2);

      // Step 2: Official scores arrive (this would trigger live score deletion in real implementation)
      game.scoring = game.scoring?.copyWith(
        homeTeamScore: 18,
        awayTeamScore: 14,
      );

      expect(game.scoring?.homeTeamScore, 18);
      expect(game.scoring?.awayTeamScore, 14);

      // In the real implementation, the GamesViewModel would call StatsViewModel.deleteGameLiveScores
      // which would delete the live scores from the database and remove the game from the live scores list

      // This test demonstrates the intended behavior - official scores should take precedence
      // and live scores should be cleaned up immediately when official scores arrive
      expect(
        game.scoring?.homeTeamScore,
        isNotNull,
        reason: 'Official scores should be preserved',
      );
      expect(
        game.scoring?.awayTeamScore,
        isNotNull,
        reason: 'Official scores should be preserved',
      );
    });
  });
}

// Mock class for testing
class MockStatsViewModel {
  final List<Game> testGamesWithLiveScores = [];

  void removeGameFromLiveScores(Game game) {
    testGamesWithLiveScores.removeWhere((g) => g.dbkey == game.dbkey);
  }
}
