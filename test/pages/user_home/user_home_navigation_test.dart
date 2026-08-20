import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class _MockTippersViewModel extends Mock implements TippersViewModel {}

class _MockTipsViewModel extends Mock implements TipsViewModel {}

void main() {
  late _MockDAUCompsViewModel dauCompsViewModel;
  late _MockTippersViewModel tippersViewModel;
  late DAURound round;
  late Tipper tipper;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    dauCompsViewModel = _MockDAUCompsViewModel();
    tippersViewModel = _MockTippersViewModel();

    final nrlHome = Team(
      dbkey: 'nrl-home',
      name: 'NRL Home',
      league: League.nrl,
    );
    final nrlAway = Team(
      dbkey: 'nrl-away',
      name: 'NRL Away',
      league: League.nrl,
    );
    final aflHome = Team(
      dbkey: 'afl-home',
      name: 'AFL Home',
      league: League.afl,
    );
    final aflAway = Team(
      dbkey: 'afl-away',
      name: 'AFL Away',
      league: League.afl,
    );
    final now = DateTime.now().toUtc();
    round = DAURound(
      dAUroundNumber: 1,
      firstGameKickOffUTC: now.add(const Duration(days: 1)),
      lastGameKickOffUTC: now.add(const Duration(days: 2)),
    )..games = [
        for (var index = 0; index < 10; index++)
          Game(
            dbkey: 'nrl-$index',
            league: League.nrl,
            homeTeam: nrlHome,
            awayTeam: nrlAway,
            location: 'Test Ground',
            startTimeUTC: now.add(Duration(days: 1, hours: index)),
            fixtureRoundNumber: 1,
            fixtureMatchNumber: index + 1,
          ),
        for (var index = 0; index < 10; index++)
          Game(
            dbkey: 'afl-$index',
            league: League.afl,
            homeTeam: aflHome,
            awayTeam: aflAway,
            location: 'Test Ground',
            startTimeUTC: now.add(Duration(days: 1, hours: index)),
            fixtureRoundNumber: 1,
            fixtureMatchNumber: index + 1,
          ),
      ];
    final comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: [round],
    );
    tipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: [comp],
      authuid: 'auth-1',
      email: 'tipper@example.com',
      name: 'Tipper',
      tipperRole: TipperRole.tipper,
    );
    registerFallbackValue(<Game>[]);
    registerFallbackValue(tipper);
    registerFallbackValue(round);
    registerFallbackValue(League.nrl);

    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);
    when(() => dauCompsViewModel.gamesViewModel).thenReturn(null);
    when(() => dauCompsViewModel.selectedTipperTipsViewModel).thenReturn(null);
    when(() => dauCompsViewModel.statsViewModel).thenReturn(null);
    when(() => dauCompsViewModel.currentRoundOutstandingTipsCount())
        .thenReturn(0);
    when(() => dauCompsViewModel.appBadgeOutstandingTipsCount()).thenReturn(0);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);
    when(() => tippersViewModel.selectedTipper).thenReturn(tipper);
    when(() => tippersViewModel.inGodMode).thenReturn(false);

    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
    di.registerSingleton<TippersViewModel>(tippersViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  Future<TipsTabState> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    return tester.state<TipsTabState>(find.byType(TipsTab));
  }

  Future<void> tapTips(WidgetTester tester) async {
    await tester.tap(find.text('TIPS'));
    await tester.pump();
  }

  testWidgets('cycles NRL and AFL when default is the first NRL game', (
    tester,
  ) async {
    final tipsState = await pumpHome(tester);
    final nrlOffset = tipsState.scrollController.offset;
    final aflOffset = nrlOffset + 10 * Game.gameCardHeight;

    tipsState.scrollController.jumpTo(nrlOffset + 400);
    expect(tipsState.scrollController.offset, greaterThan(nrlOffset));

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(nrlOffset, 0.1));

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(aflOffset, 0.1));

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(nrlOffset, 0.1));
  });

  testWidgets('cycles dynamic position, NRL, AFL, then repeats', (
    tester,
  ) async {
    final tipsViewModel = _MockTipsViewModel();
    when(() => tipsViewModel.isInitialLoadComplete).thenReturn(true);
    when(
      () => tipsViewModel.firstUntippedGameIndex(any(), any()),
    ).thenReturn(1);
    when(
      () => tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
        any(),
        any(),
      ),
    ).thenReturn(0);
    when(
      () => tipsViewModel.numberOfMarginTipsSubmittedForRoundAndLeague(
        any(),
        any(),
      ),
    ).thenReturn(0);
    when(
      () => dauCompsViewModel.selectedTipperTipsViewModel,
    ).thenReturn(tipsViewModel);

    final tipsState = await pumpHome(tester);
    final dynamicOffset = tipsState.scrollController.offset;
    final nrlOffset = dynamicOffset - Game.gameCardHeight;
    final aflOffset = nrlOffset + 10 * Game.gameCardHeight;

    tipsState.scrollController.jumpTo(dynamicOffset + 400);

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(dynamicOffset, 0.1));

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(nrlOffset, 0.1));

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(aflOffset, 0.1));

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(dynamicOffset, 0.1));
  });

  testWidgets('updates AFL sticky header to NRL on the second tap', (
    tester,
  ) async {
    final tipsViewModel = _MockTipsViewModel();
    when(() => tipsViewModel.isInitialLoadComplete).thenReturn(true);
    when(
      () => tipsViewModel.firstUntippedGameIndex(any(), any()),
    ).thenAnswer((invocation) {
      final games = invocation.positionalArguments.first as List<Game>;
      return games.first.league == League.afl ? 1 : -1;
    });
    when(
      () => tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
        any(),
        any(),
      ),
    ).thenReturn(0);
    when(
      () => tipsViewModel.numberOfMarginTipsSubmittedForRoundAndLeague(
        any(),
        any(),
      ),
    ).thenReturn(0);
    when(
      () => dauCompsViewModel.selectedTipperTipsViewModel,
    ).thenReturn(tipsViewModel);

    await pumpHome(tester);

    TipsStickyHeader stickyHeader() => tester.widget<TipsStickyHeader>(
      find.byType(TipsStickyHeader),
    );

    expect(stickyHeader().section.league, League.afl);

    await tapTips(tester);
    expect(stickyHeader().section.league, League.afl);

    await tapTips(tester);
    expect(stickyHeader().section.league, League.nrl);
  });

  testWidgets('includes a league section when that league has no games', (
    tester,
  ) async {
    round.games.removeWhere((game) => game.league == League.nrl);

    final tipsState = await pumpHome(tester);
    final nrlEmptySectionOffset = tipsState.scrollController.offset;
    final aflOffset =
        nrlEmptySectionOffset + DAURound.noGamesCardHeight;

    tipsState.scrollController.jumpTo(aflOffset + 400);

    await tapTips(tester);
    expect(
      tipsState.scrollController.offset,
      closeTo(nrlEmptySectionOffset, 0.1),
    );

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(aflOffset, 0.1));

    await tapTips(tester);
    expect(
      tipsState.scrollController.offset,
      closeTo(nrlEmptySectionOffset, 0.1),
    );
  });

  testWidgets('cycles end of competition, final NRL, and final AFL', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    round
      ..roundState = RoundState.allGamesEnded
      ..firstGameKickOffUTC = now.subtract(const Duration(days: 2))
      ..lastGameKickOffUTC = now.subtract(const Duration(days: 1));

    final tipsState = await pumpHome(tester);
    final endOfCompetitionOffset = tipsState.scrollController.offset;
    const nrlOffset = 175.0;
    final aflOffset = nrlOffset + 10 * Game.gameCardHeight;

    tipsState.scrollController.jumpTo(0);

    await tapTips(tester);
    expect(
      tipsState.scrollController.offset,
      closeTo(endOfCompetitionOffset, 0.1),
    );

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(nrlOffset, 0.1));

    await tapTips(tester);
    expect(tipsState.scrollController.offset, closeTo(aflOffset, 0.1));

    await tapTips(tester);
    expect(
      tipsState.scrollController.offset,
      closeTo(endOfCompetitionOffset, 0.1),
    );
  });
}
