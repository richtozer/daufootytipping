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
import 'package:daufootytipping/pages/user_home/user_home_tips_gameinfo.dart'; // To find GameInfo card
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart'; // To find TipChoice card
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
    when(mockGamesViewModelForDI.getGames()).thenAnswer((_) async => []); 
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
    when(mockGameForListItem.gameState).thenReturn(GameState.notStarted); 
    when(mockGameForListItem.startTimeUTC).thenReturn(DateTime.now().add(const Duration(days: 1)));

    when(mockGameTipViewModel.game).thenReturn(mockGameForListItem); 
    when(mockGameTipViewModel.controller).thenReturn(realCarouselController);
    when(mockGameTipViewModel.currentIndex).thenReturn(0); 
    when(mockGameTipViewModel.tip).thenReturn(null); 
    when(mockGameTipViewModel.currentTipper).thenReturn(mockTipper);
    
    when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async => []);
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
  
  // Helper to simulate page change and trigger data load
  Future<void> triggerHistoricalDataLoad(WidgetTester tester) async {
      final carousel = find.byType(CarouselSlider);
      if (tester.any(carousel)) {
        final CarouselOptions options = tester.widget<CarouselSlider>(carousel).options;
        options.onPageChanged?.call(2, CarouselPageChangedReason.manual); // New trigger index is 2
        when(mockGameTipViewModel.currentIndex).thenReturn(2); 
      }
      await tester.pump(); // Let the state update for loading
  }


  group('GameListItem Carousel: Historical Matchup Cards', () {
    testWidgets('Initial State: shows TipChoice and GameInfo, no historical cards, getFormattedHistoricalMatchups not called', (WidgetTester tester) async {
      await pumpGameListItem(tester);
      await tester.pump(); 

      expect(find.byType(TipChoice), findsOneWidget);
      expect(find.byType(GameInfo), findsOneWidget);
      // Verify no historical cards by checking for their specific content or titles
      expect(find.textContaining('Previous matchup'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text("Error loading history."), findsNothing);
      verifyNever(mockGameTipViewModel.getFormattedHistoricalMatchups());
    });

    testWidgets('Lazy Loading Trigger: shows loading card at index 2, getFormattedHistoricalMatchups called', (WidgetTester tester) async {
      Completer<List<HistoricalMatchupUIData>> historicalDataCompleter = Completer();
      when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) {
        return historicalDataCompleter.future;
      });

      await pumpGameListItem(tester);
      await tester.pump(); 

      await triggerHistoricalDataLoad(tester);

      verify(mockGameTipViewModel.getFormattedHistoricalMatchups()).called(1);
      
      // After triggering load, the carousel items should now include the loading card.
      // We expect TipChoice, GameInfo, then Loading Card.
      final carouselItems = tester.widget<CarouselSlider>(find.byType(CarouselSlider)).items;
      expect(carouselItems.length, 3); // TipChoice, GameInfo, Loading Card
      expect(carouselItems[0].runtimeType, TipChoice);
      expect(carouselItems[1].runtimeType, GameInfo);
      // The loading card is a Card with a CircularProgressIndicator
      expect(find.descendant(of: find.byWidget(carouselItems[2]), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      
      historicalDataCompleter.complete([]); 
      await tester.pumpAndSettle(); 
    });

    testWidgets('Data Display: Renders individual historical matchup cards after load', (WidgetTester tester) async {
      final now = DateTime.now();
      final mockPastGame = MockGame(); 
      when(mockPastGame.dbkey).thenReturn('mock-past-game');
      when(mockPastGame.location).thenReturn('Mock Stadium');


      final data = [
        HistoricalMatchupUIData(year: (now.year - 1).toString(), month: "Sep", winningTeamName: "Team Alpha", winType: "Home", userTipTeamName: "Team Alpha", isCurrentYear: false, pastGame: mockPastGame, location: "Stadium A"),
        HistoricalMatchupUIData(year: now.year.toString(), month: "Jul", winningTeamName: "Draw", winType: "Draw", userTipTeamName: "", isCurrentYear: true, pastGame: mockPastGame, location: "Stadium B"),
      ];
      when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async => data);

      await pumpGameListItem(tester);
      await triggerHistoricalDataLoad(tester);
      await tester.pumpAndSettle(); // Settle FutureBuilder/state changes

      final carouselItems = tester.widget<CarouselSlider>(find.byType(CarouselSlider)).items;
      expect(carouselItems.length, 4); // TipChoice, GameInfo, HistCard1, HistCard2
      expect(carouselItems[0].runtimeType, TipChoice);
      expect(carouselItems[1].runtimeType, GameInfo);

      // Card 1 (index 2 in carousel)
      expect(find.text('Previous matchup 1/2'), findsOneWidget);
      expect(find.text('Date: Sep ${now.year - 1}'), findsOneWidget);
      expect(find.text('Outcome: Team Alpha won (Home)'), findsOneWidget);
      expect(find.text('Venue: Stadium A'), findsOneWidget);
      expect(find.text('Your Tip: Team Alpha'), findsOneWidget);

      // Card 2 (index 3 in carousel)
      expect(find.text('Previous matchup 2/2'), findsOneWidget);
      expect(find.text('Date: Jul'), findsOneWidget); // Current year
      expect(find.text('Outcome: Match was a Draw'), findsOneWidget);
      expect(find.text('Venue: Stadium B'), findsOneWidget);
      expect(find.text('Your Tip: N/A'), findsOneWidget);
    });
    
    testWidgets('Data Display: Renders max 3 historical cards if more data available', (WidgetTester tester) async {
      final now = DateTime.now();
      final mockPastGame = MockGame(); 
      when(mockPastGame.dbkey).thenReturn('mock-past-game');
      when(mockPastGame.location).thenReturn('Mock Stadium');

      final data = [
        HistoricalMatchupUIData(year: "2023", month: "Jan", winningTeamName: "Team 1", winType: "Home", userTipTeamName: "Team 1", isCurrentYear: false, pastGame: mockPastGame, location: "Venue1"),
        HistoricalMatchupUIData(year: "2022", month: "Feb", winningTeamName: "Team 2", winType: "Away", userTipTeamName: "N/A", isCurrentYear: false, pastGame: mockPastGame, location: "Venue2"),
        HistoricalMatchupUIData(year: "2021", month: "Mar", winningTeamName: "Draw", winType: "Draw", userTipTeamName: "Draw", isCurrentYear: false, pastGame: mockPastGame, location: "Venue3"),
        HistoricalMatchupUIData(year: "2020", month: "Apr", winningTeamName: "Team 4", winType: "Home", userTipTeamName: "Team 4", isCurrentYear: false, pastGame: mockPastGame, location: "Venue4"),
      ];
      when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async => data);

      await pumpGameListItem(tester);
      await triggerHistoricalDataLoad(tester);
      await tester.pumpAndSettle();

      final carouselItems = tester.widget<CarouselSlider>(find.byType(CarouselSlider)).items;
      expect(carouselItems.length, 5); // TipChoice, GameInfo, HistCard1, HistCard2, HistCard3

      expect(find.text('Previous matchup 1/3'), findsOneWidget);
      expect(find.text('Previous matchup 2/3'), findsOneWidget);
      expect(find.text('Previous matchup 3/3'), findsOneWidget);
      expect(find.text('Previous matchup 4/4'), findsNothing); // 4th card not rendered
      expect(find.text('Date: Apr 2020'), findsNothing); 
    });


    testWidgets('Empty Historical Data: Shows TipChoice and GameInfo, no historical cards', (WidgetTester tester) async {
      when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async => []);
      
      await pumpGameListItem(tester);
      await triggerHistoricalDataLoad(tester);
      await tester.pumpAndSettle();

      final carouselItems = tester.widget<CarouselSlider>(find.byType(CarouselSlider)).items;
      expect(carouselItems.length, 2); // Only TipChoice and GameInfo
      expect(find.byType(TipChoice), findsOneWidget);
      expect(find.byType(GameInfo), findsOneWidget);
      expect(find.textContaining('Previous matchup'), findsNothing);
    });

    testWidgets('Error State for Historical Data: Shows TipChoice, GameInfo, and error card', (WidgetTester tester) async {
      when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) => Future.error('Fetch error'));

      await pumpGameListItem(tester);
      await triggerHistoricalDataLoad(tester);
      await tester.pumpAndSettle();

      final carouselItems = tester.widget<CarouselSlider>(find.byType(CarouselSlider)).items;
      expect(carouselItems.length, 3); // TipChoice, GameInfo, Error Card
      expect(carouselItems[0].runtimeType, TipChoice);
      expect(carouselItems[1].runtimeType, GameInfo);
      expect(find.descendant(of: find.byWidget(carouselItems[2]), matching: find.text("Error loading history.")), findsOneWidget);
    });
  });

  // Ladder Rank tests can remain as they test a different aspect and are not directly affected by carousel item changes for historical data
  group('Ladder Rank Deferred Calculation', () {
    testWidgets('Initial State: shows placeholder "--" for ranks', (WidgetTester tester) async {
      final gamesCompleter = Completer<List<Game>>();
      when(mockGamesViewModelForDI.getGames()).thenAnswer((_) => gamesCompleter.future);
      when(mockDAUCompsViewModelForDI.selectedDAUComp).thenReturn(mockDAUCompForListItem);

      await pumpGameListItem(tester);
      await tester.pump(); 
      
      expect(find.widgetWithText(Row, contains('-- Home Team')), findsOneWidget);
      expect(find.widgetWithText(Row, contains('-- Away Team')), findsOneWidget);
      
      gamesCompleter.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('Ranks Displayed After Post-Frame Callback and Load', (WidgetTester tester) async {
      final homeTeamWithRank = Team(dbkey: 'home-key', name: 'Home Team', league: League.nrl); 
      final awayTeamWithRank = Team(dbkey: 'away-key', name: 'Away Team', league: League.nrl);
      Map<String, List<Team>> groupedTeams = {
        'nrl': [homeTeamWithRank, awayTeamWithRank]
      };
      when(mockTeamsViewModelForDI.groupedTeams).thenReturn(groupedTeams);
      final gameForLadder = Game(dbkey: 'g1', homeTeam: homeTeamWithRank, awayTeam: awayTeamWithRank, league: League.nrl, startTimeUTC: DateTime.now(), location: 'stadium', fixtureMatchNumber: 1, fixtureRoundNumber: 1, scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10));
      when(mockGamesViewModelForDI.getGames()).thenAnswer((_) async => [gameForLadder]);
      when(mockDAUCompsViewModelForDI.selectedDAUComp).thenReturn(mockDAUCompForListItem);

      await pumpGameListItem(tester);
      await tester.pumpAndSettle(); 

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
