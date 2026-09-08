import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_historical.dart';
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
import 'package:watch_it/watch_it.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockStatsViewModel extends Mock implements StatsViewModel {}

class MockTeamsViewModel extends Mock implements TeamsViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
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

  testWidgets('competition leaderboard renders its DataTable2', (tester) async {
    await _expectPageRendersTable(tester, const StatCompLeaderboard());
  });

  testWidgets('round leaderboard renders its DataTable2', (tester) async {
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
  expect(find.byType(DataTable2), findsOneWidget);
}
