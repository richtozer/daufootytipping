import 'dart:async';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
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
class MockDAUComp extends Mock implements DAUComp {
  // Explicitly define a default constructor
  MockDAUComp({String? dbkey, String? name, List<DAURound>? daurounds}) {
    _dbkey = dbkey ?? 'default-comp-dbkey';
    _name = name ?? 'Default Mock DAUComp';
    _daurounds = daurounds ?? [];
    
    // Stub the getters to return these private fields
    when(this.dbkey).thenReturn(_dbkey);
    when(this.name).thenReturn(_name);
    when(this.daurounds).thenReturn(_daurounds);
    when(this.aflRegularCompEndDateUTC).thenReturn(null); // Default for other properties
    when(this.nrlRegularCompEndDateUTC).thenReturn(null);
  }

  late String _dbkey;
  late String _name;
  late List<DAURound> _daurounds;

  // Override getters that might be called
  @override
  String get dbkey => _dbkey;
  @override
  String get name => _name;
  @override
  List<DAURound> get daurounds => _daurounds;
  // Add other properties if they are accessed and need specific values
}

// Manual Mock for DAUCompsViewModel
class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {
  MockDAUCompsViewModel() {
    // Provide a default completed future for initialDAUCompLoadComplete
    when(initialDAUCompLoadComplete).thenAnswer((_) async {});
    // Default to an empty list of dauComps
    when(daucomps).thenReturn([]);
  }
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
  final teamAflA = _createTeam('afl-teamA', 'AFL Team A', League.afl);

  setUp(() {
    mockCurrentDauComp = MockDAUComp(dbkey: 'current-comp', name: 'Current Comp');
    mockDauCompsViewModel = MockDAUCompsViewModel();
    
    when(mockDauCompsViewModel.selectedDAUComp).thenReturn(mockCurrentDauComp);
    // Ensure initialDAUCompLoadComplete is always a completed future for the mock
    when(mockDauCompsViewModel.initialDAUCompLoadComplete).thenAnswer((_) async {});


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
      final game6_match_newest = _createGame( 
        dbkey: 'nrl-01-005', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl,
        startTime: DateTime(2023, 1, 3, 15, 0, 0), 
        homeScore: 5, awayScore: 5
      );

      gamesViewModel.testGames = [game1_match_older, game2_match_newer, game6_match_newest];
      // gamesViewModel.completeInitialLoadForTest(); // Already called in global setUp

      final result = await gamesViewModel.getMatchupHistory(teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 3);
      expect(result[0].dbkey, game6_match_newest.dbkey);
      expect(result[1].dbkey, game2_match_newer.dbkey); 
      expect(result[2].dbkey, game1_match_older.dbkey);
    });
  });


  group('GamesViewModel - getCompleteMatchupHistory', () {
    late MockDAUComp mockComp1;
    late MockDAUComp mockComp2;

    setUp(() {
      // Reset testGamesByCompKey for each test in this group
      gamesViewModel.testGamesByCompKey = {};

      mockComp1 = MockDAUComp(dbkey: 'comp1-key', name: 'Competition 1');
      mockComp2 = MockDAUComp(dbkey: 'comp2-key', name: 'Competition 2');

      // Ensure DAUCompsViewModel is stubbed correctly for these tests
      when(mockDauCompsViewModel.initialDAUCompLoadComplete).thenAnswer((_) async {});
      // Default to returning these two comps. Override in specific tests if needed.
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);
      
      // Ensure TeamsViewModel is ready for team lookups if _fetchGamesForDAUCompKey goes to real path
      // This is implicitly handled by GamesViewModel's _teamsViewModel.initialLoadComplete,
      // which should be completed during GamesViewModel's own _initialize -> _teamsViewModel = TeamsViewModel() path.
      // For tests directly using testGamesByCompKey, this is less critical for that specific fetch.
    });

    test('Matchups from Multiple DAUComps are aggregated and sorted', () async {
      final gameC1T1 = _createGame(dbkey: 'c1g1', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl, startTime: DateTime(2023, 1, 1), homeScore: 10, awayScore: 20);
      final gameC1T2_nonMatch = _createGame(dbkey: 'c1g2', homeTeam: teamNrlA, awayTeam: teamNrlC, league: League.nrl, startTime: DateTime(2023, 1, 2), homeScore: 10, awayScore: 20);
      
      final gameC2T1 = _createGame(dbkey: 'c2g1', homeTeam: teamNrlB, awayTeam: teamNrlA, league: League.nrl, startTime: DateTime(2023, 1, 3), homeScore: 30, awayScore: 10);
      final gameC2T2_newer = _createGame(dbkey: 'c2g2', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl, startTime: DateTime(2023, 1, 4), homeScore: 5, awayScore: 5);

      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [gameC1T1, gameC1T2_nonMatch],
        'comp2-key': [gameC2T1, gameC2T2_newer],
      };
      
      final result = await gamesViewModel.getCompleteMatchupHistory(teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 3);
      expect(result.map((g) => g.dbkey).toList(), containsAllInOrder([gameC2T2_newer.dbkey, gameC2T1.dbkey, gameC1T1.dbkey]));
    });

    test('Matchups from Single DAUComp', () async {
      final gameC1T1 = _createGame(dbkey: 'c1g1', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl, startTime: DateTime(2023, 1, 1), homeScore: 10, awayScore: 20);
      final gameC1T2_newer = _createGame(dbkey: 'c1g2', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl, startTime: DateTime(2023, 1, 5), homeScore: 10, awayScore: 20);

      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [gameC1T1, gameC1T2_newer],
        'comp2-key': [], // Comp2 has no games relevant or otherwise
      };
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);


      final result = await gamesViewModel.getCompleteMatchupHistory(teamNrlA, teamNrlB, League.nrl);

      expect(result.length, 2);
      expect(result.map((g) => g.dbkey).toList(), containsAllInOrder([gameC1T2_newer.dbkey, gameC1T1.dbkey]));
    });

    test('No Matchups Found across DAUComps', () async {
      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [_createGame(dbkey: 'c1g1', homeTeam: teamNrlA, awayTeam: teamNrlC, league: League.nrl, startTime: DateTime(2023,1,1), homeScore: 1, awayScore:1)], // Not teamB
        'comp2-key': [_createGame(dbkey: 'c2g1', homeTeam: teamNrlB, awayTeam: teamNrlC, league: League.nrl, startTime: DateTime(2023,1,1), homeScore: 1, awayScore:1)], // Not teamA
      };
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);

      final result = await gamesViewModel.getCompleteMatchupHistory(teamNrlA, teamNrlB, League.nrl);
      expect(result.isEmpty, isTrue);
    });
    
    test('DAUComp with No Games is handled gracefully', () async {
      final gameC2T1 = _createGame(dbkey: 'c2g1', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl, startTime: DateTime(2023, 1, 3), homeScore: 30, awayScore: 10);
      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [], // Comp1 has no games
        'comp2-key': [gameC2T1],
      };
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);

      final result = await gamesViewModel.getCompleteMatchupHistory(teamNrlA, teamNrlB, League.nrl);
      expect(result.length, 1);
      expect(result[0].dbkey, gameC2T1.dbkey);
    });

    test('Games with Identical Timestamps Across DAUComps are sorted (stability relies on List.sort)', () async {
      final sameTime = DateTime(2023, 1, 10);
      final gameC1_match1 = _createGame(dbkey: 'c1g_m1', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl, startTime: sameTime, matchNumber:1, homeScore: 10, awayScore: 20);
      // To make sorting predictable for identical timestamps if primary sort key is same,
      // Dart's List.sort is stable. So original order from concatenation is preserved for equal elements.
      // Let's ensure they have different content to distinguish.
      final gameC2_match2_sameTime = _createGame(dbkey: 'c2g_m2', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl, startTime: sameTime, matchNumber:2, homeScore: 5, awayScore: 5); // Different content
      final gameC1_later = _createGame(dbkey: 'c1g_later', homeTeam: teamNrlA, awayTeam: teamNrlB, league: League.nrl, startTime: sameTime.add(Duration(hours:1)), homeScore: 1, awayScore:1);

      gamesViewModel.testGamesByCompKey = {
        'comp1-key': [gameC1_match1, gameC1_later], 
        'comp2-key': [gameC2_match2_sameTime],  
      };
      // Order of DAUComps in the list matters for how games are initially aggregated before final sort
      when(mockDauCompsViewModel.daucomps).thenReturn([mockComp1, mockComp2]);


      final result = await gamesViewModel.getCompleteMatchupHistory(teamNrlA, teamNrlB, League.nrl);
      
      expect(result.length, 3);
      expect(result[0].dbkey, gameC1_later.dbkey, reason: "Latest game should be first");
      // For gameC1_match1 and gameC2_match2_sameTime, both have sameTime.
      // Their relative order in `allMatchupGames` before sort() depends on DAUComp iteration order
      // and then the order within `gamesFromThisDAUComp`.
      // If comp1 is processed first, gameC1_match1 is added. Then gameC2_match2_sameTime.
      // Since the sort `b.startTimeUTC.compareTo(a.startTimeUTC)` will yield 0 for them,
      // their relative order [gameC1_match1, gameC2_match2_sameTime] should be preserved by stable sort.
      expect(result[1].dbkey, gameC1_match1.dbkey);
      expect(result[2].dbkey, gameC2_match2_sameTime.dbkey);
    });
  });
}
