import 'package:daufootytipping/models/daucomp.dart';

import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
// If using @GenerateMocks, ensure the import '.mocks.dart' is present
// For this manual approach, direct mocking is used.

// Manual Mock for DAUComp if not using build_runner for full mock generation
class MockDAUComp extends Mock implements DAUComp {}

// Manual Mock for DAUCompsViewModel
class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

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
  if (homeScore != null && awayScore != null) {
    scoring = Scoring(homeTeamScore: homeScore, awayTeamScore: awayScore);
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
  late GamesViewModel gamesViewModel;
  late MockDAUComp mockCurrentDauComp;
  late MockDAUCompsViewModel mockDauCompsViewModel;

  final teamNrlA = _createTeam('nrl-teamA', 'NRL Team A', League.nrl);
  final teamNrlB = _createTeam('nrl-teamB', 'NRL Team B', League.nrl);
  final teamNrlC = _createTeam('nrl-teamC', 'NRL Team C', League.nrl);

  setUp(() {
    mockCurrentDauComp = MockDAUComp();
    mockDauCompsViewModel = MockDAUCompsViewModel();

    // Set up mock behavior
    when(mockCurrentDauComp.dbkey).thenReturn('current-comp');
    when(mockCurrentDauComp.name).thenReturn('Current Comp');
    when(mockCurrentDauComp.daurounds).thenReturn([]);
    when(mockCurrentDauComp.aflRegularCompEndDateUTC).thenReturn(null);
    when(mockCurrentDauComp.nrlRegularCompEndDateUTC).thenReturn(null);

    when(mockDauCompsViewModel.selectedDAUComp).thenReturn(mockCurrentDauComp);
    when(mockDauCompsViewModel.daucomps).thenReturn([]);
    // Ensure initialDAUCompLoadComplete is always a completed future for the mock
    when(mockDauCompsViewModel.initialDAUCompLoadComplete)
        .thenAnswer((_) async {});

    gamesViewModel = GamesViewModel(mockCurrentDauComp, mockDauCompsViewModel);
    // Complete initial load for the GamesViewModel instance itself for its own _games list.
    // This is for tests that might still use the original getMatchupHistory or other methods
    // relying on the current GamesViewModel's _games.
    gamesViewModel.completeInitialLoadForTest();
  });

  group('GamesViewModel - getMatchupHistory (Original Behavior)', () {
    // Existing tests for getMatchupHistory ...
    // These tests verify filtering/sorting on the _games list of the current DAUComp.
    // They should still pass and are relevant.

    test('Basic case: returns filtered and sorted games from _games', () async {
      final game1MatchOlder = _createGame(
          dbkey: 'nrl-01-001',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime(2023, 1, 1, 12, 0, 0),
          homeScore: 10,
          awayScore: 20);
      final game2MatchNewer = _createGame(
          dbkey: 'nrl-01-002',
          homeTeam: teamNrlB,
          awayTeam: teamNrlA,
          league: League.nrl,
          startTime: DateTime(2023, 1, 2, 12, 0, 0),
          homeScore: 30,
          awayScore: 10);
      final game6MatchNewest = _createGame(
          dbkey: 'nrl-01-005',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime(2023, 1, 3, 15, 0, 0),
          homeScore: 5,
          awayScore: 5);

      gamesViewModel.testGames = [
        game1MatchOlder,
        game2MatchNewer,
        game6MatchNewest
      ];
      // gamesViewModel.completeInitialLoadForTest(); // Already called in global setUp

      final result = await gamesViewModel.getMatchupHistory(
          teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 3);
      expect(result[0].dbkey, game6MatchNewest.dbkey);
      expect(result[1].dbkey, game2MatchNewer.dbkey);
      expect(result[2].dbkey, game1MatchOlder.dbkey);
    });
  });

  group('GamesViewModel - getCompleteMatchupHistory', () {
    late MockDAUComp mockComp1;
    late MockDAUComp mockComp2;

    setUp(() {
      // Reset testGamesByCompKey for each test in this group
      gamesViewModel.testGamesByCompKey = {};

      mockComp1 = MockDAUComp();
      mockComp2 = MockDAUComp();

      // Set up mock behavior for comp1
      when(mockComp1.dbkey).thenReturn('comp1-key');
      when(mockComp1.name).thenReturn('Competition 1');
      when(mockComp1.daurounds).thenReturn([]);
      when(mockComp1.aflRegularCompEndDateUTC).thenReturn(null);
      when(mockComp1.nrlRegularCompEndDateUTC).thenReturn(null);

      // Set up mock behavior for comp2
      when(mockComp2.dbkey).thenReturn('comp2-key');
      when(mockComp2.name).thenReturn('Competition 2');
      when(mockComp2.daurounds).thenReturn([]);
      when(mockComp2.aflRegularCompEndDateUTC).thenReturn(null);
      when(mockComp2.nrlRegularCompEndDateUTC).thenReturn(null);

      // Ensure DAUCompsViewModel is stubbed correctly for these tests
      when(mockDauCompsViewModel.initialDAUCompLoadComplete)
          .thenAnswer((_) async {});
      // Default to returning these two comps. Override in specific tests if needed.
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);

      // Ensure TeamsViewModel is ready for team lookups if _fetchGamesForDAUCompKey goes to real path
      // This is implicitly handled by GamesViewModel's _teamsViewModel.initialLoadComplete,
      // which should be completed during GamesViewModel's own _initialize -> _teamsViewModel = TeamsViewModel() path.
      // For tests directly using testGamesByCompKey, this is less critical for that specific fetch.
    });

    test('Matchups from Multiple DAUComps are aggregated and sorted', () async {
      final gameC1T1 = _createGame(
          dbkey: 'c1g1',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime(2023, 1, 1),
          homeScore: 10,
          awayScore: 20);
      final gamec1t2Nonmatch = _createGame(
          dbkey: 'c1g2',
          homeTeam: teamNrlA,
          awayTeam: teamNrlC,
          league: League.nrl,
          startTime: DateTime(2023, 1, 2),
          homeScore: 10,
          awayScore: 20);

      final gameC2T1 = _createGame(
          dbkey: 'c2g1',
          homeTeam: teamNrlB,
          awayTeam: teamNrlA,
          league: League.nrl,
          startTime: DateTime(2023, 1, 3),
          homeScore: 30,
          awayScore: 10);
      final gamec2t2Newer = _createGame(
          dbkey: 'c2g2',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime(2023, 1, 4),
          homeScore: 5,
          awayScore: 5);

      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [gameC1T1, gamec1t2Nonmatch],
        'comp2-key': [gameC2T1, gamec2t2Newer],
      };

      final result = await gamesViewModel.getCompleteMatchupHistory(
          teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 3);
      expect(
          result.map((g) => g.dbkey).toList(),
          containsAllInOrder(
              [gamec2t2Newer.dbkey, gameC2T1.dbkey, gameC1T1.dbkey]));
    });

    test('Matchups from Single DAUComp', () async {
      final gameC1T1 = _createGame(
          dbkey: 'c1g1',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime(2023, 1, 1),
          homeScore: 10,
          awayScore: 20);
      final gamec1t2Newer = _createGame(
          dbkey: 'c1g2',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime(2023, 1, 5),
          homeScore: 10,
          awayScore: 20);

      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [gameC1T1, gamec1t2Newer],
        'comp2-key': [], // Comp2 has no games relevant or otherwise
      };
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);

      final result = await gamesViewModel.getCompleteMatchupHistory(
          teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 2);
      expect(result.map((g) => g.dbkey).toList(),
          containsAllInOrder([gamec1t2Newer.dbkey, gameC1T1.dbkey]));
    });

    test('No Matchups Found across DAUComps', () async {
      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [
          _createGame(
              dbkey: 'c1g1',
              homeTeam: teamNrlA,
              awayTeam: teamNrlC,
              league: League.nrl,
              startTime: DateTime(2023, 1, 1),
              homeScore: 1,
              awayScore: 1)
        ], // Not teamB
        'comp2-key': [
          _createGame(
              dbkey: 'c2g1',
              homeTeam: teamNrlB,
              awayTeam: teamNrlC,
              league: League.nrl,
              startTime: DateTime(2023, 1, 1),
              homeScore: 1,
              awayScore: 1)
        ], // Not teamA
      };
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);

      final result = await gamesViewModel.getCompleteMatchupHistory(
          teamNrlA, teamNrlB, League.nrl);
      expect(result.isEmpty, isTrue);
    });

    test('DAUComp with No Games is handled gracefully', () async {
      final gameC2T1 = _createGame(
          dbkey: 'c2g1',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime(2023, 1, 3),
          homeScore: 30,
          awayScore: 10);
      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [], // Comp1 has no games
        'comp2-key': [gameC2T1],
      };
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);

      final result = await gamesViewModel.getCompleteMatchupHistory(
          teamNrlA, teamNrlB, League.nrl);
      expect(result.length, 1);
      expect(result[0].dbkey, gameC2T1.dbkey);
    });

    test(
        'Games with Identical Timestamps Across DAUComps are sorted (stability relies on List.sort)',
        () async {
      final sameTime = DateTime(2023, 1, 10);
      final gamec1Match1 = _createGame(
          dbkey: 'c1g_m1',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: sameTime,
          matchNumber: 1,
          homeScore: 10,
          awayScore: 20);
      // To make sorting predictable for identical timestamps if primary sort key is same,
      // Dart's List.sort is stable. So original order from concatenation is preserved for equal elements.
      // Let's ensure they have different content to distinguish.
      final gamec2Match2Sametime = _createGame(
          dbkey: 'c2g_m2',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: sameTime,
          matchNumber: 2,
          homeScore: 5,
          awayScore: 5); // Different content
      final gamec1Later = _createGame(
          dbkey: 'c1g_later',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: sameTime.add(Duration(hours: 1)),
          homeScore: 1,
          awayScore: 1);

      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [gamec1Match1, gamec1Later],
        'comp2-key': [gamec2Match2Sametime],
      };
      // Order of DAUComps in the list matters for how games are initially aggregated before final sort
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);

      final result = await gamesViewModel.getCompleteMatchupHistory(
          teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 3);
      expect(result[0].dbkey, gamec1Later.dbkey,
          reason: "Latest game should be first");
      // For gameC1_match1 and gameC2_match2_sameTime, both have sameTime.
      // Their relative order in `allMatchupGames` before sort() depends on DAUComp iteration order
      // and then the order within `gamesFromThisDAUComp`.
      // If comp1 is processed first, gameC1_match1 is added. Then gameC2_match2_sameTime.
      // Since the sort `b.startTimeUTC.compareTo(a.startTimeUTC)` will yield 0 for them,
      // their relative order [gameC1_match1, gameC2_match2_sameTime] should be preserved by stable sort.
      expect(result[1].dbkey, gamec1Match1.dbkey);
      expect(result[2].dbkey, gamec2Match2Sametime.dbkey);
    });
  });
}
