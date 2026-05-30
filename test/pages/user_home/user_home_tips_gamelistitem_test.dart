import 'package:carousel_slider/carousel_controller.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/scoring.dart';
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

void main() {
  late MockDAUCompsViewModel mockDauCompsViewModel;
  late MockGameTipViewModel mockGameTipViewModel;
  late MockTipsViewModel mockTipsViewModel;
  late Game game;
  late DAUComp currentComp;
  late DAUComp previousComp;
  late Tipper currentTipper;
  late LeagueLadder currentLadder;

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
