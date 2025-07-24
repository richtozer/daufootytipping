import 'package:test/test.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';

void main() {
  group('Scoring Race Condition Tests', () {
    test('SHOULD FAIL: Live scores arriving first should not prevent official score priority', () {
      // Simulate the race condition: live scores arrive first
      
      // Step 1: Live scores create the initial Scoring object
      final liveScore = CrowdSourcedScore(
        DateTime.now().toUtc(),
        ScoringTeam.home,
        'tipper1',
        20, // Live score suggests home team winning
        false,
      );
      
      // This simulates what _handleEventLiveScores does when game.scoring == null
      final scoringFromLiveUpdate = Scoring(
        homeTeamScore: null, // ❌ Live scores set official fields to null
        awayTeamScore: null, // ❌ This is the bug - should never touch these
        croudSourcedScores: [liveScore],
      );
      
      // Step 2: Official scores arrive later and try to update
      // This simulates what happens in fixture download
      final scoringWithOfficialScores = scoringFromLiveUpdate.copyWith(
        homeTeamScore: 12, // Official: Home team actually scored 12
        awayTeamScore: 15, // Official: Away team actually scored 15 (wins!)
      );
      
      // Step 3: Test that official scores take priority
      final homeScore = scoringWithOfficialScores.currentScore(ScoringTeam.home);
      final awayScore = scoringWithOfficialScores.currentScore(ScoringTeam.away);
      final result = scoringWithOfficialScores.getGameResultCalculated(League.nrl);
      
      // These should pass if priority logic works correctly
      expect(homeScore, 12, reason: 'Should use official home score');
      expect(awayScore, 15, reason: 'Should use official away score');
      expect(result, GameResult.d, reason: 'Away team wins 15-12, should be GameResult.d');
    });

    test('SHOULD FAIL: Live scores should not pollute official score fields', () {
      // This test exposes the architectural problem
      
      // Step 1: Create a game with no scoring data initially
      Scoring? gameScoring;
      
      // Step 2: Live scores arrive first (simulating _handleEventLiveScores)
      final liveScoreData = Scoring(
        homeTeamScore: null,
        awayTeamScore: null,
        croudSourcedScores: [
          CrowdSourcedScore(
            DateTime.now().toUtc(),
            ScoringTeam.home,
            'tipper1',
            25,
            false,
          ),
        ],
      );
      
      // This is the current problematic logic in _handleEventLiveScores
      gameScoring ??= liveScoreData; // ❌ PROBLEM: Assigns entire object with null official scores
      
      // Step 3: Official scores arrive later
      gameScoring = gameScoring.copyWith(
        homeTeamScore: 10,
        awayTeamScore: 8,
      );
      
      // Step 4: Verify clean separation
      expect(gameScoring.homeTeamScore, 10, reason: 'Official home score should be preserved');
      expect(gameScoring.awayTeamScore, 8, reason: 'Official away score should be preserved');
      expect(gameScoring.croudSourcedScores?.length, 1, reason: 'Live scores should be preserved');
      
      // This should work correctly due to priority logic, but the data structure is polluted
      final result = gameScoring.getGameResultCalculated(League.nrl);
      expect(result, GameResult.b, reason: 'Home wins 10-8, should be GameResult.b');
    });

    test('SHOULD FAIL: Official scores arriving first should not be overwritten by live scores', () {
      // Test the reverse scenario: official scores first, then live scores
      
      // Step 1: Official scores arrive first
      final gameScoring = Scoring(
        homeTeamScore: 21, // Official: Home team wins
        awayTeamScore: 18,
        croudSourcedScores: null,
      );
      
      // Step 2: Live scores arrive later with different values
      final liveScoreUpdate = Scoring(
        homeTeamScore: null, // Live scores should not touch these
        awayTeamScore: null,
        croudSourcedScores: [
          CrowdSourcedScore(
            DateTime.now().toUtc(),
            ScoringTeam.away,
            'tipper1',
            30, // Live score suggests away team winning (incorrect)
            false,
          ),
        ],
      );
      
      // Step 3: Simulate what _handleEventLiveScores does when scoring != null
      gameScoring.croudSourcedScores = liveScoreUpdate.croudSourcedScores;
      
      // Step 4: Verify official scores maintain priority
      final homeScore = gameScoring.currentScore(ScoringTeam.home);
      final awayScore = gameScoring.currentScore(ScoringTeam.away);
      final result = gameScoring.getGameResultCalculated(League.nrl);
      
      expect(homeScore, 21, reason: 'Should use official home score, not live');
      expect(awayScore, 18, reason: 'Should use official away score, not live');
      expect(result, GameResult.b, reason: 'Home wins 21-18, should be GameResult.b');
    });

    test('SHOULD FAIL: Data isolation - live and official scores should be completely independent', () {
      // This test verifies proper data architecture
      
      // Step 1: Start with clean state
      Scoring? gameScoring;
      
      // Step 2: Live scores arrive with high values
      final liveScores = [
        CrowdSourcedScore(DateTime.now().toUtc(), ScoringTeam.home, 'tipper1', 100, false),
        CrowdSourcedScore(DateTime.now().toUtc(), ScoringTeam.away, 'tipper2', 90, false),
      ];
      
      // The CORRECT way to handle live scores when no scoring exists
      gameScoring ??= Scoring(
        homeTeamScore: null, // Should remain null - only live scores touch this
        awayTeamScore: null, // Should remain null - only live scores touch this
        croudSourcedScores: liveScores,
      );
      
      // Step 3: Official scores should be completely independent
      gameScoring = gameScoring.copyWith(
        homeTeamScore: 5,  // Much lower than live score
        awayTeamScore: 3,  // Much lower than live score
      );
      
      // Step 4: Verify complete independence
      expect(gameScoring.homeTeamScore, 5, reason: 'Official scores independent of live');
      expect(gameScoring.awayTeamScore, 3, reason: 'Official scores independent of live');
      expect(gameScoring.croudSourcedScores?.length, 2, reason: 'Live scores preserved');
      
      // Step 5: Verify official scores take priority despite being much lower
      final homeScore = gameScoring.currentScore(ScoringTeam.home);
      final awayScore = gameScoring.currentScore(ScoringTeam.away);
      
      expect(homeScore, 5, reason: 'Should use official score (5) not live score (100)');
      expect(awayScore, 3, reason: 'Should use official score (3) not live score (90)');
    });
  });
}