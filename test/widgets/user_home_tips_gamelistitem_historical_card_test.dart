import 'dart:async';

import 'package:carousel_slider/carousel_controller.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
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

// Assuming HistoricalMatchupUIData is accessible; it's in 'gametip_viewmodel.dart'

@GenerateMocks([
  GameTipViewModel,
  Game, // For GameListItem.game and GameTipViewModel.game
  Tipper, // For GameListItem.currentTipper
  DAUComp, // For GameListItem.currentDAUComp
  TipsViewModel, // For GameListItem.allTipsViewModel
  Team, // For Game's teams
  // CarouselController, // Use real one
  // For DI in _initLeagueLadder
  DAUCompsViewModel,
  GamesViewModel,
  TeamsViewModel,
])
import 'user_home_tips_gamelistitem_historical_card_test.mocks.dart';

final getIt = GetIt.instance;

void main() {
  late MockGameTipViewModel mockGameTipViewModel;
  late MockGame mockGameForListItem; // Game passed to GameListItem
  late MockTipper mockTipper;
  late MockDAUComp mockDAUCompForListItem; // Renamed to avoid confusion
  late MockTipsViewModel mockTipsViewModel;
  late MockTeam mockHomeTeam;
  late MockTeam mockAwayTeam;
  late CarouselController realCarouselController;

  // Mocks for handling _initLeagueLadder DI calls
  late MockDAUCompsViewModel mockDAUCompsViewModelForDI;
  late MockGamesViewModel mockGamesViewModelForDI;
  late MockTeamsViewModel mockTeamsViewModelForDI;


  setUpAll(() {
    getIt.allowReassignment = true;
    // Register mocks for _initLeagueLadder
    mockDAUCompsViewModelForDI = MockDAUCompsViewModel();
    mockGamesViewModelForDI = MockGamesViewModel();
    mockTeamsViewModelForDI = MockTeamsViewModel();

    getIt.registerSingleton<DAUCompsViewModel>(mockDAUCompsViewModelForDI);
    // This GamesViewModel is for _initLeagueLadder via DAUCompsViewModel
    when(mockDAUCompsViewModelForDI.gamesViewModel).thenReturn(mockGamesViewModelForDI);
    when(mockGamesViewModelForDI.teamsViewModel).thenReturn(mockTeamsViewModelForDI);
    
    // Default stubs for DI view models
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

    // Ensure selectedDAUComp for _initLeagueLadder uses the current mockDAUCompForListItem
    when(mockDAUCompsViewModelForDI.selectedDAUComp).thenReturn(mockDAUCompForListItem);
    // Provide a default for daurounds if accessed by GameTipViewModel constructor through currentDAUComp
    when(mockDAUCompForListItem.daurounds).thenReturn([]); 
    when(mockDAUCompForListItem.highestRoundNumberInPast()).thenReturn(0);


    // Default stubs for Game
    when(mockGameForListItem.homeTeam).thenReturn(mockHomeTeam);
    when(mockGameForListItem.awayTeam).thenReturn(mockAwayTeam);
    when(mockHomeTeam.dbkey).thenReturn('home-key');
    when(mockAwayTeam.dbkey).thenReturn('away-key');
    when(mockHomeTeam.name).thenReturn('Home Team');
    when(mockAwayTeam.name).thenReturn('Away Team');
    when(mockGameForListItem.league).thenReturn(League.nrl);
    // CRITICAL: For the historical card to show, gameState must be notStarted or startingSoon
    when(mockGameForListItem.gameState).thenReturn(GameState.notStarted);
    when(mockGameForListItem.startTimeUTC).thenReturn(DateTime.now().add(const Duration(days: 1)));


    // Default stubs for GameTipViewModel
    // The GameTipViewModel reads properties from the 'game' object passed to it.
    // So, mockGameTipViewModel.game should return a game that itself has stubbed properties.
    // We use a separate MockGame for this internal game if needed, or ensure mockGameForListItem has all properties.
    // For GameInfo, it uses gameTipsViewModelConsumer.game.
    when(mockGameTipViewModel.game).thenReturn(mockGameForListItem); 
    when(mockGameTipViewModel.controller).thenReturn(realCarouselController);
    when(mockGameTipViewModel.currentIndex).thenReturn(0); 
    when(mockGameTipViewModel.tip).thenReturn(null); 
    when(mockGameTipViewModel.currentTipper).thenReturn(mockTipper);


    // Default stub for getFormattedHistoricalMatchups
    when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async => []);
  });

  Future<void> pumpGameListItem(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<GameTipViewModel>.value(
            value: mockGameTipViewModel,
            child: GameListItem(
              game: mockGameForListItem, // Use the fully stubbed game
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
  
  Finder findHistoricalCard() {
    // This finder assumes the historical card is the one that eventually contains specific text,
    // or a progress indicator. It's better to add a Key to the Card in the main code.
    // For now, we search for distinctive content.
    return find.byWidgetPredicate((widget) {
        if (widget is Card) {
            // Check children for known content of the historical card
            final textFinders = [
                find.text("No past matchups found for these teams.", skipOffstage: false),
                find.text("Error loading historical matchups.", skipOffstage: false),
            ];
            final progressFinder = find.byType(CircularProgressIndicator, skipOffstage: false);
            final listViewFinder = find.byType(ListView, skipOffstage: false);

            bool found = false;
            for (var textFinder in textFinders) {
                if (tester.any(find.descendant(of: find.byWidget(widget), matching: textFinder))) {
                    found = true;
                    break;
                }
            }
            if (found) return true;
            if (tester.any(find.descendant(of: find.byWidget(widget), matching: progressFinder))) return true;
            if (tester.any(find.descendant(of: find.byWidget(widget), matching: listViewFinder))) return true;
        }
        return false;
    });
  }


  testWidgets('Loading state shows CircularProgressIndicator', (WidgetTester tester) async {
    final completer = Completer<List<HistoricalMatchupUIData>>();
    when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) => completer.future);

    await pumpGameListItem(tester);
    // The CarouselSlider builds its viewport based on the items.
    // The _buildNewHistoricalMatchupsCard is one of these items.
    // Pumping once should be enough to build the initial state of FutureBuilder.
    await tester.pump(); 

    // Locate the specific card that should contain the progress indicator.
    // This is tricky without a key. We assume it's the one.
    expect(find.descendant(of: findHistoricalCard(), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    
    completer.complete([]); 
    await tester.pumpAndSettle(); 
  });

  testWidgets('Empty state shows "No past matchups" message', (WidgetTester tester) async {
    when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async => []);

    await pumpGameListItem(tester);
    await tester.pumpAndSettle(); 

    expect(find.text("No past matchups found for these teams."), findsOneWidget);
  });

  testWidgets('Error state shows error message', (WidgetTester tester) async {
    when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) => Future.error('Test error'));

    await pumpGameListItem(tester);
    await tester.pumpAndSettle(); 

    expect(find.text("Error loading historical matchups."), findsOneWidget);
  });

  testWidgets('Data Display: Correctly formats and displays historical matchups', (WidgetTester tester) async {
    final now = DateTime.now();
    final mockPastGame = MockGame(); // Dummy game for HistoricalMatchupUIData
    when(mockPastGame.dbkey).thenReturn('mock-past-game');

    final data = [
      HistoricalMatchupUIData(
        year: (now.year - 1).toString(), month: "Mar", winningTeamName: "Past Winner A", 
        winType: "Home", userTipTeamName: "Past Winner A", isCurrentYear: false, pastGame: mockPastGame
      ),
      HistoricalMatchupUIData(
        year: now.year.toString(), month: "Jul", winningTeamName: "Draw", 
        winType: "Draw", userTipTeamName: "", isCurrentYear: true, pastGame: mockPastGame
      ),
       HistoricalMatchupUIData(
        year: now.year.toString(), month: "Aug", winningTeamName: "Current Winner B", 
        winType: "Away", userTipTeamName: "Other Team", isCurrentYear: true, pastGame: mockPastGame
      ),
    ];
    when(mockGameTipViewModel.getFormattedHistoricalMatchups()).thenAnswer((_) async => data);

    await pumpGameListItem(tester);
    await tester.pumpAndSettle();

    // Ensure the ListView is present within the card.
    expect(find.descendant(of: findHistoricalCard(), matching: find.byType(ListView)), findsOneWidget);
    
    expect(find.text("${now.year - 1} Mar: Past Winner A won (Home). You tipped Past Winner A"), findsOneWidget);
    expect(find.text("Jul: Match was a Draw"), findsOneWidget);
    expect(find.text("Aug: Current Winner B won (Away). You tipped Other Team"), findsOneWidget);
  });
}
