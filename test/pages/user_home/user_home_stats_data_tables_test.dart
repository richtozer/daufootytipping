import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_historical.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundgamescoresfortipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundmissingtipsstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundpointsfortipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:daufootytipping/pages/user_home/user_home_team_games_history_page.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/load_tips_fonts.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockStatsViewModel extends Mock implements StatsViewModel {}

class MockTeamsViewModel extends Mock implements TeamsViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  setUpAll(() => loadTipsFonts(includeFallbacks: true));
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockGamesViewModel gamesViewModel;
  late MockStatsViewModel statsViewModel;
  late MockTeamsViewModel teamsViewModel;
  late MockTippersViewModel tippersViewModel;
  late DAUComp selectedComp;
  late Team homeTeam;
  late Team awayTeam;
  late Tipper selectedTipper;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    dauCompsViewModel = MockDAUCompsViewModel();
    gamesViewModel = MockGamesViewModel();
    statsViewModel = MockStatsViewModel();
    teamsViewModel = MockTeamsViewModel();
    tippersViewModel = MockTippersViewModel();

    selectedComp = DAUComp(
      dbkey: 'comp-2026',
      name: 'Test Competition 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: <DAURound>[],
    );
    homeTeam = Team(dbkey: 'nrl-home', name: 'Home Team', league: League.nrl);
    awayTeam = Team(dbkey: 'nrl-away', name: 'Away Team', league: League.nrl);
    selectedTipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: <DAUComp>[],
      authuid: 'auth-1',
      email: 'tipper@example.com',
      name: 'Test Tipper',
      tipperRole: TipperRole.tipper,
    );

    when(() => dauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => dauCompsViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(selectedComp);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);
    when(() => dauCompsViewModel.gamesViewModel).thenReturn(null);

    when(() => statsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => statsViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => statsViewModel.compLeaderboard).thenReturn(<LeaderboardEntry>[]);
    when(() => statsViewModel.getRoundLeaderBoard(any())).thenReturn({});
    when(() => statsViewModel.roundWinners).thenReturn({});
    when(() => statsViewModel.getTipperRoundPointsForComp(selectedTipper))
        .thenReturn([]);
    when(() => statsViewModel.hasLiveScoresInUse).thenReturn(false);
    when(() => statsViewModel.sortRoundWinnersByRoundNumber(any()))
        .thenAnswer((_) {});

    when(() => tippersViewModel.selectedTipper).thenReturn(selectedTipper);

    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
    di.registerSingleton<StatsViewModel>(statsViewModel);
    di.registerSingleton<TippersViewModel>(tippersViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  Map<Tipper, RoundStats> populateRound() {
    final data = <Tipper, RoundStats>{};
    for (var i = 0; i < 24; i++) {
      final tipper = i == 0
          ? selectedTipper
          : Tipper(
              dbkey: 'member-$i',
              compsPaidFor: <DAUComp>[],
              authuid: 'auth-member-$i',
              email: 'member-$i@example.com',
              name: i == 1 ? 'Alexandra Long Tipper Name' : 'Member $i',
              tipperRole: TipperRole.tipper,
            );
      data[tipper] = RoundStats.fromJson({
        'aS': 24 - i,
        'nS': 30 - i,
        'aMt': i % 4,
        'nMt': i % 3,
        'aMu': i % 2,
        'nMu': i % 3,
      })..rank = i + 1;
    }
    when(() => statsViewModel.getRoundLeaderBoard(any()))
        .thenAnswer((_) => data);
    return data;
  }

  Future<void> pumpRound(
    WidgetTester tester, {
    double width = 360,
    double scale = 1,
    int round = 1,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const Key('round-page'),
          child: StatRoundLeaderboard(round),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('round leaderboard golden $width/$scale', (tester) async {
        populateRound();
        await pumpRound(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const Key('round-page')),
          matchesGoldenFile(
            'goldens/round-leaderboard-${width.toInt()}-$scale.png',
          ),
        );
      });
    }
  }

  testWidgets(
    'round rows survive resize and unchanged ticks, refresh changed values',
    (tester) async {
      final data = populateRound();
      await pumpRound(tester);
      AppTable table() => tester.widget<AppTable>(find.byType(AppTable));
      final original = table().rows;
      final listeners = verify(() => statsViewModel.addListener(captureAny()))
          .captured
          .cast<VoidCallback>();
      void notify() {
        for (final listener in listeners) {
          listener();
        }
      }

      notify();
      await tester.pump();
      expect(identical(table().rows, original), isTrue);
      await pumpRound(tester, width: 1280);
      expect(identical(table().rows, original), isTrue);
      data[selectedTipper]!.nrlPoints = 99;
      notify();
      await tester.pump();
      expect(identical(table().rows, original), isFalse);
      expect(table().rows.first.cells[3].text, '99');
      expect(
        table().rows.first.colour,
        Theme.of(tester.element(find.byType(AppTable))).highlightColor,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'round sorting preserves rank and league rules after notifications',
    (tester) async {
      populateRound();
      await pumpRound(tester, width: 768);
      AppTable table() => tester.widget<AppTable>(find.byType(AppTable));
      expect(table().rows.first.cells.first.text, 'Test Tipper');
      await tester.tap(find.text('Rank'));
      await tester.pump();
      expect(table().rows.first.cells[1].text, '24');
      await tester.tap(find.text('NRL'));
      await tester.pump();
      expect(table().rows.first.cells[3].text, '7');
      final listeners = verify(() => statsViewModel.addListener(captureAny()))
          .captured;
      for (final listener in listeners.cast<VoidCallback>()) {
        listener();
      }
      await tester.pump();
      expect(table().rows.first.cells[3].text, '7');
      await tester.tap(find.text('Total'));
      await tester.pump();
      expect(table().rows.first.cells[1].text, '1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('whole round row opens the correct tipper and round', (
    tester,
  ) async {
    populateRound();
    await pumpRound(tester, width: 768, round: 25);
    // Tap the numeric total, not the name; the entire row is interactive.
    await tester.tap(find.text('54'));
    await tester.pumpAndSettle();
    final destination = tester.widget<StatRoundGameScoresForTipper>(
      find.byType(StatRoundGameScoresForTipper),
    );
    expect(destination.statsTipper, selectedTipper);
    expect(destination.roundNumberToDisplay, 25);
    expect(tester.takeException(), isNull);
  });

  testWidgets('round change refreshes the retained page state', (tester) async {
    populateRound();
    await pumpRound(tester);
    await pumpRound(tester, round: 2);
    verify(() => statsViewModel.getRoundLeaderBoard(2)).called(1);
    expect(find.text('Round 2 Leaderboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow round page keeps names frozen and headings pinned', (
    tester,
  ) async {
    populateRound();
    await pumpRound(tester, scale: 1.5);
    final nameX = tester.getTopLeft(find.text('Name')).dx;
    final nameY = tester.getTopLeft(find.text('Name')).dy;
    final totalX = tester.getTopLeft(find.text('Total')).dx;
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    expect(horizontal.position.maxScrollExtent, greaterThan(0));
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Name')).dx, nameX);
    expect(tester.getTopLeft(find.text('Total')).dx, lessThan(totalX));
    expect(tester.getRect(find.text('UPS')).right, lessThan(346));
    final vertical = tester.widget<ListView>(find.byType(ListView)).controller!;
    vertical.jumpTo(300);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Name')).dy, nameY);
    expect(tester.takeException(), isNull);
  });

  testWidgets('competition leaderboard renders its DataTable2', (tester) async {
    await _expectPageRendersTable(tester, const StatCompLeaderboard());
  });

  testWidgets('round leaderboard renders its AppTable', (tester) async {
    await _expectPageRendersTable(tester, const StatRoundLeaderboard(1));
  });

  testWidgets('round winners renders its DataTable2', (tester) async {
    await _expectPageRendersTable(tester, const StatRoundWinners());
  });

  testWidgets('missing tips renders its DataTable2', (tester) async {
    await _expectPageRendersTable(tester, const RoundMissingTipsStats(1));
  });

  testWidgets('tipper round points renders its DataTable2', (tester) async {
    await _expectPageRendersTable(
      tester,
      StatRoundPointsForTipper(selectedTipper),
    );
  });

  testWidgets('tipper round games renders its DataTable2', (tester) async {
    // A null competition deliberately avoids constructing a Firebase-backed
    // TipsViewModel; this smoke case only guards the table's Material ancestry.
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(null);

    await _expectPageRendersTable(
      tester,
      StatRoundGameScoresForTipper(selectedTipper, 1),
    );
  });

  testWidgets('historical matchups renders its DataTable2', (tester) async {
    final game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      location: 'Test Ground',
      startTimeUTC: DateTime.utc(2025, 5, 1),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10),
    );

    when(() => dauCompsViewModel.gamesViewModel).thenReturn(gamesViewModel);
    when(() => gamesViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => gamesViewModel.teamsViewModel).thenReturn(teamsViewModel);
    when(() => teamsViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => teamsViewModel.findTeam(homeTeam.dbkey)).thenReturn(homeTeam);
    when(() => teamsViewModel.findTeam(awayTeam.dbkey)).thenReturn(awayTeam);
    when(
      () => gamesViewModel.getCompleteMatchupHistory(
        homeTeam,
        awayTeam,
        League.nrl,
      ),
    ).thenAnswer((_) async => <Game>[game]);

    await _expectPageRendersTable(
      tester,
      LeagueLadderHistoricalMatchups(
        league: League.nrl,
        teamDbKeys: <String>[homeTeam.dbkey, awayTeam.dbkey],
      ),
      pumpAsyncState: true,
    );
  });

  testWidgets('team game history renders its DataTable2', (tester) async {
    final historyItem = TeamGameHistoryItem(
      opponentName: awayTeam.name,
      teamScore: 20,
      opponentScore: 10,
      result: 'Won',
      ladderPoints: 2,
      gameDate: DateTime.utc(2025, 5, 1),
      roundNumber: 1,
      isHomeGame: true,
    );

    when(() => dauCompsViewModel.gamesViewModel).thenReturn(gamesViewModel);
    when(() => gamesViewModel.getCompleteTeamGameHistory(homeTeam, League.nrl))
        .thenAnswer((_) async => <TeamGameHistoryItem>[historyItem]);

    await _expectPageRendersTable(
      tester,
      TeamGamesHistoryPage(team: homeTeam, league: League.nrl),
      pumpAsyncState: true,
    );
  });

  testWidgets('DataTable2 text uses the app theme, not a light fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlexThemeData.dark(scheme: FlexScheme.green),
        home: Scaffold(
          body: DataTable2(
            columns: const <DataColumn>[DataColumn(label: Text('Tipper'))],
            rows: const <DataRow>[
              DataRow(cells: <DataCell>[DataCell(Text('Rich'))]),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final BuildContext cellTextContext = tester.element(find.text('Rich'));
    expect(
      DefaultTextStyle.of(cellTextContext).style.color,
      Theme.of(cellTextContext).textTheme.bodyMedium?.color,
    );
  });
  Future<void> pumpStatsTab(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: ChangeNotifierProvider<DAUCompsViewModel>.value(
          value: dauCompsViewModel,
          child: const Scaffold(body: StatsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('stats menu scrolls on a short viewport instead of overflowing', (
    tester,
  ) async {
    await pumpStatsTab(tester, const Size(900, 420));
    expect(tester.takeException(), isNull);
    final last = find.text('AFL Ladder\nTeam rankings');
    await tester.scrollUntilVisible(
      last,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stats menu stays bottom aligned when the viewport is tall', (
    tester,
  ) async {
    await pumpStatsTab(tester, const Size(900, 1400));
    expect(tester.takeException(), isNull);
    // Bottom-focused layout: the final row sits near the bottom edge rather
    // than floating to the top of a tall pane.
    expect(
      tester.getRect(find.text('AFL Ladder\nTeam rankings')).bottom,
      greaterThan(1400 - 200),
    );
  });
}

Future<void> _expectPageRendersTable(
  WidgetTester tester,
  Widget page, {
  bool pumpAsyncState = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
  if (pumpAsyncState) {
    await tester.pump();
    await tester.pump();
  }

  expect(tester.takeException(), isNull);
  expect(
    find.byType(page is StatRoundLeaderboard ? AppTable : DataTable2),
    findsOneWidget,
  );
}
