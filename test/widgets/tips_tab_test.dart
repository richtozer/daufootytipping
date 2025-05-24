import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart'; // Still import mockito for the 'Mock' class
import 'package:watch_it/watch_it.dart';

// Manual Mocks
// We extend Mockito's Mock class to get 'when' and other functionalities,
// but we won't use build_runner to generate specific mock classes.
class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}
class MockTippersViewModel extends Mock implements TippersViewModel {}
class MockTipsViewModel extends Mock implements TipsViewModel {}
class MockGamesViewModel extends Mock implements GamesViewModel {}
class MockTeamsViewModel extends Mock implements TeamsViewModel {}
class MockStatsViewModel extends Mock implements StatsViewModel {}

// For models, we'll typically use real instances with test data,
// unless they have complex behavior that needs mocking.
// For this test, real model instances are generally sufficient.

void main() {
  late MockDAUCompsViewModel mockDauCompsViewModel;
  late MockTippersViewModel mockTippersViewModel;
  late MockTipsViewModel mockTipsViewModel;
  late MockGamesViewModel mockGamesViewModel;
  late MockTeamsViewModel mockTeamsViewModel;
  late MockStatsViewModel mockStatsViewModel;

  // Test data instances for models
  late DAUComp testDauComp;
  late DAURound testDauRound;
  late Game testNrlGame;
  late Game testAflGame;
  late Team nrlHomeTeam, nrlAwayTeam, aflHomeTeam, aflAwayTeam;
  late Tipper testTipper;
  late Tip nrlTip, aflTip;

  setUpAll(() {
    mockDauCompsViewModel = MockDAUCompsViewModel();
    mockTippersViewModel = MockTippersViewModel();
    mockTipsViewModel = MockTipsViewModel();
    mockGamesViewModel = MockGamesViewModel();
    mockTeamsViewModel = MockTeamsViewModel();
    mockStatsViewModel = MockStatsViewModel();

    di.registerSingleton<DAUCompsViewModel>(mockDauCompsViewModel);
    di.registerSingleton<TippersViewModel>(mockTippersViewModel);
    // TipsViewModel might be provided via DAUCompsViewModel.selectedTipperTipsViewModel
    // GamesViewModel and TeamsViewModel are usually part of DAUCompsViewModel
    // StatsViewModel is also part of DAUCompsViewModel or provided via it

    // Initialize test data
    nrlHomeTeam = Team(dbkey: 'nrlh1', name: 'NRL Home', shortName: 'NRH', logoURI: 'path/nrl_home.svg', league: League.nrl);
    nrlAwayTeam = Team(dbkey: 'nrla1', name: 'NRL Away', shortName: 'NRA', logoURI: 'path/nrl_away.svg', league: League.nrl);
    aflHomeTeam = Team(dbkey: 'aflh1', name: 'AFL Home', shortName: 'AFH', logoURI: 'path/afl_home.svg', league: League.afl);
    aflAwayTeam = Team(dbkey: 'afla1', name: 'AFL Away', shortName: 'AFA', logoURI: 'path/afl_away.svg', league: League.afl);

    testNrlGame = Game(
        dbkey: 'nrlg1',
        league: League.nrl,
        homeTeam: nrlHomeTeam,
        awayTeam: nrlAwayTeam,
        startTimeUTC: DateTime.now().add(const Duration(days: 1)),
        gameState: GameState.notStarted,
        roundNumber: 1,
        venue: 'NRL Venue');

    testAflGame = Game(
        dbkey: 'aflg1',
        league: League.afl,
        homeTeam: aflHomeTeam,
        awayTeam: aflAwayTeam,
        startTimeUTC: DateTime.now().add(const Duration(days: 1)),
        gameState: GameState.notStarted,
        roundNumber: 1,
        venue: 'AFL Venue');
    
    // Initialize DAURound with actual games lists
    testDauRound = DAURound(
        dbkey: 'r1',
        roundNumber: 1,
        name: 'Round 1',
        compDbKey: 'comp1',
        nrlGames: [testNrlGame], // Pass the actual list
        aflGames: [testAflGame], // Pass the actual list
        roundStartDate: DateTime.now(),
        roundEndDate: DateTime.now().add(const Duration(days: 2)),
        roundState: RoundState.open
    );
    // No need to mock getGamesForLeague if we initialize DAURound with game lists directly.
    // DAURound's constructor or a method should handle setting these up internally.
    // If DAURound.getGamesForLeague is what GameListBuilder uses, ensure it works with this setup.
    // For this example, assume GameListBuilder gets games from dauCompsViewModel.groupGamesIntoLeagues


    testDauComp = DAUComp(
        dbkey: 'comp1',
        name: 'Test Competition',
        daurounds: [testDauRound],
        season: DateTime.now().year.toString(),
        isCurrent: true,
        leagueOrder: [League.nrl, League.afl]
    );

    testTipper = Tipper(dbkey: 'tipper1', name: 'Test Tipper', email: 'test@tipper.com');
    nrlTip = Tip(dbkey: 'tip_nrl1', gameDbkey: testNrlGame.dbkey, tipperDbkey: testTipper.dbkey, tipTeamDbkey: nrlHomeTeam.dbkey, tipMargin: 10, isCorrect: false, points: 0);
    aflTip = Tip(dbkey: 'tip_afl1', gameDbkey: testAflGame.dbkey, tipperDbkey: testTipper.dbkey, tipTeamDbkey: aflHomeTeam.dbkey, tipMargin: 5, isCorrect: false, points: 0);

    // Stubbing for ViewModels
    when(mockDauCompsViewModel.selectedDAUComp).thenReturn(testDauComp);
    when(mockDauCompsViewModel.activeDAUComp).thenReturn(testDauComp);
    when(mockDauCompsViewModel.gamesViewModel).thenReturn(mockGamesViewModel);
    when(mockGamesViewModel.teamsViewModel).thenReturn(mockTeamsViewModel);
    when(mockDauCompsViewModel.statsViewModel).thenReturn(mockStatsViewModel);
    
    // This is crucial for GameListBuilder
    when(mockDauCompsViewModel.groupGamesIntoLeagues(testDauRound))
        .thenReturn({League.nrl: [testNrlGame], League.afl: [testAflGame]});
    
    when(mockGamesViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(mockTeamsViewModel.initialLoadComplete).thenAnswer((_) async {});

    when(mockTippersViewModel.selectedTipper).thenReturn(testTipper);
    when(mockDauCompsViewModel.selectedTipperTipsViewModel).thenReturn(mockTipsViewModel);
    
    when(mockTipsViewModel.getTip(testNrlGame)).thenAnswer((_) async => nrlTip);
    when(mockTipsViewModel.getTip(testAflGame)).thenAnswer((_) async => aflTip);

    // Default stub for pixelHeightUpToRound and highestRoundNumberInPast
    when(mockDauCompsViewModel.selectedDAUComp?.pixelHeightUpToRound(any)).thenReturn(100.0);
    when(mockDauCompsViewModel.selectedDAUComp?.highestRoundNumberInPast()).thenReturn(0);
    
    // Stubbing for DAUComp methods if accessed directly on the object from selectedDAUComp
    // This is safer as the selectedDAUComp is a real object.
    // For example, if TipsTab's initState calls these on the real testDauComp:
    // testDauComp.pixelHeightUpToRound = (roundNum) => 100.0; // This won't work as it's not a setter.
    // Instead, ensure DAUComp's methods work as expected or simplify the test data.
    // For this test, we rely on the DAUCompsViewModel stubs for these values if possible.
    // TipsTab's initState uses daucompsViewModel.selectedDAUComp!.pixelHeightUpToRound and highestRoundNumberInPast
    // So, the stubs on mockDauCompsViewModel.selectedDAUComp (if it were a mock) would be needed.
    // Since it's a real object, these methods should just work if DAUComp is well-defined.
    // If DAUComp itself is complex, it might need to be a mock too. For now, assume its methods are simple getters/setters or direct calculations.
    // For the test, we'll rely on the fact that testDauComp.daurounds is populated.
  });

  tearDownAll(() {
    di.reset(dispose: true); // Clears all registered singletons
  });

  testWidgets('TipsTab builds correctly and finds child widgets', (WidgetTester tester) async {
    // Act
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TipsTab(),
        ),
      ),
    );

    // Assert
    expect(find.byType(TipsTab), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SliverVariedExtentList), findsOneWidget);

    await tester.pumpAndSettle(); // Allow GameListBuilder and its children to build

    // For 1 DAURound, we expect 2 GameListBuilders (one for NRL, one for AFL)
    expect(find.byType(GameListBuilder), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('TipsTab shows "Nothing to see here" when selectedDAUComp is null initially', (WidgetTester tester) async {
    // Arrange: Override selectedDAUComp to be null
    when(mockDauCompsViewModel.selectedDAUComp).thenReturn(null);
    when(mockDauCompsViewModel.activeDAUComp).thenReturn(null); 

    // Act
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TipsTab(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('Nothing to see here.\nContact support: https://interview.coach/tipping.'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
