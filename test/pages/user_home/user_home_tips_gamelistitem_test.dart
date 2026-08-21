import 'dart:async';

import 'package:carousel_slider/carousel_controller.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}
class MockGameTipViewModel extends Mock implements GameTipViewModel {}
class MockTipsViewModel extends Mock implements TipsViewModel {}
class MockStatsViewModel extends Mock implements StatsViewModel {}

void main() {
  late MockDAUCompsViewModel mockDauCompsViewModel;
  late MockGameTipViewModel mockGameTipViewModel;
  late MockTipsViewModel mockTipsViewModel;
  late Game game;
  late DAUComp currentComp;
  late DAUComp previousComp;
  late Tipper currentTipper;
  late LeagueLadder currentLadder;
  late ValueNotifier<int> ladderRevision;

  LeagueLadder buildLadder(List<String> orderedTeamKeys) {
    return LeagueLadder(
      league: League.nrl,
      teams: [
        for (final teamKey in orderedTeamKeys)
          LadderTeam(dbkey: teamKey, teamName: teamKey),
      ],
    );
  }

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    mockDauCompsViewModel = MockDAUCompsViewModel();
    mockGameTipViewModel = MockGameTipViewModel();
    mockTipsViewModel = MockTipsViewModel();
    ladderRevision = ValueNotifier<int>(0);

    final homeTeam = Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl);
    final awayTeam = Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl);

    game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      location: 'Test Oval',
      startTimeUTC: DateTime.now().toUtc().add(const Duration(days: 2)),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: 0, awayTeamScore: 0),
    );

    previousComp = DAUComp(
      dbkey: 'comp-0',
      name: 'Previous Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl-0'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl-0'),
      daurounds: const [],
    );

    currentComp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );

    currentTipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: [currentComp],
      authuid: 'auth-1',
      email: 'tipper@example.com',
      name: 'Tipper',
      tipperRole: TipperRole.tipper,
    );

    currentLadder = buildLadder([
      game.homeTeam.dbkey,
      game.awayTeam.dbkey,
    ]);

    when(
      () => mockDauCompsViewModel.getOrCalculateLeagueLadder(
        League.nrl,
        forceRecalculate: any(named: 'forceRecalculate'),
      ),
    ).thenAnswer((_) async => currentLadder);
    when(
      () => mockDauCompsViewModel.leagueLadderRevision,
    ).thenReturn(ladderRevision);

    when(() => mockGameTipViewModel.game).thenReturn(game);
    when(() => mockGameTipViewModel.tip).thenReturn(null);
    when(() => mockGameTipViewModel.savingTip).thenReturn(false);
    when(
      () => mockGameTipViewModel.controller,
    ).thenReturn(CarouselSliderController());

    di.registerSingleton<DAUCompsViewModel>(mockDauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('uses cached ladder from DAUCompsViewModel to render ranks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Provider<StatsViewModel?>.value(
          value: null,
          child: Scaffold(
            body: GameListItem(
              game: game,
              currentTipper: currentTipper,
              currentDAUComp: currentComp,
              allTipsViewModel: mockTipsViewModel,
              isPercentStatsPage: false,
              gameTipViewModel: mockGameTipViewModel,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('1st'), findsOneWidget);
    expect(find.text('2nd'), findsOneWidget);
    verify(
      () => mockDauCompsViewModel.getOrCalculateLeagueLadder(
        League.nrl,
        forceRecalculate: false,
      ),
    ).called(1);
    verify(() => mockDauCompsViewModel.leagueLadderRevision).called(1);
    verifyNoMoreInteractions(mockDauCompsViewModel);
  });

  testWidgets('refetches ladder ranks when the displayed comp changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Provider<StatsViewModel?>.value(
          value: null,
          child: Scaffold(
            body: GameListItem(
              game: game,
              currentTipper: currentTipper,
              currentDAUComp: previousComp,
              allTipsViewModel: mockTipsViewModel,
              isPercentStatsPage: false,
              gameTipViewModel: mockGameTipViewModel,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('1st'), findsOneWidget);
    expect(find.text('2nd'), findsOneWidget);

    currentLadder = buildLadder([
      'nrl-filler-1',
      'nrl-filler-2',
      'nrl-filler-3',
      game.awayTeam.dbkey,
      'nrl-filler-4',
      'nrl-filler-5',
      game.homeTeam.dbkey,
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Provider<StatsViewModel?>.value(
          value: null,
          child: Scaffold(
            body: GameListItem(
              game: game,
              currentTipper: currentTipper,
              currentDAUComp: currentComp,
              allTipsViewModel: mockTipsViewModel,
              isPercentStatsPage: false,
              gameTipViewModel: mockGameTipViewModel,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('4th'), findsOneWidget);
    expect(find.text('7th'), findsOneWidget);
    expect(find.text('1st'), findsNothing);
    expect(find.text('2nd'), findsNothing);
    verify(
      () => mockDauCompsViewModel.getOrCalculateLeagueLadder(
        League.nrl,
        forceRecalculate: false,
      ),
    ).called(2);
  });

  testWidgets('refetches ladder ranks when fixture scores invalidate the ladder', (
    tester,
  ) async {
    Widget buildSubject() => MaterialApp(
      home: Provider<StatsViewModel?>.value(
        value: null,
        child: Scaffold(
          body: GameListItem(
            game: game,
            currentTipper: currentTipper,
            currentDAUComp: currentComp,
            allTipsViewModel: mockTipsViewModel,
            isPercentStatsPage: false,
            gameTipViewModel: mockGameTipViewModel,
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildSubject());
    await tester.pump();
    await tester.pump();

    expect(find.text('1st'), findsOneWidget);
    expect(find.text('2nd'), findsOneWidget);

    currentLadder = buildLadder([
      'nrl-filler-1',
      'nrl-filler-2',
      game.awayTeam.dbkey,
      'nrl-filler-3',
      game.homeTeam.dbkey,
    ]);
    ladderRevision.value++;

    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('3rd'), findsOneWidget);
    expect(find.text('5th'), findsOneWidget);
    expect(find.text('1st'), findsNothing);
    expect(find.text('2nd'), findsNothing);
  });

  testWidgets('replaces percentage spinners when game stats arrive', (
    tester,
  ) async {
    final statsViewModel = MockStatsViewModel();
    final directLoad = Completer<GameStatsEntry?>();
    GameStatsEntry? gameStatsEntry;
    late VoidCallback statsListener;
    when(() => statsViewModel.addListener(any())).thenAnswer((invocation) {
      statsListener = invocation.positionalArguments[0] as VoidCallback;
    });
    when(() => statsViewModel.removeListener(any())).thenReturn(null);
    when(
      () => statsViewModel.gameStatsEntryFor(game),
    ).thenAnswer((_) => gameStatsEntry);
    when(
      () => statsViewModel.loadGamesStatsEntry(game, false),
    ).thenAnswer((_) => directLoad.future);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StatsViewModel?>.value(
          value: statsViewModel,
          child: Scaffold(
            body: GameListItem(
              game: game,
              currentTipper: currentTipper,
              currentDAUComp: currentComp,
              allTipsViewModel: mockTipsViewModel,
              isPercentStatsPage: true,
              gameTipViewModel: mockGameTipViewModel,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNWidgets(5));
    verify(() => statsViewModel.loadGamesStatsEntry(game, false)).called(1);

    gameStatsEntry = GameStatsEntry(
      percentageTippedHomeMargin: 0.035,
      percentageTippedHome: 0.772,
      percentageTippedDraw: 0,
      percentageTippedAway: 0.193,
      percentageTippedAwayMargin: 0,
    );
    statsListener();
    directLoad.complete(gameStatsEntry);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('3.5%'), findsOneWidget);
    expect(find.text('77.2%'), findsOneWidget);
    expect(find.text('0.0%'), findsNWidgets(2));
    expect(find.text('19.3%'), findsOneWidget);
  });

  testWidgets(
    'renders first percentage card from its direct stats read',
    (tester) async {
      final statsViewModel = MockStatsViewModel();
      final directEntry = GameStatsEntry(
        percentageTippedHomeMargin: 0.035,
        percentageTippedHome: 0.772,
        percentageTippedDraw: 0,
        percentageTippedAway: 0.193,
        percentageTippedAwayMargin: 0,
      );
      when(() => statsViewModel.addListener(any())).thenReturn(null);
      when(() => statsViewModel.removeListener(any())).thenReturn(null);
      when(() => statsViewModel.gameStatsEntryFor(game)).thenReturn(null);
      when(
        () => statsViewModel.loadGamesStatsEntry(game, false),
      ).thenAnswer((_) async => directEntry);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StatsViewModel?>.value(
            value: statsViewModel,
            child: Scaffold(
              body: GameListItem(
                game: game,
                currentTipper: currentTipper,
                currentDAUComp: currentComp,
                allTipsViewModel: mockTipsViewModel,
                isPercentStatsPage: true,
                gameTipViewModel: mockGameTipViewModel,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('3.5%'), findsOneWidget);
      expect(find.text('77.2%'), findsOneWidget);
      expect(find.text('19.3%'), findsOneWidget);
      verify(
        () => statsViewModel.loadGamesStatsEntry(game, false),
      ).called(1);
    },
  );

  testWidgets(
    'replaces percentage spinners when the direct read completes missing',
    (tester) async {
      final statsViewModel = MockStatsViewModel();
      when(() => statsViewModel.addListener(any())).thenReturn(null);
      when(() => statsViewModel.removeListener(any())).thenReturn(null);
      when(() => statsViewModel.gameStatsEntryFor(game)).thenReturn(null);
      when(
        () => statsViewModel.loadGamesStatsEntry(game, false),
      ).thenAnswer((_) async => null);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StatsViewModel?>.value(
            value: statsViewModel,
            child: Scaffold(
              body: GameListItem(
                game: game,
                currentTipper: currentTipper,
                currentDAUComp: currentComp,
                allTipsViewModel: mockTipsViewModel,
                isPercentStatsPage: true,
                gameTipViewModel: mockGameTipViewModel,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('?'), findsNWidgets(5));
    },
  );

  testWidgets('requests percentage stats when stats view model becomes ready', (
    tester,
  ) async {
    final statsViewModel = MockStatsViewModel();
    final currentStatsViewModel = ValueNotifier<StatsViewModel?>(null);
    addTearDown(currentStatsViewModel.dispose);
    when(() => statsViewModel.addListener(any())).thenReturn(null);
    when(() => statsViewModel.removeListener(any())).thenReturn(null);
    when(() => statsViewModel.gameStatsEntryFor(game)).thenReturn(null);
    when(
      () => statsViewModel.loadGamesStatsEntry(game, false),
    ).thenAnswer((_) async => null);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<StatsViewModel?>(
          valueListenable: currentStatsViewModel,
          builder: (context, value, child) {
            return ChangeNotifierProvider<StatsViewModel?>.value(
              value: value,
              child: Scaffold(
                body: GameListItem(
                  game: game,
                  currentTipper: currentTipper,
                  currentDAUComp: currentComp,
                  allTipsViewModel: mockTipsViewModel,
                  isPercentStatsPage: true,
                  gameTipViewModel: mockGameTipViewModel,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    verifyNever(() => statsViewModel.loadGamesStatsEntry(game, false));

    currentStatsViewModel.value = statsViewModel;
    await tester.pump();
    await tester.pump();

    verify(() => statsViewModel.loadGamesStatsEntry(game, false)).called(1);
  });

  testWidgets(
    'does not show an endless spinner when an untipped game starts',
    (tester) async {
      Widget buildSubject() {
        return MaterialApp(
          home: Provider<StatsViewModel?>.value(
            value: null,
            child: Scaffold(
              body: GameListItem(
                game: game,
                currentTipper: currentTipper,
                currentDAUComp: currentComp,
                allTipsViewModel: mockTipsViewModel,
                isPercentStatsPage: false,
                gameTipViewModel: mockGameTipViewModel,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildSubject());
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      game = Game(
        dbkey: game.dbkey,
        league: game.league,
        homeTeam: game.homeTeam,
        awayTeam: game.awayTeam,
        location: game.location,
        startTimeUTC: DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        ),
        fixtureRoundNumber: game.fixtureRoundNumber,
        fixtureMatchNumber: game.fixtureMatchNumber,
        scoring: game.scoring,
      );
      when(() => mockGameTipViewModel.game).thenReturn(game);
      await tester.pumpWidget(buildSubject());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'shows interim banner for crowdsourced scores even after live window',
    (tester) async {
      final liveScoredGame = Game(
        dbkey: 'nrl-01-002',
        league: League.nrl,
        homeTeam: game.homeTeam,
        awayTeam: game.awayTeam,
        location: game.location,
        startTimeUTC: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 2,
        scoring: Scoring(
          homeTeamScore: null,
          awayTeamScore: null,
          crowdSourcedScores: [
            CrowdSourcedScore(
              DateTime.now().toUtc(),
              ScoringTeam.home,
              currentTipper.dbkey!,
              20,
              false,
            ),
          ],
        ),
      );

      currentLadder = buildLadder([
        liveScoredGame.homeTeam.dbkey,
        liveScoredGame.awayTeam.dbkey,
      ]);
      when(() => mockGameTipViewModel.game).thenReturn(liveScoredGame);

      await tester.pumpWidget(
        MaterialApp(
          home: Provider<StatsViewModel?>.value(
            value: null,
            child: Scaffold(
              body: GameListItem(
                game: liveScoredGame,
                currentTipper: currentTipper,
                currentDAUComp: currentComp,
                allTipsViewModel: mockTipsViewModel,
                isPercentStatsPage: false,
                gameTipViewModel: mockGameTipViewModel,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(_findBanner('* Interim'), findsOneWidget);
      expect(_findBanner('Live'), findsNothing);
    },
  );

  testWidgets('hides interim banner once fixture scores are available', (
    tester,
  ) async {
    final finalScoredGame = Game(
      dbkey: 'nrl-01-003',
      league: League.nrl,
      homeTeam: game.homeTeam,
      awayTeam: game.awayTeam,
      location: game.location,
      startTimeUTC: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 3,
      scoring: Scoring(
        homeTeamScore: 28,
        awayTeamScore: 18,
        crowdSourcedScores: [
          CrowdSourcedScore(
            DateTime.now().toUtc(),
            ScoringTeam.home,
            currentTipper.dbkey!,
            20,
            false,
          ),
        ],
      ),
    );

    currentLadder = buildLadder([
      finalScoredGame.homeTeam.dbkey,
      finalScoredGame.awayTeam.dbkey,
    ]);
    when(() => mockGameTipViewModel.game).thenReturn(finalScoredGame);

    await tester.pumpWidget(
      MaterialApp(
        home: Provider<StatsViewModel?>.value(
          value: null,
          child: Scaffold(
            body: GameListItem(
              game: finalScoredGame,
              currentTipper: currentTipper,
              currentDAUComp: currentComp,
              allTipsViewModel: mockTipsViewModel,
              isPercentStatsPage: false,
              gameTipViewModel: mockGameTipViewModel,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(_findBanner('* Interim'), findsNothing);
  });
}

Finder _findBanner(String message) {
  return find.byWidgetPredicate(
    (widget) => widget is Banner && widget.message == message,
  );
}
