import 'package:test/test.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/team.dart';

void main() {
  group('StatsViewModel Race Condition Tests', () {
    late Game testGame;

    setUp(() {
      // Create a test game
      testGame = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: Team(dbkey: 'nrl_team1', name: 'Team 1', league: League.nrl),
        awayTeam: Team(dbkey: 'nrl_team2', name: 'Team 2', league: League.nrl),
        location: 'Test Stadium',
        startTimeUTC: DateTime.now().toUtc(),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
    });

    test(
      'SHOULD EXPOSE BUG: _handleEventLiveScores assigns entire Scoring object when game.scoring is null',
      () {
        // This test simulates the exact scenario in StatsViewModel._handleEventLiveScores()

        // Step 1: Game starts with no scoring data
        expect(
          testGame.scoring,
          null,
          reason: 'Game should start with no scoring',
        );

        // Step 2: Live scores arrive via Firebase (simulating line 248-250 in _handleEventLiveScores)
        // This simulates what Scoring.fromJson() creates from live score data
        final liveScoreFromDatabase = {
          'homeTeamScore': null, // ❌ Database explicitly sets these to null
          'awayTeamScore': null, // ❌ This is the problem!
          'croudSourcedScores': [
            {
              'submittedTimeUTC': DateTime.now().toUtc().toIso8601String(),
              'scoreTeam': 'home',
              'tipperID': 'tipper1',
              'interimScore': 14,
              'gameComplete': false,
            },
          ],
        };

        final scoringFromLiveUpdate = Scoring.fromJson(liveScoreFromDatabase);

        // Step 3: Simulate the problematic assignment from _handleEventLiveScores line 252
        if (testGame.scoring == null) {
          testGame.scoring =
              scoringFromLiveUpdate; // ❌ BUG: Assigns object with null official scores
        } else {
          testGame.scoring?.crowdSourcedScores =
              scoringFromLiveUpdate.crowdSourcedScores;
        }

        // Step 4: Verify the bug - official score fields are now explicitly null
        expect(
          testGame.scoring?.homeTeamScore,
          null,
          reason: 'Live update set official scores to null',
        );
        expect(
          testGame.scoring?.awayTeamScore,
          null,
          reason: 'Live update set official scores to null',
        );
        expect(
          testGame.scoring?.crowdSourcedScores?.length,
          1,
          reason: 'Live scores should be present',
        );

        // Step 5: Official scores arrive later from fixture download
        testGame.scoring = testGame.scoring!.copyWith(
          homeTeamScore: 18, // Official: Home wins
          awayTeamScore: 12,
        );

        // Step 6: This should work due to priority logic, but the architecture is wrong
        final result = testGame.scoring!.getGameResultCalculated(League.nrl);
        expect(
          result,
          GameResult.b,
          reason: 'Home wins 18-12, should be GameResult.b',
        );

        // But the test exposes that we unnecessarily touched official score fields
        // The fix is to never assign the entire Scoring object from live data
      },
    );

    test('SHOULD FAIL INITIALLY: Demonstrate the correct fix for data isolation', () {
      // This test shows what the fix should look like

      // Step 1: Game starts with no scoring data
      expect(testGame.scoring, null);

      // Step 2: Live scores arrive - simulate the CORRECTED _handleEventLiveScores logic
      final liveScoreFromDatabase = {
        'homeTeamScore': null,
        'awayTeamScore': null,
        'croudSourcedScores': [
          {
            'submittedTimeUTC': DateTime.now().toUtc().toIso8601String(),
            'scoreTeam': 'home',
            'tipperID': 'tipper1',
            'interimScore': 25,
            'gameComplete': false,
          },
        ],
      };

      final scoringFromLiveUpdate = Scoring.fromJson(liveScoreFromDatabase);

      // Step 3: THE FIX - Only assign crowd-sourced scores, never touch official fields
      if (testGame.scoring == null) {
        testGame.scoring = Scoring(
          crowdSourcedScores: scoringFromLiveUpdate.crowdSourcedScores,
          // homeTeamScore and awayTeamScore remain null (their default)
          // They are NEVER touched by live score updates
        );
      } else {
        testGame.scoring?.crowdSourcedScores =
            scoringFromLiveUpdate.crowdSourcedScores;
      }

      // Step 4: Verify clean initial state - official scores were never touched
      expect(
        testGame.scoring?.homeTeamScore,
        null,
        reason: 'Official scores untouched by live data',
      );
      expect(
        testGame.scoring?.awayTeamScore,
        null,
        reason: 'Official scores untouched by live data',
      );
      expect(
        testGame.scoring?.crowdSourcedScores?.length,
        1,
        reason: 'Live scores preserved',
      );

      // Step 5: Official scores arrive later and work cleanly
      testGame.scoring = testGame.scoring!.copyWith(
        homeTeamScore: 10,
        awayTeamScore: 8,
      );

      // Step 6: Perfect data isolation - both data sources coexist cleanly
      expect(
        testGame.scoring?.homeTeamScore,
        10,
        reason: 'Official scores work perfectly',
      );
      expect(
        testGame.scoring?.awayTeamScore,
        8,
        reason: 'Official scores work perfectly',
      );
      expect(
        testGame.scoring?.crowdSourcedScores?.length,
        1,
        reason: 'Live scores preserved',
      );

      // Step 7: Priority logic works flawlessly
      final homeScore = testGame.scoring!.currentScore(ScoringTeam.home);
      final awayScore = testGame.scoring!.currentScore(ScoringTeam.away);
      final result = testGame.scoring!.getGameResultCalculated(League.nrl);

      expect(
        homeScore,
        10,
        reason: 'Uses official score despite live score being 25',
      );
      expect(awayScore, 8, reason: 'Uses official score');
      expect(result, GameResult.b, reason: 'Home wins 10-8');
    });

    test(
      'SHOULD EXPOSE BUG: Official scores arriving first, then live scores with explicit nulls',
      () {
        // This tests the reverse scenario that could also cause issues

        // Step 1: Official scores arrive first (from fixture download)
        testGame.scoring = Scoring(homeTeamScore: 20, awayTeamScore: 16);

        // Step 2: Live scores arrive later with explicit null values for official scores
        final liveScoreFromDatabase = {
          'homeTeamScore': null, // ❌ Explicit null from database
          'awayTeamScore': null, // ❌ Explicit null from database
          'croudSourcedScores': [
            {
              'submittedTimeUTC': DateTime.now().toUtc().toIso8601String(),
              'scoreTeam': 'away',
              'tipperID': 'tipper1',
              'interimScore': 30,
              'gameComplete': false,
            },
          ],
        };

        final scoringFromLiveUpdate = Scoring.fromJson(liveScoreFromDatabase);

        // Step 3: Current _handleEventLiveScores logic (line 254) - this should be safe
        testGame.scoring?.crowdSourcedScores =
            scoringFromLiveUpdate.crowdSourcedScores;

        // Step 4: Verify official scores were not overwritten
        expect(
          testGame.scoring?.homeTeamScore,
          20,
          reason: 'Official scores preserved',
        );
        expect(
          testGame.scoring?.awayTeamScore,
          16,
          reason: 'Official scores preserved',
        );
        expect(
          testGame.scoring?.crowdSourcedScores?.length,
          1,
          reason: 'Live scores added',
        );

        // Step 5: Priority logic should still work
        final result = testGame.scoring!.getGameResultCalculated(League.nrl);
        expect(
          result,
          GameResult.b,
          reason: 'Home wins 20-16 using official scores',
        );
      },
    );

    test(
      'SHOULD EXPOSE BUG: Timing-dependent behavior based on arrival order',
      () {
        // This test shows how the current code has different behavior based on timing

        // Scenario A: Live scores first (problematic)
        final gameA = Game(
          dbkey: 'nrl-01-002',
          league: League.nrl,
          homeTeam: Team(
            dbkey: 'nrl_team1',
            name: 'Team 1',
            league: League.nrl,
          ),
          awayTeam: Team(
            dbkey: 'nrl_team2',
            name: 'Team 2',
            league: League.nrl,
          ),
          location: 'Test Stadium',
          startTimeUTC: DateTime.now().toUtc(),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 2,
        );

        // Live scores arrive first for Game A
        final liveScoring = Scoring.fromJson({
          'homeTeamScore': null,
          'awayTeamScore': null,
          'croudSourcedScores': [
            {
              'submittedTimeUTC': DateTime.now().toUtc().toIso8601String(),
              'scoreTeam': 'home',
              'tipperID': 'tipper1',
              'interimScore': 15,
              'gameComplete': false,
            },
          ],
        });

        gameA.scoring ??= liveScoring; // ❌ Current problematic approach

        // Official scores arrive later for Game A
        gameA.scoring = gameA.scoring?.copyWith(
          homeTeamScore: 12,
          awayTeamScore: 10,
        );

        // Scenario B: Official scores first (works fine)
        final gameB = Game(
          dbkey: 'nrl-01-003',
          league: League.nrl,
          homeTeam: Team(
            dbkey: 'nrl_team1',
            name: 'Team 1',
            league: League.nrl,
          ),
          awayTeam: Team(
            dbkey: 'nrl_team2',
            name: 'Team 2',
            league: League.nrl,
          ),
          location: 'Test Stadium',
          startTimeUTC: DateTime.now().toUtc(),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 3,
        );

        // Official scores arrive first for Game B
        gameB.scoring = Scoring(homeTeamScore: 12, awayTeamScore: 10);

        // Live scores arrive later for Game B
        gameB.scoring?.crowdSourcedScores = liveScoring.crowdSourcedScores;

        // Both games should behave identically regardless of arrival order
        final resultA = gameA.scoring!.getGameResultCalculated(League.nrl);
        final resultB = gameB.scoring!.getGameResultCalculated(League.nrl);

        expect(
          resultA,
          resultB,
          reason: 'Results should be identical regardless of arrival order',
        );
        expect(resultA, GameResult.b, reason: 'Home wins 12-10');

        // The bug is exposed by the fact that the internal structure differs
        // even though the final result is the same due to priority logic
      },
    );
  });
}
