import 'dart:async';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/scoring.dart';
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
    when(mockDAUCompsViewModelForDI.gamesViewModel)
        .thenReturn(mockGamesViewModelForDI);
    when(mockGamesViewModelForDI.teamsViewModel)
        .thenReturn(mockTeamsViewModelForDI);

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

    when(mockDAUCompsViewModelForDI.selectedDAUComp)
        .thenReturn(mockDAUCompForListItem);
    when(mockDAUCompForListItem.daurounds).thenReturn([]);
    when(mockDAUCompForListItem.highestRoundNumberInPast()).thenReturn(0);

    when(mockGameForListItem.homeTeam).thenReturn(mockHomeTeam);
    when(mockGameForListItem.awayTeam).thenReturn(mockAwayTeam);
    when(mockHomeTeam.dbkey).thenReturn('home-key');
    when(mockHomeTeam.name).thenReturn('Home Team');
    when(mockAwayTeam.name).thenReturn('Away Team');
    when(mockGameForListItem.league).thenReturn(League.nrl);
    when(mockGameForListItem.gameState).thenReturn(GameState.notStarted);
    when(mockGameForListItem.startTimeUTC)
        .thenReturn(DateTime.now().add(const Duration(days: 1)));

    when(mockGameTipViewModel.game).thenReturn(mockGameForListItem);
    when(mockGameTipViewModel.controller).thenReturn(realCarouselController);
    when(mockGameTipViewModel.currentIndex).thenReturn(0);
    when(mockGameTipViewModel.tip).thenReturn(null);
    when(mockGameTipViewModel.currentTipper).thenReturn(mockTipper);

    when(mockGameTipViewModel.getFormattedHistoricalMatchups())
        .thenAnswer((_) async => []);
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

  // Simulates the carousel being on the historical card's page, triggering its content build.
  // This is a simplified way to ensure the card content is built for testing.
  Future<void> pumpHistoricalCardContent(WidgetTester tester) async {
    // In GameListItem, the historical card is at index 1 in the carouselItems list
    // when game state is notStarted or startingSoon.
    // We need to ensure the GameListItem builds with the historical card visible.
    // The onPageChanged logic now triggers the fetch.
    // For testing the card's content *after* fetch, we can simulate the fetch completion.

    // Simulate conditions as if the card is active and data is being loaded / has loaded
    final carousel = find.byType(CarouselSlider);
    if (tester.any(carousel)) {
      final CarouselOptions options =
          tester.widget<CarouselSlider>(carousel).options;
      options.onPageChanged?.call(1, CarouselPageChangedReason.manual);
      when(mockGameTipViewModel.currentIndex)
          .thenReturn(1); // Reflect the change
    }
    await tester.pumpAndSettle(); // Allow state changes and futures to resolve
  }

  group('Historical Matchups Card Display (with DataTable)', () {
    testWidgets(
        'Initial State: shows heading and placeholder, getFormattedHistoricalMatchups not called',
        (WidgetTester tester) async {
      await pumpGameListItem(tester);
      await tester.pump();

      expect(find.text('Previous matchups'), findsOneWidget);
      expect(find.text("View history by swiping."), findsOneWidget);
      verifyNever(mockGameTipViewModel.getFormattedHistoricalMatchups());
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets(
        'Loading State: shows heading and loading indicator, getFormattedHistoricalMatchups called',
        (WidgetTester tester) async {
      Completer<List<HistoricalMatchupUIData>> historicalDataCompleter =
          Completer();
      when(mockGameTipViewModel.getFormattedHistoricalMatchups())
          .thenAnswer((_) {
        return historicalDataCompleter.future;
      });

      await pumpGameListItem(tester);
      await tester.pump();

      final carousel = find.byType(CarouselSlider);
      expect(carousel, findsOneWidget);
      final CarouselOptions options =
          tester.widget<CarouselSlider>(carousel).options;

      options.onPageChanged?.call(1, CarouselPageChangedReason.manual);
      when(mockGameTipViewModel.currentIndex).thenReturn(1);

      await tester.pump(); // Rebuild for loading state

      verify(mockGameTipViewModel.getFormattedHistoricalMatchups()).called(1);
      expect(find.text('Previous matchups'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);

      historicalDataCompleter.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('Empty State: shows heading and "No past matchups" message',
        (WidgetTester tester) async {
      when(mockGameTipViewModel.getFormattedHistoricalMatchups())
          .thenAnswer((_) async => []);

      await pumpGameListItem(tester);
      await pumpHistoricalCardContent(
          tester); // Ensure card is "active" and future resolves

      expect(find.text('Previous matchups'), findsOneWidget);
      expect(
          find.text("No past matchups found for these teams."), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets('Error State: shows heading and error message',
        (WidgetTester tester) async {
      when(mockGameTipViewModel.getFormattedHistoricalMatchups())
          .thenAnswer((_) => Future.error('Fetch error'));

      await pumpGameListItem(tester);
      await pumpHistoricalCardContent(tester);

      expect(find.text('Previous matchups'), findsOneWidget);
      expect(find.text("Error loading history."), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets(
        'Data Display: Shows DataTable with correct headers and cell content (max 3 rows)',
        (WidgetTester tester) async {
      final now = DateTime.now();
      final mockPastGame = MockGame();
      when(mockPastGame.dbkey).thenReturn('mock-past-game');

      final data = [
        HistoricalMatchupUIData(
            year: (now.year - 1).toString(),
            month: "Sep",
            winningTeamName: "Team Alpha",
            winType: "Home",
            userTip: "Team Alpha",
            isCurrentYear: false,
            pastGame: mockPastGame),
        HistoricalMatchupUIData(
            year: now.year.toString(),
            month: "Jul",
            winningTeamName: "Draw",
            winType: "Draw",
            userTip: "",
            isCurrentYear: true,
            pastGame: mockPastGame),
        HistoricalMatchupUIData(
            year: (now.year - 2).toString(),
            month: "May",
            winningTeamName: "Team Beta",
            winType: "Away",
            userTip: "Team Beta",
            isCurrentYear: false,
            pastGame: mockPastGame),
        HistoricalMatchupUIData(
            year: (now.year - 3).toString(),
            month: "Apr",
            winningTeamName: "Team Gamma",
            winType: "Home",
            userTip: "N/A",
            isCurrentYear: false,
            pastGame: mockPastGame), // Should not be shown
      ];
      when(mockGameTipViewModel.getFormattedHistoricalMatchups())
          .thenAnswer((_) async => data);

      await pumpGameListItem(tester);
      await pumpHistoricalCardContent(tester);

      expect(find.text('Previous matchups'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);

      // Verify Column Headers
      expect(find.widgetWithText(DataColumn, 'When'), findsOneWidget);
      expect(find.widgetWithText(DataColumn, 'Who won'), findsOneWidget);
      expect(find.widgetWithText(DataColumn, 'Where'), findsOneWidget);
      expect(find.widgetWithText(DataColumn, 'Your Tip'), findsOneWidget);

      // Verify Row and Cell Content (max 3 rows due to .take(3))
      final dataTable = tester.widget<DataTable>(find.byType(DataTable));
      expect(dataTable.rows.length, 3);

      // Row 1
      expect(find.text("Sep ${(now.year - 1).toString().substring(2)}"),
          findsOneWidget); // Year shortened
      expect(find.text("Team Alpha"), findsOneWidget); // Who won
      expect(
          find.text("Home"),
          findsNWidgets(
              2)); // Where (could be in other rows too if data is same)
      // Your Tip for Row 1 is also "Team Alpha"

      // Row 2
      expect(
          find.text("Jul"), findsOneWidget); // Current year, no year displayed
      expect(find.text("Draw"),
          findsNWidgets(2)); // Who won (could be in other rows)
      // Where for Row 2 is also "Draw"
      expect(
          find.text("N/A"), findsNWidgets(2)); // Your Tip (empty becomes N/A)

      // Row 3
      expect(find.text("May ${(now.year - 2).toString().substring(2)}"),
          findsOneWidget); // Year shortened
      expect(find.text("Team Beta"), findsNWidgets(2)); // Who won
      // Where for Row 3 is "Away"
      // Your Tip for Row 3 is also "Team Beta"

      // More specific cell checks:
      // Row 1
      final row1 = dataTable.rows[0];
      final row1Cells = row1.cells;
      expect(((row1Cells[0].child as Text).data),
          "Sep ${(now.year - 1).toString().substring(2)}");
      expect(((row1Cells[1].child as Text).data), "Team Alpha");
      expect(((row1Cells[2].child as Text).data), "Home");
      expect(((row1Cells[3].child as Text).data), "Team Alpha");

      // Row 2
      final row2 = dataTable.rows[1];
      final row2Cells = row2.cells;
      expect(((row2Cells[0].child as Text).data), "Jul");
      expect(((row2Cells[1].child as Text).data), "Draw");
      expect(((row2Cells[2].child as Text).data), "Draw");
      expect(((row2Cells[3].child as Text).data), "N/A");

      // Row 3
      final row3 = dataTable.rows[2];
      final row3Cells = row3.cells;
      expect(((row3Cells[0].child as Text).data),
          "May ${(now.year - 2).toString().substring(2)}");
      expect(((row3Cells[1].child as Text).data), "Team Beta");
      expect(((row3Cells[2].child as Text).data), "Away");
      expect(((row3Cells[3].child as Text).data), "Team Beta");

      // Ensure the 4th data item is NOT displayed
      expect(find.text("Apr ${(now.year - 3).toString().substring(2)}"),
          findsNothing);
      expect(find.text("Team Gamma"), findsNothing);
    });
  });

  // Ladder Rank tests remain unchanged by this subtask
  group('Ladder Rank Deferred Calculation', () {
    testWidgets('Initial State: shows placeholder "--" for ranks',
        (WidgetTester tester) async {
      final gamesCompleter = Completer<List<Game>>();
      when(mockGamesViewModelForDI.getGames())
          .thenAnswer((_) => gamesCompleter.future);
      when(mockDAUCompsViewModelForDI.selectedDAUComp)
          .thenReturn(mockDAUCompForListItem);

      await pumpGameListItem(tester);
      await tester.pump();

      expect(
          find.byWidgetPredicate((widget) =>
              widget is Row &&
              widget.children.any((child) =>
                  child is Text &&
                  (child.data?.contains('-- Home Team') ?? false))),
          findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Row &&
              widget.children.any((child) =>
                  child is Text &&
                  (child.data?.contains('-- Away Team') ?? false))),
          findsOneWidget);

      gamesCompleter.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('Ranks Displayed After Post-Frame Callback and Load',
        (WidgetTester tester) async {
      final homeTeamWithRank =
          Team(dbkey: 'home-key', name: 'Home Team', league: League.nrl);
      final awayTeamWithRank =
          Team(dbkey: 'away-key', name: 'Away Team', league: League.nrl);
      // final calculatedLadder = LeagueLadder(league: League.nrl, teams: [ // Not used directly, but informs stubbing
      //   LadderItem(teamName: 'Home Team', dbkey: 'home-key', played: 1, won: 1, points: 2, percentage: 200),
      //   LadderItem(teamName: 'Away Team', dbkey: 'away-key', played: 1, won: 0, points: 0, percentage: 50),
      // ]);
      Map<String, List<Team>> groupedTeams = {
        'nrl': [homeTeamWithRank, awayTeamWithRank]
      };
      when(mockTeamsViewModelForDI.groupedTeams).thenReturn(groupedTeams);
      final gameForLadder = Game(
          dbkey: 'g1',
          homeTeam: homeTeamWithRank,
          awayTeam: awayTeamWithRank,
          league: League.nrl,
          startTimeUTC: DateTime.now(),
          location: 'stadium',
          fixtureMatchNumber: 1,
          fixtureRoundNumber: 1,
          scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10));
      when(mockGamesViewModelForDI.getGames())
          .thenAnswer((_) async => [gameForLadder]);
      when(mockDAUCompsViewModelForDI.selectedDAUComp)
          .thenReturn(mockDAUCompForListItem);

      await pumpGameListItem(tester);
      await tester.pumpAndSettle();

      expect(
          find.byWidgetPredicate((widget) =>
              widget is Row &&
              widget.children.any((child) =>
                  child is Text &&
                  (child.data?.contains('1st Home Team') ?? false))),
          findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Row &&
              widget.children.any((child) =>
                  child is Text &&
                  (child.data?.contains('2nd Away Team') ?? false))),
          findsOneWidget);
    });

    testWidgets('Error State for Ranks shows "N/A"',
        (WidgetTester tester) async {
      when(mockGamesViewModelForDI.getGames())
          .thenThrow(Exception('Ladder fetch failed'));
      when(mockDAUCompsViewModelForDI.selectedDAUComp)
          .thenReturn(mockDAUCompForListItem);

      await pumpGameListItem(tester);
      await tester.pumpAndSettle();

      expect(
          find.byWidgetPredicate((widget) =>
              widget is Row &&
              widget.children.any((child) =>
                  child is Text &&
                  (child.data?.contains('N/A Home Team') ?? false))),
          findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Row &&
              widget.children.any((child) =>
                  child is Text &&
                  (child.data?.contains('N/A Away Team') ?? false))),
          findsOneWidget);
    });
  });
}
