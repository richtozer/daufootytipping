import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

// Generate mocks for these classes
@GenerateMocks([
  Tipper,
  DAUComp,
  // Game, // We will use real Game objects for historical games list, with MockTeam and MockScoring
  Tip,    // We will use real Tip objects
  Team,   // For upcoming game's teams and historical game's teams
  Scoring,// For historical game's scoring
  GamesViewModel,
  TipsViewModel,
])
import 'gametip_viewmodel_test.mocks.dart'; // Import generated mocks

// GetIt instance for managing dependencies
final getIt = GetIt.instance;

void main() {
  late GameTipViewModel gameTipViewModel;
  late MockTipper mockCurrentTipper;
  late MockDAUComp mockCurrentDAUComp;
  late Game mockUpcomingGame; // The game for which insights are being generated - use real Game with MockTeams
  late MockTipsViewModel mockTipsViewModel;
  late MockGamesViewModel mockGamesViewModel; // For DI

  late MockTeam mockUpcomingHomeTeam;
  late MockTeam mockUpcomingAwayTeam;

  // Helper to create a real Game object for historical matchups
  Game _createHistoricalGame({
    required String dbkey,
    required Team homeTeam, // Can be MockTeam
    required Team awayTeam, // Can be MockTeam
    required League league,
    required DateTime startTime,
    int? homeScore,
    int? awayScore,
  }) {
    MockScoring? mockScoring;
    if (homeScore != null && awayScore != null) {
      mockScoring = MockScoring();
      when(mockScoring.homeTeamScore).thenReturn(homeScore);
      when(mockScoring.awayTeamScore).thenReturn(awayScore);
    }
    
    return Game(
      dbkey: dbkey,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      league: league,
      startTimeUTC: startTime,
      location: 'Test Stadium',
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: mockScoring, // Use the mock scoring object
    );
  }

  // Helper to create a real Tip object
  Tip _createHistoricalTip({
    required Game game, // Real game instance
    required Tipper tipper, // Can be MockTipper
    required GameResult tipResult,
    required bool isDefault,
  }) {
    return Tip(
      dbkey: 'tip-${game.dbkey}-${tipper.dbkey}',
      game: game,
      tipper: tipper, // Use the mock tipper
      tip: tipResult,
      submittedTimeUTC: isDefault ? DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true) : DateTime.now().toUtc(),
    );
  }
  
  // Helper to create the "current" game being viewed by the GameTipViewModel
  Game _createUpcomingGame({
    required String dbkey,
    required Team homeTeam,
    required Team awayTeam,
    required League league,
  }) {
     return Game(
      dbkey: dbkey,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      league: league,
      startTimeUTC: DateTime.now().add(Duration(days:1)), // Future game
      location: 'Upcoming Venue',
      fixtureRoundNumber: 10,
      fixtureMatchNumber: 1,
      // Scoring would typically be null for an upcoming game
    );
  }

  setUpAll(() {
    getIt.allowReassignment = true;
    // Register the mock GamesViewModel with GetIt
    mockGamesViewModel = MockGamesViewModel();
    getIt.registerSingleton<GamesViewModel>(mockGamesViewModel);
  });

  setUp(() {
    mockCurrentTipper = MockTipper();
    mockCurrentDAUComp = MockDAUComp();
    mockTipsViewModel = MockTipsViewModel();
    
    // It's important that mockGamesViewModel is already registered from setUpAll
    // or here if not a singleton that persists across tests in this group.
    // If it's registered in setUpAll, ensure it's reset or stubs are cleared if necessary.
    // For this case, we re-stub it in each test or setup as needed.

    when(mockTipsViewModel.gamesViewModel).thenReturn(mockGamesViewModel);

    mockUpcomingHomeTeam = MockTeam();
    when(mockUpcomingHomeTeam.dbkey).thenReturn('nrl-upcomingHome');
    when(mockUpcomingHomeTeam.name).thenReturn('Upcoming Home Dragons');
    
    mockUpcomingAwayTeam = MockTeam();
    when(mockUpcomingAwayTeam.dbkey).thenReturn('nrl-upcomingAway');
    when(mockUpcomingAwayTeam.name).thenReturn('Upcoming Away Cowboys');

    mockUpcomingGame = _createUpcomingGame(
      dbkey: 'upcoming-game-key',
      homeTeam: mockUpcomingHomeTeam,
      awayTeam: mockUpcomingAwayTeam,
      league: League.nrl
    );

    when(mockCurrentTipper.dbkey).thenReturn('tipper-current-key');
    when(mockCurrentTipper.name).thenReturn('Current Test Tipper');
    
    when(mockGamesViewModel.initialLoadComplete).thenAnswer((_) async {});


    gameTipViewModel = GameTipViewModel(
      mockCurrentTipper,
      mockCurrentDAUComp,
      mockUpcomingGame, // Pass the real Game object with MockTeams
      mockTipsViewModel,
    );
  });


  group('getFormattedHistoricalMatchups', () {
    test('Correctly formats historical games with various tip types', () async {
      final now = DateTime.now();
      final histGame1 = _createHistoricalGame(
        dbkey: 'hist-g1', homeTeam: mockUpcomingHomeTeam, awayTeam: mockUpcomingAwayTeam, league: League.nrl,
        startTime: DateTime(now.year - 1, 3, 15), homeScore: 20, awayScore: 10, // Home win
      );
      final tip1 = _createHistoricalTip(game: histGame1, tipper: mockCurrentTipper, tipResult: GameResult.b, isDefault: false); // Active Home tip

      final histGame2 = _createHistoricalGame(
        dbkey: 'hist-g2', homeTeam: mockUpcomingAwayTeam, awayTeam: mockUpcomingHomeTeam, league: League.nrl, // Teams swapped for variety
        startTime: DateTime(now.year, 7, 20), homeScore: 12, awayScore: 18, // Away win (mockUpcomingHomeTeam is Away here)
      );
      final tip2 = _createHistoricalTip(game: histGame2, tipper: mockCurrentTipper, tipResult: GameResult.d, isDefault: true); // Default Away tip

      final histGame3 = _createHistoricalGame(
        dbkey: 'hist-g3', homeTeam: mockUpcomingHomeTeam, awayTeam: mockUpcomingAwayTeam, league: League.nrl,
        startTime: DateTime(now.year - 2, 11, 5), homeScore: 24, awayScore: 24, // Draw
      );
      // No tip for game 3

      final histGame4 = _createHistoricalGame(
        dbkey: 'hist-g4', homeTeam: mockUpcomingHomeTeam, awayTeam: mockUpcomingAwayTeam, league: League.nrl,
        startTime: DateTime(now.year, 1, 10), homeScore: 30, awayScore: 0, // Home win
      );
      final tip4 = _createHistoricalTip(game: histGame4, tipper: mockCurrentTipper, tipResult: GameResult.a, isDefault: true); // Default Home tip

      final histGame5_UserTippedDraw = _createHistoricalGame(
        dbkey: 'hist-g5', homeTeam: mockUpcomingHomeTeam, awayTeam: mockUpcomingAwayTeam, league: League.nrl,
        startTime: DateTime(now.year -3, 5, 5), homeScore: 12, awayScore: 12, // Actual Draw
      );
      final tip5 = _createHistoricalTip(game: histGame5_UserTippedDraw, tipper: mockCurrentTipper, tipResult: GameResult.c, isDefault: false); // Active Draw tip


      // Updated to call getCompleteMatchupHistory
      when(mockGamesViewModel.getCompleteMatchupHistory(mockUpcomingHomeTeam, mockUpcomingAwayTeam, League.nrl))
          .thenAnswer((_) async => [histGame1, histGame2, histGame3, histGame4, histGame5_UserTippedDraw]);
      
      when(mockTipsViewModel.findTip(histGame1, mockCurrentTipper)).thenAnswer((_) async => tip1);
      when(mockTipsViewModel.findTip(histGame2, mockCurrentTipper)).thenAnswer((_) async => tip2);
      when(mockTipsViewModel.findTip(histGame3, mockCurrentTipper)).thenAnswer((_) async => null);
      when(mockTipsViewModel.findTip(histGame4, mockCurrentTipper)).thenAnswer((_) async => tip4);
      when(mockTipsViewModel.findTip(histGame5_UserTippedDraw, mockCurrentTipper)).thenAnswer((_) async => tip5);

      final result = await gameTipViewModel.getFormattedHistoricalMatchups();

      expect(result.length, 5);

      // Game 1: Home Win, User Tipped Home (Active)
      expect(result[0].year, (now.year - 1).toString());
      expect(result[0].month, "Mar");
      expect(result[0].isCurrentYear, false);
      expect(result[0].winningTeamName, mockUpcomingHomeTeam.name);
      expect(result[0].winType, "Home");
      expect(result[0].userTipTeamName, mockUpcomingHomeTeam.name);

      // Game 2: Away Win (mockUpcomingHomeTeam was away), User Tipped Default Away (Ignored)
      expect(result[1].year, now.year.toString());
      expect(result[1].month, "Jul");
      expect(result[1].isCurrentYear, true);
      expect(result[1].winningTeamName, mockUpcomingHomeTeam.name); // mockUpcomingHomeTeam was the away team and won
      expect(result[1].winType, "Away");
      expect(result[1].userTipTeamName, isEmpty, reason: "Default Away tip should be ignored");

      // Game 3: Draw, User No Tip
      expect(result[2].year, (now.year - 2).toString());
      expect(result[2].month, "Nov");
      expect(result[2].isCurrentYear, false);
      expect(result[2].winningTeamName, "Draw");
      expect(result[2].winType, "Draw");
      expect(result[2].userTipTeamName, isEmpty);
      
      // Game 4: Home Win, User Tipped Default Home (Shown)
      expect(result[3].year, now.year.toString());
      expect(result[3].month, "Jan");
      expect(result[3].isCurrentYear, true);
      expect(result[3].winningTeamName, mockUpcomingHomeTeam.name);
      expect(result[3].winType, "Home");
      expect(result[3].userTipTeamName, mockUpcomingHomeTeam.name, reason: "Default Home tip should be shown");

      // Game 5: Actual Draw, User Tipped Draw (Active)
      expect(result[4].year, (now.year - 3).toString());
      expect(result[4].month, "May");
      expect(result[4].isCurrentYear, false);
      expect(result[4].winningTeamName, "Draw");
      expect(result[4].winType, "Draw");
      expect(result[4].userTipTeamName, "Draw", reason: "User actively tipped Draw");
    });

    test('Returns empty list when no historical games are found', () async {
      // Updated to call getCompleteMatchupHistory
      when(mockGamesViewModel.getCompleteMatchupHistory(mockUpcomingHomeTeam, mockUpcomingAwayTeam, League.nrl))
          .thenAnswer((_) async => []);

      final result = await gameTipViewModel.getFormattedHistoricalMatchups();
      expect(result.isEmpty, isTrue);
    });
    
    test('Skips games with missing scores', () async {
      final gameWithScore = _createHistoricalGame(
        dbkey: 'hist-scored', homeTeam: mockUpcomingHomeTeam, awayTeam: mockUpcomingAwayTeam, league: League.nrl,
        startTime: DateTime(2023, 3, 15), homeScore: 20, awayScore: 10,
      );
      final tipForScored = _createHistoricalTip(game: gameWithScore, tipper: mockCurrentTipper, tipResult: GameResult.b, isDefault: false);

      final gameNoScoringObject = _createHistoricalGame( // scoring object is null
        dbkey: 'hist-no-scoring-obj', homeTeam: mockUpcomingHomeTeam, awayTeam: mockUpcomingAwayTeam, league: League.nrl,
        startTime: DateTime(2023, 3, 10), // homeScore and awayScore not provided to _createHistoricalGame
      );
       final gameNullScores = _createHistoricalGame( 
        dbkey: 'hist-null-scores', homeTeam: mockUpcomingHomeTeam, awayTeam: mockUpcomingAwayTeam, league: League.nrl,
        startTime: DateTime(2023, 3, 5), homeScore: 10, awayScore: null, // awayScore is null
      );
      // Ensure scoring object exists but awayTeamScore is null for gameNullScores
      (gameNullScores.scoring as MockScoring).homeTeamScore = 10; // This was set
      when((gameNullScores.scoring as MockScoring).awayTeamScore).thenReturn(null); // Explicitly stub awayTeamScore to be null


      // Updated to call getCompleteMatchupHistory
      when(mockGamesViewModel.getCompleteMatchupHistory(mockUpcomingHomeTeam, mockUpcomingAwayTeam, League.nrl))
          .thenAnswer((_) async => [gameWithScore, gameNoScoringObject, gameNullScores]);
      
      when(mockTipsViewModel.findTip(gameWithScore, mockCurrentTipper)).thenAnswer((_) async => tipForScored);
      // findTip might be called for others, let them return null, they should be skipped before tip processing.
      when(mockTipsViewModel.findTip(gameNoScoringObject, mockCurrentTipper)).thenAnswer((_) async => null);
      when(mockTipsViewModel.findTip(gameNullScores, mockCurrentTipper)).thenAnswer((_) async => null);

      final result = await gameTipViewModel.getFormattedHistoricalMatchups();

      expect(result.length, 1);
      expect(result[0].pastGame.dbkey, gameWithScore.dbkey);
    });
  });
}
