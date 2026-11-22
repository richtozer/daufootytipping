import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_round_leagueheader_listtile.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_percent_tipped.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../mocks/mock_daucomps_viewmodel.dart';
import '../../support/app_controls_test_app.dart';
import '../../support/load_tips_fonts.dart';

class _MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  setUpAll(loadTipsFonts);
  late MockDAUCompsViewModel dauCompsViewModel;

  setUp(() async {
    await di.reset();
    registerAppControlsViewModel();
    dauCompsViewModel = MockDAUCompsViewModel();
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(null);
    when(() => dauCompsViewModel.activeDAUComp).thenReturn(null);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('points tippers to the support site when no comp is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatPercentTipped())),
    );

    expect(
      find.text('Nothing to see here.\nContact support: ${p.supportUrl}.'),
      findsOneWidget,
    );
  });

  testWidgets('before any game has a final score the page says the breakdown '
      'is coming instead of showing nothing', (tester) async {
    final comp = DAUComp(
      dbkey: 'comp-2027',
      name: 'DAU 2027',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: [],
    );
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);
    when(() => dauCompsViewModel.statsViewModel).thenReturn(null);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);
    when(() => dauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => dauCompsViewModel.removeListener(any())).thenAnswer((_) {});
    // A phone held upright, where the page shows its title.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatPercentTipped())),
    );
    await tester.pump();

    expect(find.text('Tipping breakdown coming soon'), findsOneWidget);
    expect(find.text('Percentage Tipped'), findsOneWidget);
  });

  /// Opens the page on a comp of [roundCount] rounds, the first
  /// [completedRounds] of them over and scored, and checks round
  /// [expectedRound]'s NRL header is in view.
  Future<void> expectOpensOnRound(
    WidgetTester tester, {
    required int roundCount,
    required int completedRounds,
    required int expectedRound,
  }) async {
    final teams = {
      for (final league in League.values)
        league: (
          Team(dbkey: '${league.name}-h', name: 'Home', league: league),
          Team(dbkey: '${league.name}-a', name: 'Away', league: league),
        ),
    };
    final now = DateTime.now().toUtc();
    // Completed rounds ended weeks ago; the rest are still to come.
    DateTime roundStart(int roundNumber) =>
        now.add(Duration(days: 7 * (roundNumber - completedRounds - 1)));
    final rounds = [
      for (var roundNumber = 1; roundNumber <= roundCount; roundNumber++)
        DAURound(
            dAUroundNumber: roundNumber,
            firstGameKickOffUTC: roundStart(roundNumber),
            lastGameKickOffUTC: roundStart(roundNumber)
                .add(const Duration(days: 1)),
          )
          ..roundState = roundNumber <= completedRounds
              ? RoundState.allGamesEnded
              : RoundState.notStarted
          ..games = [
            for (final league in const [League.nrl, League.afl])
              for (var match = 1; match <= 8; match++)
                Game(
                  dbkey: '${league.name}-$roundNumber-$match',
                  league: league,
                  homeTeam: teams[league]!.$1,
                  awayTeam: teams[league]!.$2,
                  location: 'Ground',
                  startTimeUTC: roundStart(roundNumber),
                  fixtureRoundNumber: roundNumber,
                  fixtureMatchNumber: match,
                  scoring: roundNumber <= completedRounds
                      ? Scoring(homeTeamScore: 10, awayTeamScore: 8)
                      : null,
                ),
          ],
    ];
    final comp = DAUComp(
      dbkey: 'comp-2026',
      name: 'DAU 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: rounds,
    );
    final tipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: [comp],
      authuid: 'auth-1',
      email: 'tipper@example.com',
      name: 'Tipper',
      tipperRole: TipperRole.tipper,
    );
    final tippersViewModel = _MockTippersViewModel();
    when(() => tippersViewModel.selectedTipper).thenReturn(tipper);
    di.registerSingleton<TippersViewModel>(tippersViewModel);
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);
    when(() => dauCompsViewModel.statsViewModel).thenReturn(null);
    when(() => dauCompsViewModel.gamesViewModel).thenReturn(null);
    when(() => dauCompsViewModel.isLinkingGames).thenReturn(false);
    when(() => dauCompsViewModel.selectedTipperTipsViewModel).thenReturn(null);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(false);
    when(() => dauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => dauCompsViewModel.removeListener(any())).thenAnswer((_) {});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatPercentTipped())),
    );
    await tester.pump();

    final roundHeader = find.byWidgetPredicate(
      (widget) =>
          widget is RoundLeagueHeaderListTile &&
          widget.dauRound.dAUroundNumber == expectedRound &&
          widget.league == League.nrl,
    );
    expect(roundHeader, findsOneWidget);
    final list = tester.getRect(find.byType(CustomScrollView));
    final header = tester.getRect(roundHeader);
    expect(header.top, greaterThanOrEqualTo(list.top));
    expect(header.bottom, lessThanOrEqualTo(list.bottom));
  }

  // The page once opened on round 16 of a finished 20-round comp: it guessed
  // the list's height from fixed card heights, and its cards are taller.
  testWidgets('a finished comp opens on its last round', (tester) async {
    await expectOpensOnRound(
      tester,
      roundCount: 20,
      completedRounds: 20,
      expectedRound: 20,
    );
  });

  testWidgets('mid-season it opens on the latest completed round', (
    tester,
  ) async {
    await expectOpensOnRound(
      tester,
      roundCount: 27,
      completedRounds: 15,
      expectedRound: 15,
    );
  });
}
