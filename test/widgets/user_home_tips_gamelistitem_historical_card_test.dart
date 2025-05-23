import 'dart:async';

import 'package:carousel_slider/carousel_controller.dart';
import 'package:carousel_slider/carousel_options.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateMocks([
  GameTipViewModel,
  Game, 
  Tipper, 
  DAUComp, 
  TipsViewModel, 
  Team, 
  DAUCompsViewModel,
  GamesViewModel,
  TeamsViewModel,
])
import 'user_home_tips_gamelistitem_historical_card_test.mocks.dart';

final getIt = GetIt.instance;

void main() {
  late MockGameTipViewModel mockGameTipViewModel;
  late MockGame mockGameForListItem;
  late MockTipper mockTipper;
  late MockDAUComp mockDAUCompForListItem;
  late MockTipsViewModel mockTipsViewModel;
  late MockTeam mockHomeTeam;
  late MockTeam mockAwayTeam;
  late CarouselController realCarouselController;

  late MockDAUCompsViewModel mockDAUCompsViewModelForDI;
  late MockGamesViewModel mockGamesViewModelForDI;
  late MockTeamsViewModel mockTeamsViewModelForDI;

  setUpAll(() {
    getIt.allowReassignment = true;
    mockDAUCompsViewModelForDI = MockDAUCompsViewModel();
    mockGamesViewModelForDI = MockGamesViewModel();
    mockTeamsViewModelForDI = MockTeamsViewModel();

    getIt.registerSingleton<DAUCompsViewModel>(mockDAUCompsViewModelForDI);
    when(mockDAUCompsViewModelForDI.gamesViewModel).thenReturn(mockGamesViewModelForDI);
    when(mockGamesViewModelForDI.teamsViewModel).thenReturn(mockTeamsViewModelForDI);
    
    when(mockGamesViewModelForDI.initialLoadComplete).thenAnswer((_) async {});
    when(mockGamesViewModelForDI.getGames()).thenAnswer((_) async => []); // Used by _fetchAndSetLadderRanks
    when(mockTeamsViewModelForDI.initialLoadComplete).thenAnswer((_) async {});
    when(mockTeamsViewModelForDI.groupedTeams).thenReturn({});
  });

  setUp(() {
    mockGameTipViewModel = MockGameTipViewModel();
    mockGameForListItem = MockGame();
    mockTipper = MockTipper();
    mockDAUCompForListItem = MockDAUComp(); 
    mockTipsViewModel = MockTipsViewModel();
    mockHomeTeam = MockTeam();
    mockAwayTeam = MockTeam();
    realCarouselController = CarouselController();

    when(mockDAUCompsViewModelForDI.selectedDAUComp).thenReturn(mockDAUCompForListItem);
    when(mockDAUCompForListItem.daurounds).thenReturn([]); 
    when(mockDAUCompForListItem.highestRoundNumberInPast()).thenReturn(0);

    when(mockGameForListItem.homeTeam).thenReturn(mockHomeTeam);
    when(mockGameForListItem.awayTeam).thenReturn(mockAwayTeam);
    when(mockHomeTeam.dbkey).thenReturn('home-key');
    when(mockAwayTeam.dbkey).thenReturn('away-key');
    when(mockHomeTeam.name).thenReturn('Home Team');
    when(mockAwayTeam.name).thenReturn('Away Team');
    when(mockGameForListItem.league).thenReturn(League.nrl);
    when(mockGameForListItem.gameState).thenReturn(GameState.notStarted); // Default for historical card to be eligible
    when(mockGameForListItem.startTimeUTC).thenReturn(DateTime.now().add(const Duration(days: 1)));

    when(mockGameTipViewModel.game).thenReturn(mockGameForListItem); 
    when(mockGameTipViewModel.controller).thenReturn(realCarouselController);
    when(mockGameTipViewModel.currentIndex).thenReturn(0); // Initial index
    when(mockGameTipViewModel.tip).thenReturn(null); 
    when(mockGameTipViewModel.currentTipper).thenReturn(mockTipper);

    // Default: historical matchups not called / returns empty
    when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async {
      // This line helps verify if the method was actually called if not specifically stubbed otherwise
      // For initial state tests, we want to ensure it's NOT called.
      // For loading tests, it WILL be called.
      return [];
    });
  });

  Future<void> pumpGameListItem(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<GameTipViewModel>.value(
            value: mockGameTipViewModel,
            child: GameListItem(
              game: mockGameForListItem,
              currentTipper: mockTipper,
              currentDAUComp: mockDAUCompForListItem,
              allTipsViewModel: mockTipsViewModel,
              isPercentStatsPage: false,
            ),
          ),
        ),
      ),
    );
  }

  group('Historical Matchups Card Lazy Loading', () {
    testWidgets('Initial State: shows placeholder, getFormattedHistoricalMatchups not called', (WidgetTester tester) async {
      await pumpGameListItem(tester);
      await tester.pump(); // Initial build

      // The historical card is the second item (index 1)
      // When not loaded, it shows "Matchup History"
      expect(find.text("Matchup History"), findsOneWidget);
      verifyNever(mockGameTipViewModel.getFormattedHistoricalMatchups());
    });

    testWidgets('Loading Triggered: shows loading, getFormattedHistoricalMatchups called', (WidgetTester tester) async {
      Completer<List<HistoricalMatchupUIData>> historicalDataCompleter = Completer();
      when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) {
        return historicalDataCompleter.future;
      });

      await pumpGameListItem(tester);
      await tester.pump(); // Initial build, card shows "Matchup History"

      // Simulate Carousel page change to the historical card (index 1)
      final carousel = find.byType(CarouselSlider);
      expect(carousel, findsOneWidget);
      final CarouselOptions options = tester.widget<CarouselSlider>(carousel).options;
      
      // Directly call onPageChanged logic. This is the most reliable way to test the effect.
      // The actual _fetchHistoricalData is private. We test that onPageChanged, when appropriate,
      // leads to getFormattedHistoricalMatchups being called.
      // The onPageChanged callback in the widget will set currentIndex and then call _fetchHistoricalData.
      // We need to ensure our mockGameTipViewModel.currentIndex reflects the change
      // and then the conditions for _fetchHistoricalData() are met.

      // To test the trigger, we'll rely on the fact that _fetchHistoricalData calls getFormattedHistoricalMatchups.
      // So, if getFormattedHistoricalMatchups is called after the page change, the trigger worked.
      options.onPageChanged?.call(1, CarouselPageChangedReason.manual);
      when(mockGameTipViewModel.currentIndex).thenReturn(1); // Reflect the change

      await tester.pump(); // Rebuild after page change and potential setState in onPageChanged for loading

      // Verify that getFormattedHistoricalMatchups was called (due to _fetchHistoricalData being invoked)
      verify(mockGameTipViewModel.getFormattedHistoricalMatchups()).called(1);
      // And the UI shows loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      historicalDataCompleter.complete([]); // Complete the future
      await tester.pumpAndSettle(); // Settle the FutureBuilder
    });

    testWidgets('Data Displayed After Load', (WidgetTester tester) async {
      final now = DateTime.now();
      final mockPastGame = MockGame(); when(mockPastGame.dbkey).thenReturn('pg-loaded');
      final data = [
        HistoricalMatchupUIData(year: (now.year - 1).toString(), month: "Oct", winningTeamName: "Loaded Team", winType: "Home", userTipTeamName: "Loaded Team", isCurrentYear: false, pastGame: mockPastGame),
      ];
      when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async => data);

      await pumpGameListItem(tester);
      await tester.pump();

      final carousel = find.byType(CarouselSlider);
      final CarouselOptions options = tester.widget<CarouselSlider>(carousel).options;
      options.onPageChanged?.call(1, CarouselPageChangedReason.manual);
      when(mockGameTipViewModel.currentIndex).thenReturn(1);

      await tester.pumpAndSettle(); // Pump and settle for FutureBuilder

      expect(find.text("${now.year - 1} Oct: Loaded Team won (Home). You tipped Loaded Team"), findsOneWidget);
    });

    testWidgets('Error State After Load', (WidgetTester tester) async {
      when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) => Future.error('Fetch error'));

      await pumpGameListItem(tester);
      await tester.pump();

      final carousel = find.byType(CarouselSlider);
      final CarouselOptions options = tester.widget<CarouselSlider>(carousel).options;
      options.onPageChanged?.call(1, CarouselPageChangedReason.manual);
      when(mockGameTipViewModel.currentIndex).thenReturn(1);
      
      await tester.pumpAndSettle();

      expect(find.text("Error loading history."), findsOneWidget);
    });
  });

  group('Ladder Rank Deferred Calculation', () {
    testWidgets('Initial State: shows placeholder "--" for ranks', (WidgetTester tester) async {
      // Prevent _fetchAndSetLadderRanks from completing immediately
      final gamesCompleter = Completer<List<Game>>();
      when(mockGamesViewModelForDI.getGames()).thenAnswer((_) => gamesCompleter.future);
      // Ensure other DI calls for _fetchAndSetLadderRanks are fine
      when(mockDAUCompsViewModelForDI.selectedDAUComp).thenReturn(mockDAUCompForListItem);


      await pumpGameListItem(tester);
      // Initial pump for initState, then another for addPostFrameCallback to schedule.
      // Another pump might be needed for the scheduled callback to execute the async part.
      await tester.pump(); 
      
      // Ranks should be placeholders because _fetchAndSetLadderRanks hasn't completed
      // The text widgets for ranks are inside rows, check for the text directly.
      // The actual text is like "1st Home Team Name" so we look for "--"
      // The rank display logic is `displayHomeRank = _homeOrdinalRankLabel ?? (_isLoadingLadderRank ? '' : '--');`
      // Initially, _homeOrdinalRankLabel is null, _isLoadingLadderRank is false (becomes true inside fetch)
      expect(find.widgetWithText(Row, contains('-- Home Team')), findsOneWidget);
      expect(find.widgetWithText(Row, contains('-- Away Team')), findsOneWidget);
      
      // Clean up
      gamesCompleter.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('Ranks Displayed After Post-Frame Callback and Load', (WidgetTester tester) async {
      // Setup mocks for successful ladder calculation
      final homeTeamWithRank = Team(dbkey: 'home-key', name: 'Home Team', league: League.nrl); // Use real Team for LadderItem
      final awayTeamWithRank = Team(dbkey: 'away-key', name: 'Away Team', league: League.nrl);
      final calculatedLadder = LeagueLadder(league: League.nrl, teams: [
        LadderItem(teamName: 'Home Team', dbkey: 'home-key', played: 1, won: 1, points: 2, percentage: 200), // Rank 1
        LadderItem(teamName: 'Away Team', dbkey: 'away-key', played: 1, won: 0, points: 0, percentage: 50),   // Rank 2
      ]);
      // Mock the ladder service call if it were separate, but it's part of _fetchAndSetLadderRanks
      // So, ensure getGames returns quickly and other dependencies are met.
      when(mockGamesViewModelForDI.getGames()).thenAnswer((_) async => []); // Minimal games list needed
      when(mockDAUCompsViewModelForDI.selectedDAUComp).thenReturn(mockDAUCompForListItem);
      // If LadderCalculationService was injected, we'd mock it. Here, it's instantiated directly.
      // We rely on the fact that with empty games, ranks might be "--" or default.
      // For a more robust test, mock the LadderCalculationService or ensure data leads to specific ranks.
      // Let's assume for this test, empty games and teams lead to "--".
      // To test actual ranks, we need to ensure `ladderService.calculateLadder` returns specific ranks.
      // This means `leagueTeams` in `_fetchAndSetLadderRanks` needs to be populated.
      // `teamsViewModel.groupedTeams` needs to be stubbed.
      Map<String, List<Team>> groupedTeams = {
        'nrl': [homeTeamWithRank, awayTeamWithRank]
      };
      when(mockTeamsViewModelForDI.groupedTeams).thenReturn(groupedTeams);
      // And getGames should return games that result in these ranks
      final gameForLadder = Game(dbkey: 'g1', homeTeam: homeTeamWithRank, awayTeam: awayTeamWithRank, league: League.nrl, startTimeUTC: DateTime.now(), location: 'stadium', fixtureMatchNumber: 1, fixtureRoundNumber: 1, scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10));
      when(mockGamesViewModelForDI.getGames()).thenAnswer((_) async => [gameForLadder]);


      await pumpGameListItem(tester);
      await tester.pumpAndSettle(); // Allow post-frame and async fetch to complete

      expect(find.widgetWithText(Row, contains('1st Home Team')), findsOneWidget);
      expect(find.widgetWithText(Row, contains('2nd Away Team')), findsOneWidget);
    });

    testWidgets('Error State for Ranks shows "N/A"', (WidgetTester tester) async {
      when(mockGamesViewModelForDI.getGames()).thenThrow(Exception('Ladder fetch failed'));
      when(mockDAUCompsViewModelForDI.selectedDAUComp).thenReturn(mockDAUCompForListItem);

      await pumpGameListItem(tester);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Row, contains('N/A Home Team')), findsOneWidget);
      expect(find.widgetWithText(Row, contains('N/A Away Team')), findsOneWidget);
    });
  });
}
