import 'dart:async';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
// import 'package:daufootytipping/view_models/teams_viewmodel.dart'; // Not strictly needed if not mocking its interactions
import 'package:flutter_test/flutter_test.dart';
// It's good practice to use a mocking library like mockito.
// Add mockito to your dev_dependencies in pubspec.yaml
// And run `flutter pub run build_runner build` to generate mocks if you use annotations.
// For this example, simple manual mocks or extending Mock from package:mockito/mockito.dart.
import 'package:mockito/mockito.dart';

// Manual Mock for DAUComp if not using build_runner for full mock generation
class MockDAUComp extends Mock implements DAUComp {
  @override
  String get dbkey => 'test-comp-dbkey';
  @override
  String get name => 'Test DAUComp';
  @override
  List<DAURound> get daurounds => []; // Default to empty list or provide specific rounds if needed
   // Add other getters/methods if GamesViewModel constructor or init calls them.
  @override
  DateTime? get aflRegularCompEndDateUTC => null;
  @override
  DateTime? get nrlRegularCompEndDateUTC => null;
}

// Manual Mock for DAUCompsViewModel
class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {
  // If GamesViewModel calls methods on _dauCompsViewModel during init, mock them here.
  // For example, if it tries to access selectedDAUComp:
  @override
  DAUComp? get selectedDAUComp => MockDAUComp(); // Return a default mock DAUComp
}

// Helper function to create a Team
Team _createTeam(String dbkey, String name, League league) {
  return Team(dbkey: dbkey, name: name, league: league);
}

// Helper function to create a Game
Game _createGame({
  required String dbkey,
  required League league,
  required Team homeTeam,
  required Team awayTeam,
  required DateTime startTime,
  int? homeScore,
  int? awayScore,
  int roundNumber = 1,
  int matchNumber = 1,
  String location = 'Test Venue',
}) {
  Scoring? scoring;
  if (homeScore != null && awayTeamScore != null) { // Corrected: awayTeamScore for scoring
    scoring = Scoring(homeTeamScore: homeScore, awayTeamScore: awayTeamScore);
  }
  return Game(
    dbkey: dbkey,
    league: league,
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    location: location,
    startTimeUTC: startTime,
    fixtureRoundNumber: roundNumber,
    fixtureMatchNumber: matchNumber,
    scoring: scoring,
  );
}

void main() {
  group('GamesViewModel - getMatchupHistory', () {
    late GamesViewModel gamesViewModel;
    late MockDAUComp mockDauComp; // Use the manually defined MockDAUComp
    late MockDAUCompsViewModel mockDauCompsViewModel;

    final teamNrlA = _createTeam('nrl-teamA', 'NRL Team A', League.nrl);
    final teamNrlB = _createTeam('nrl-teamB', 'NRL Team B', League.nrl);
    final teamNrlC = _createTeam('nrl-teamC', 'NRL Team C', League.nrl);
    final teamAflA = _createTeam('afl-teamA', 'AFL Team A', League.afl); // Used for wrong league game

    setUp(() {
      mockDauComp = MockDAUComp();
      mockDauCompsViewModel = MockDAUCompsViewModel();
      
      // Stub selectedDAUComp on mockDauCompsViewModel to return our mockDauComp
      when(mockDauCompsViewModel.selectedDAUComp).thenReturn(mockDauComp);

      gamesViewModel = GamesViewModel(mockDauComp, mockDauCompsViewModel);
      // Note: GamesViewModel constructor calls _initialize, which calls _listenToGames.
      // This attempts to set up a Firebase listener. In a pure unit test environment,
      // this might cause issues if Firebase is not initialized.
      // For focused testing of getMatchupHistory, this is okay as long as it doesn't throw
      // an unhandled exception during test setup that prevents tests from running.
      // The testability methods added will bypass the Firebase data loading path.
    });

    test('Basic case: returns filtered and sorted games', () async {
      final game1_match_older = _createGame( 
        dbkey: 'nrl-01-001', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl,
        startTime: DateTime(2023, 1, 1, 12, 0, 0), 
        homeScore: 10, awayScore: 20
      );
      final game2_match_newer = _createGame( 
        dbkey: 'nrl-01-002', homeTeam: teamNrlB, awayTeam: teamNrlA, league: League.nrl,
        startTime: DateTime(2023, 1, 2, 12, 0, 0), 
        homeScore: 30, awayScore: 10
      );
      final game3_wrong_team = _createGame( 
        dbkey: 'nrl-01-003', homeTeam: teamNrlA, awayTeam: teamNrlC, league: League.nrl,
        startTime: DateTime(2023, 1, 3, 12, 0, 0),
        homeScore: 10, awayScore: 20
      );
      final game4_wrong_league = _createGame( 
        dbkey: 'afl-01-001', homeTeam: teamAflA, awayTeam: teamNrlB, league: League.afl, 
        startTime: DateTime(2023, 1, 4, 12, 0, 0),
        homeScore: 10, awayScore: 20
      );
      final game5_no_score = _createGame( 
        dbkey: 'nrl-01-004', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl,
        startTime: DateTime(2023, 1, 5, 12, 0, 0),
        // No scoring info
      );
       final game6_match_newest = _createGame( 
        dbkey: 'nrl-01-005', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl,
        startTime: DateTime(2023, 1, 3, 15, 0, 0), 
        homeScore: 5, awayScore: 5
      );

      gamesViewModel.testGames = [game1_match_older, game2_match_newer, game3_wrong_team, game4_wrong_league, game5_no_score, game6_match_newest];
      gamesViewModel.completeInitialLoadForTest();

      final result = await gamesViewModel.getMatchupHistory(teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 3);
      expect(result[0].dbkey, game6_match_newest.dbkey, reason: "Newest game should be first");
      expect(result[1].dbkey, game2_match_newer.dbkey); 
      expect(result[2].dbkey, game1_match_older.dbkey, reason: "Oldest of the matched games should be last");
    });

    test('No matching games: returns empty list', () async {
      final game1_wrong_team = _createGame(
        dbkey: 'nrl-01-001', homeTeam: teamNrlA, awayTeam: teamNrlC, league: League.nrl,
        startTime: DateTime(2023, 1, 1),
        homeScore: 10, awayScore: 20
      );
      final game2_wrong_league = _createGame(
        dbkey: 'afl-01-001', homeTeam: teamAflA, awayTeam: teamNrlB, league: League.afl,
        startTime: DateTime(2023, 1, 2),
        homeScore: 10, awayScore: 20
      );
      final game3_no_score = _createGame(
        dbkey: 'nrl-01-002', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl,
        startTime: DateTime(2023, 1, 3),
      );
      
      gamesViewModel.testGames = [game1_wrong_team, game2_wrong_league, game3_no_score];
      gamesViewModel.completeInitialLoadForTest();

      final result = await gamesViewModel.getMatchupHistory(teamNrlA, teamNrlB, League.nrl);
      expect(result.isEmpty, isTrue);
    });

    test('Empty input games list: returns empty list', () async {
      gamesViewModel.testGames = [];
      gamesViewModel.completeInitialLoadForTest();
      
      final result = await gamesViewModel.getMatchupHistory(teamNrlA, teamNrlB, League.nrl);
      expect(result.isEmpty, isTrue);
    });

    test('Games with same timestamp: sorts by startTimeUTC descending. Relative order of same-timestamp games depends on initial list sort.', () async {
      final sameTime1 = DateTime(2023, 1, 1, 10, 0, 0);
      final game_samedate_m1 = _createGame( 
        dbkey: 'nrl-01-001', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl,
        startTime: sameTime1, matchNumber: 1, 
        homeScore: 10, awayScore: 20
      );
      final game_samedate_m2 = _createGame( 
        dbkey: 'nrl-01-002', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl,
        startTime: sameTime1, matchNumber: 2,
        homeScore: 30, awayScore: 10
      );
       final game_newer = _createGame( 
        dbkey: 'nrl-01-003', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl,
        startTime: DateTime(2023, 1, 1, 12, 0, 0), 
        homeScore: 30, awayScore: 10
      );
      
      // The `testGames` setter sorts the list by Game.compareTo (startTimeUTC ASC, then fixtureMatchNumber ASC)
      // So, _games becomes [game_samedate_m1, game_samedate_m2, game_newer]
      gamesViewModel.testGames = [game_newer, game_samedate_m2, game_samedate_m1]; // Intentionally unsorted by date/match to test sorting
      gamesViewModel.completeInitialLoadForTest();

      final result = await gamesViewModel.getMatchupHistory(teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 3);
      expect(result[0].dbkey, game_newer.dbkey, reason: "Newest game overall should be first");
      
      // After `game_newer`, the next games are `game_samedate_m1` and `game_samedate_m2`.
      // Both have the same `startTimeUTC`. The `testGames` setter sorts `_games` using `Game.compareTo`,
      // which means `game_samedate_m1` (matchNumber 1) will come before `game_samedate_m2` (matchNumber 2)
      // in the `_games` list.
      // The sort in `getMatchupHistory` is `(b.startTimeUTC.compareTo(a.startTimeUTC))`.
      // Since this is a stable sort, for elements with equal `startTimeUTC`, their relative order
      // from the `_games` list (after filtering) should be preserved.
      // Thus, `game_samedate_m1` should appear before `game_samedate_m2` in the final result.
      expect(result[1].dbkey, game_samedate_m1.dbkey, reason: "For same timestamp, game with smaller matchNumber (due to initial sort) should come first");
      expect(result[2].dbkey, game_samedate_m2.dbkey, reason: "For same timestamp, game with larger matchNumber (due to initial sort) should come after");
    });
  });
}
