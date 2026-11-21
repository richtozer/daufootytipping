import 'dart:async';
import 'dart:convert';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_round_leagueheader_listtile.dart';
import 'package:daufootytipping/services/unconfirmed_tips_service.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_host.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_observer.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_pill.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/load_tips_fonts.dart';

import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class _MockTippersViewModel extends Mock implements TippersViewModel {}

class _MockTipsViewModel extends Mock implements TipsViewModel {}

class _MockStatsViewModel extends Mock implements StatsViewModel {}

class _FakeTip extends Fake implements Tip {
  _FakeTip(this.tip, this.submittedTimeUTC);

  @override
  final GameResult tip;

  @override
  final DateTime submittedTimeUTC;
}

void main() {
  setUpAll(loadTipsFonts);
  late _MockDAUCompsViewModel dauCompsViewModel;
  late _MockTippersViewModel tippersViewModel;
  late AppControlsViewModel appControlsViewModel;
  late DAURound round;
  late Tipper tipper;

  /// Tips loaded, with the first untipped game at [nrl] in the NRL games and
  /// [afl] in the AFL ones (-1 for none).
  void tipsWithFirstUntipped({required int nrl, required int afl}) {
    final tipsViewModel = _MockTipsViewModel();
    when(() => tipsViewModel.isInitialLoadComplete).thenReturn(true);
    when(() => tipsViewModel.firstUntippedGameIndex(any(), any()))
        .thenAnswer((invocation) {
          final games = invocation.positionalArguments.first as List<Game>;
          if (games.isEmpty) return -1;
          return games.first.league == League.nrl ? nrl : afl;
        });
    when(
      () =>
          tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
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
    when(() => dauCompsViewModel.selectedTipperTipsViewModel)
        .thenReturn(tipsViewModel);
  }

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
    round =
        DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: now.add(const Duration(days: 1)),
            lastGameKickOffUTC: now.add(const Duration(days: 2)),
          )
          ..games = [
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
    when(() => dauCompsViewModel.gamesLinked).thenReturn(true);
    // Loaded, with nothing tipped.
    tipsWithFirstUntipped(nrl: 0, afl: 0);
    when(() => dauCompsViewModel.statsViewModel).thenReturn(null);
    when(() => dauCompsViewModel.currentRoundOutstandingTipsCount())
        .thenReturn(0);
    when(() => dauCompsViewModel.appBadgeOutstandingTipsCount()).thenReturn(0);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);
    when(() => tippersViewModel.selectedTipper).thenReturn(tipper);
    when(() => tippersViewModel.inGodMode).thenReturn(false);

    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
    di.registerSingleton<TippersViewModel>(tippersViewModel);
    appControlsViewModel = AppControlsViewModel();
    di.registerSingleton<AppControlsViewModel>(appControlsViewModel);
  });

  tearDown(() async {
    await di.reset();
    appControlsViewModel.dispose();
  });

  /// The app as main.dart builds it: the floating controls above the
  /// Navigator, which is where the tab pill is drawn.
  Widget appHosting({EdgeInsets padding = EdgeInsets.zero}) {
    final observer = AppControlsObserver(appControlsViewModel);
    return MaterialApp(
      navigatorObservers: [observer],
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: padding),
        child: AppControlsHost(
          viewModel: appControlsViewModel,
          observer: observer,
          child: navigator!,
        ),
      ),
      home: const HomePage(),
    );
  }

  Future<TipsTabState> pumpHome(
    WidgetTester tester, {
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(appHosting(padding: padding));
    // The pill grows in once the tabs are offered; let it finish so it can be
    // tapped.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return tester.state<TipsTabState>(find.byType(TipsTab));
  }

  /// Where a game card sits on screen. The tests build no cards (there is no
  /// games view model), so a section's body is a spinner in the league's
  /// colour, one card extent per game. A body just off screen is in the
  /// viewport's cache, which finders skip by default; its position still holds.
  double gameTop(WidgetTester tester, League league, int index) {
    final spinner = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CircularProgressIndicator &&
            widget.color == league.colour,
        skipOffstage: false,
      ),
      skipOffstage: false,
    );
    final body = find
        .ancestor(of: spinner, matching: find.byType(SizedBox))
        .first;
    final tipsState = tester.state<TipsTabState>(find.byType(TipsTab));
    return tester.getRect(body).top + index * tipsState.cardExtent;
  }

  /// Collects the comps view model's listeners, so a test can notify them.
  List<VoidCallback> captureListeners() {
    final listeners = <VoidCallback>[];
    registerFallbackValue(() {});
    when(() => dauCompsViewModel.addListener(any())).thenAnswer(
      (invocation) =>
          listeners.add(invocation.positionalArguments.first as VoidCallback),
    );
    return listeners;
  }

  void notifyAll(List<VoidCallback> listeners) {
    for (final listener in List.of(listeners)) {
      listener();
    }
  }

  /// The header pinned at the top of the list: its tile sits inside 4 of
  /// padding at the list's top. Null while the welcome header is there.
  Element? pinnedHeader(WidgetTester tester) {
    final listTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    for (final element in find.byType(RoundLeagueHeaderListTile).evaluate()) {
      final top = (element.renderObject! as RenderBox).localToGlobal(
        Offset.zero,
      );
      if ((top.dy - listTop - 4).abs() < 0.5) return element;
    }
    return null;
  }

  /// The bottom of the pinned header, below which a game is in view.
  double stickyBottom(WidgetTester tester) {
    final header = pinnedHeader(tester)!.renderObject! as RenderBox;
    return header.localToGlobal(Offset(0, header.size.height)).dy + 4;
  }

  League? stickyLeague(WidgetTester tester) =>
      (pinnedHeader(tester)?.widget as RoundLeagueHeaderListTile?)?.league;

  /// The league's first game just below the pinned header, which shows it.
  void expectLeagueAtTop(WidgetTester tester, League league) {
    expect(stickyLeague(tester), league);
    expect(gameTop(tester, league, 0), closeTo(stickyBottom(tester), 1));
  }

  Future<void> tapTips(WidgetTester tester) async {
    await tester.tap(find.text('TIPS'));
    await tester.pump();
  }

  testWidgets('cycles the welcome header, NRL and AFL for a new comp', (
    tester,
  ) async {
    final tipsState = await pumpHome(tester);
    // Round 1, nothing tipped: the list opens on the welcome header.
    expect(tipsState.scrollController!.offset, 0);

    await tapTips(tester);
    expectLeagueAtTop(tester, League.nrl);

    await tapTips(tester);
    expectLeagueAtTop(tester, League.afl);

    await tapTips(tester);
    expect(tipsState.scrollController!.offset, 0);

    // Off the cycle, a tap rejoins it at its first stop.
    tipsState.scrollController!.jumpTo(400);
    await tapTips(tester);
    expect(tipsState.scrollController!.offset, 0);
  });

  testWidgets('cycles dynamic position, NRL, AFL, then repeats', (
    tester,
  ) async {
    final tipsViewModel = _MockTipsViewModel();
    when(() => tipsViewModel.isInitialLoadComplete).thenReturn(true);
    when(() => tipsViewModel.firstUntippedGameIndex(any(), any()))
        .thenReturn(1);
    when(
      () =>
          tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
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
    when(() => dauCompsViewModel.selectedTipperTipsViewModel)
        .thenReturn(tipsViewModel);

    final tipsState = await pumpHome(tester);
    double offset() => tipsState.scrollController!.offset;

    // Asserts the cycle, not the arithmetic between its stops: deriving the
    // stops from the card extent assumed a spacing that any change to the
    // card's height quietly breaks, and says nothing about cycling.
    await tapTips(tester);
    final first = offset();
    await tapTips(tester);
    final second = offset();
    await tapTips(tester);
    final third = offset();
    expect({first, second, third}.length, 3, reason: 'three distinct stops');
    // The third stop is where startup put the list: the second NRL game, the
    // first untipped, just below the sticky header.
    expect(stickyLeague(tester), League.nrl);
    expect(gameTop(tester, League.nrl, 1), closeTo(stickyBottom(tester), 1));

    await tapTips(tester);
    expect(offset(), closeTo(first, 0.1), reason: 'and then it repeats');

    // Somewhere off the cycle altogether rejoins it. Which stop depends on
    // where startup left the list, so the test does not name one.
    tipsState.scrollController!.jumpTo(first + 400);
    await tapTips(tester);
    expect(
      [first, second, third].any((stop) => (stop - offset()).abs() < 0.1),
      isTrue,
      reason: 'rejoins the cycle from off it',
    );
  });

  testWidgets('updates AFL sticky header to NRL on the next tap', (
    tester,
  ) async {
    final tipsViewModel = _MockTipsViewModel();
    when(() => tipsViewModel.isInitialLoadComplete).thenReturn(true);
    when(() => tipsViewModel.firstUntippedGameIndex(any(), any()))
        .thenAnswer((invocation) {
          final games = invocation.positionalArguments.first as List<Game>;
          return games.first.league == League.afl ? 1 : -1;
        });
    when(
      () =>
          tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
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
    when(() => dauCompsViewModel.selectedTipperTipsViewModel)
        .thenReturn(tipsViewModel);

    await pumpHome(tester);

    expect(stickyLeague(tester), League.afl);

    await tapTips(tester);
    expectLeagueAtTop(tester, League.nrl);
  });

  testWidgets('includes a league section when that league has no games', (
    tester,
  ) async {
    round.games.removeWhere((game) => game.league == League.nrl);
    // Nothing to tip, so startup has no game to go to.
    tipsWithFirstUntipped(nrl: -1, afl: -1);

    final tipsState = await pumpHome(tester);
    expect(tipsState.scrollController!.offset, 0);

    // The empty NRL section is a stop of its own, its no-games card in view.
    await tapTips(tester);
    expectLeagueAtTop(tester, League.nrl);

    await tapTips(tester);
    expectLeagueAtTop(tester, League.afl);

    await tapTips(tester);
    expect(tipsState.scrollController!.offset, 0);

    tipsState.scrollController!.jumpTo(400);
    await tapTips(tester);
    expect(tipsState.scrollController!.offset, 0);
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
    final endOfCompetitionOffset = tipsState.scrollController!.offset;

    await tapTips(tester);
    expectLeagueAtTop(tester, League.nrl);

    await tapTips(tester);
    expectLeagueAtTop(tester, League.afl);

    await tapTips(tester);
    expect(
      tipsState.scrollController!.offset,
      closeTo(endOfCompetitionOffset, 0.1),
    );

    tipsState.scrollController!.jumpTo(400);

    await tapTips(tester);
    expect(
      tipsState.scrollController!.offset,
      closeTo(endOfCompetitionOffset, 0.1),
    );
  });

  testWidgets('offers its tabs in the floating pill and follows a tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(appHosting());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppGlassPill), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(appControlsViewModel.tabs!.selectedIndex, 0);

    await tester.tap(find.text('STATS'));
    await tester.pump();
    expect(appControlsViewModel.tabs!.selectedIndex, 1);
  });

  testWidgets('moves the pill into a wide right display inset', (tester) async {
    tester.view.physicalSize = const Size(420, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      appHosting(padding: const EdgeInsets.only(right: 80)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final pill = tester.getRect(find.byType(AppGlassPill));
    expect(pill.width, lessThan(pill.height), reason: 'runs down the side');
    expect(pill.center.dx, 420 - 40, reason: 'inside the 80pt strip');
  });

  testWidgets('keeps the reader on their game when the cards are remeasured', (
    tester,
  ) async {
    final listeners = <VoidCallback>[];
    registerFallbackValue(() {});
    when(() => dauCompsViewModel.addListener(any())).thenAnswer(
      (invocation) =>
          listeners.add(invocation.positionalArguments.first as VoidCallback),
    );
    final tipsState = await pumpHome(tester);
    // From the NRL games' start, the reader has scrolled half way through the
    // fifth: half of it is under the sticky header.
    await tapTips(tester);
    final beforeExtent = tipsState.cardExtent;
    tipsState.scrollController!.jumpTo(
      tipsState.scrollController!.offset + 4.5 * beforeExtent,
    );
    await tester.pump();
    double fifthGameUnderSticky() =>
        stickyBottom(tester) - gameTop(tester, League.nrl, 4);
    expect(fifthGameUnderSticky(), closeTo(0.5 * beforeExtent, 1));

    // Rotating or folding narrows the pane, which remeasures the cards. The
    // device also resumes, and the view model notifies while the list is
    // still being re-placed. Nothing it carries has changed, so it must not
    // send the list back to the current round.
    tester.view.physicalSize = const Size(320, 844);
    await tester.pump();
    for (final listener in List.of(listeners)) {
      listener();
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(
      tipsState.cardExtent,
      isNot(beforeExtent),
      reason: 'the narrower pane must actually change the layout',
    );
    expect(
      fifthGameUnderSticky(),
      closeTo(0.5 * tipsState.cardExtent, 1),
      reason: 'the same game, the same way through it, not the current round',
    );

    // And again once it has settled.
    for (final listener in List.of(listeners)) {
      listener();
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(
      fifthGameUnderSticky(),
      closeTo(0.5 * tipsState.cardExtent, 1),
      reason: 'a notification after the remeasure must not undo it',
    );
  });

  testWidgets('keeps a league at the top under a notch when remeasured', (
    tester,
  ) async {
    // Below a notch the sticky header is pinned under the inset, and a league
    // placed at the top has its first game just below it.
    final tipsState = await pumpHome(
      tester,
      padding: const EdgeInsets.only(top: 50),
    );
    expect(tipsState.scrollController!.offset, 0);
    await tapTips(tester);
    await tapTips(tester);
    expectLeagueAtTop(tester, League.afl);

    final beforeExtent = tipsState.cardExtent;
    tester.view.physicalSize = const Size(320, 844);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(
      tipsState.cardExtent,
      isNot(beforeExtent),
      reason: 'the narrower pane must actually change the layout',
    );
    // Still AFL's first game, not scaled with the NRL games above it.
    expectLeagueAtTop(tester, League.afl);
  });

  testWidgets(
    'does not send a reader to the end when the list could not scroll',
    (tester) async {
      // One game in each league fits on a tall screen without scrolling.
      round.games = [round.games.first, round.games.last];
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(appHosting());
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      final tipsState = tester.state<TipsTabState>(find.byType(TipsTab));
      expect(tipsState.scrollController!.position.maxScrollExtent, 0);

      // A short, narrow pane makes the list scroll, with the reader still at
      // the top of it.
      tester.view.physicalSize = const Size(320, 400);
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      expect(
        tipsState.scrollController!.position.maxScrollExtent,
        greaterThan(0),
        reason: 'the smaller pane must actually make the list scroll',
      );
      expect(
        tipsState.scrollController!.offset,
        lessThan(tipsState.scrollController!.position.maxScrollExtent),
        reason: 'a reader who was not at an end of anything stays off the end',
      );
    },
  );

  testWidgets('draws no list until the games are in their rounds', (
    tester,
  ) async {
    final listeners = captureListeners();
    when(() => dauCompsViewModel.gamesLinked).thenReturn(false);
    tipsWithFirstUntipped(nrl: -1, afl: 2);
    final tipsState = await pumpHome(tester);
    // Every round reads as empty until then, so a list drawn now would be
    // placed against games it does not have.
    expect(find.byType(CustomScrollView), findsNothing);

    when(() => dauCompsViewModel.gamesLinked).thenReturn(true);
    notifyAll(listeners);
    await tester.pump();
    // The first frame that draws the list draws it in place.
    final first = tipsState.scrollController!.offset;
    expect(first, greaterThan(0));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(tipsState.scrollController!.offset, first);
  });

  testWidgets('keeps the reader on their game when a game arrives above it', (
    tester,
  ) async {
    final listeners = captureListeners();
    tipsWithFirstUntipped(nrl: -1, afl: 0);
    final tipsState = await pumpHome(tester);
    // The reader scrolls on into the AFL games.
    final controller = tipsState.scrollController!;
    controller.jumpTo(controller.offset + 2.5 * tipsState.cardExtent);
    await tester.pump();
    final before = gameTop(tester, League.afl, 3);

    // A game is added to the NRL above them.
    final nrlGame = round.games.first;
    round.games = [
      Game(
        dbkey: 'nrl-added',
        league: League.nrl,
        homeTeam: nrlGame.homeTeam,
        awayTeam: nrlGame.awayTeam,
        location: nrlGame.location,
        startTimeUTC: nrlGame.startTimeUTC.add(const Duration(hours: 20)),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 11,
      ),
      ...round.games,
    ];
    notifyAll(listeners);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(
      gameTop(tester, League.afl, 3),
      closeTo(before, 1),
      reason: 'the same game where it was, not pushed down or re-placed',
    );
  });

  testWidgets("shows a started round's points from the stats", (tester) async {
    // The round's first NRL game is under way.
    final first = round.games.first;
    round.games[0] = Game(
      dbkey: first.dbkey,
      league: League.nrl,
      homeTeam: first.homeTeam,
      awayTeam: first.awayTeam,
      location: first.location,
      startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
    );
    final statsViewModel = _MockStatsViewModel();
    when(() => statsViewModel.getScoringRoundStats(any(), any())).thenReturn(
      RoundStats(
        roundNumber: 1,
        aflPoints: 0,
        aflMaxPoints: 0,
        aflMarginTips: 0,
        aflMarginUPS: 0,
        nrlPoints: 7,
        nrlMaxPoints: 9,
        nrlMarginTips: 0,
        nrlMarginUPS: 0,
        rank: 3,
        rankChange: 0,
        nrlTipsOutstanding: 0,
        aflTipsOutstanding: 0,
      ),
    );
    when(() => dauCompsViewModel.statsViewModel).thenReturn(statsViewModel);

    await pumpHome(tester);

    expect(find.text('Points: 7 / 9', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
    'a game arriving mid-animation stops it where it put the reader',
    (tester) async {
      final listeners = captureListeners();
      tipsWithFirstUntipped(nrl: -1, afl: 0);
      final tipsState = await pumpHome(tester);
      final controller = tipsState.scrollController!;
      // Page Down, say.
      unawaited(
        controller.animateTo(
          controller.offset + 2 * tipsState.cardExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // A game is added to the NRL above the reader.
      final nrlGame = round.games.first;
      round.games = [
        Game(
          dbkey: 'nrl-added',
          league: League.nrl,
          homeTeam: nrlGame.homeTeam,
          awayTeam: nrlGame.awayTeam,
          location: nrlGame.location,
          startTimeUTC: nrlGame.startTimeUTC.add(const Duration(hours: 20)),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 11,
        ),
        ...round.games,
      ];
      notifyAll(listeners);
      await tester.pump();
      final kept = gameTop(tester, League.afl, 1);

      // The rest of the animation would carry on in the old layout's offsets.
      await tester.pump(const Duration(milliseconds: 400));
      expect(gameTop(tester, League.afl, 1), closeTo(kept, 1));
    },
  );

  testWidgets('measures its cards only once it has a width', (tester) async {
    tipsWithFirstUntipped(nrl: 2, afl: -1);
    final width = ValueNotifier<double>(0);
    addTearDown(width.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (context, value, child) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: value, height: 844, child: child),
          ),
          child: const TipsTab(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // A pane opening from nothing, say.
    width.value = 390;
    await tester.pump();

    expect(stickyLeague(tester), League.nrl);
    expect(gameTop(tester, League.nrl, 2), closeTo(stickyBottom(tester), 1));
  });

  testWidgets('starts a new comp on its welcome header while games arrive', (
    tester,
  ) async {
    final listeners = <VoidCallback>[];
    when(() => dauCompsViewModel.addListener(any())).thenAnswer(
      (invocation) =>
          listeners.add(invocation.positionalArguments.first as VoidCallback),
    );
    // A new comp's fixture streams in: three NRL games are there at first.
    final allGames = round.games;
    round.games = [...allGames.take(3), ...allGames.skip(10)];
    const topInset = 62.0;
    final tipsState = await pumpHome(
      tester,
      padding: const EdgeInsets.only(top: topInset),
    );
    // Round 1 has not started and its first game is the first to tip, so
    // the list opens at the top: the welcome header, then the round's header
    // and its first game, none of them under the inset or the sticky header.
    expect(tipsState.scrollController!.offset, 0);

    // The rest arrive, and the cards they bring are measured afresh. The
    // reader has not moved, so the list starts where a new comp starts.
    round.games = allGames;
    for (final listener in List.of(listeners)) {
      listener();
    }
    tester.view.physicalSize = const Size(320, 844);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(
      tipsState.scrollController!.offset,
      0,
      reason: 'not a fraction of a section that held other games',
    );
  });

  testWidgets('opens on a live first game, not the welcome header', (
    tester,
  ) async {
    // Round 1's first NRL game is under way and everything is tipped.
    final first = round.games.first;
    round.games[0] = Game(
      dbkey: first.dbkey,
      league: League.nrl,
      homeTeam: first.homeTeam,
      awayTeam: first.awayTeam,
      location: first.location,
      startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
    );
    tipsWithFirstUntipped(nrl: -1, afl: -1);
    await pumpHome(tester);

    expectLeagueAtTop(tester, League.nrl);
  });

  group('under a notch, startup puts the first game to tip just below the '
      'sticky header', () {
    const notch = EdgeInsets.only(top: 62);

    testWidgets('a later game in round 1', (tester) async {
      tipsWithFirstUntipped(nrl: 2, afl: -1);
      await pumpHome(tester, padding: notch);

      expect(stickyLeague(tester), League.nrl);
      expect(gameTop(tester, League.nrl, 2), closeTo(stickyBottom(tester), 1));
    });

    testWidgets('the first AFL game in round 1', (tester) async {
      tipsWithFirstUntipped(nrl: -1, afl: 0);
      await pumpHome(tester, padding: notch);

      expect(stickyLeague(tester), League.afl);
      expect(gameTop(tester, League.afl, 0), closeTo(stickyBottom(tester), 1));
    });
  });

  testWidgets('re-places the list when a fold remeasures the cards', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    round
      ..roundState = RoundState.allGamesEnded
      ..firstGameKickOffUTC = now.subtract(const Duration(days: 2))
      ..lastGameKickOffUTC = now.subtract(const Duration(days: 1));

    final tipsState = await pumpHome(tester);
    final beforeExtent = tipsState.cardExtent;
    bool atEndOfCompetition() =>
        tipsState.scrollController!.offset >
        tipsState.scrollController!.position.maxScrollExtent -
            2 * tipsState.cardExtent;
    expect(
      atEndOfCompetition(),
      isTrue,
      reason: 'a completed competition starts at its end',
    );

    // Folding remeasures the cards, so every section moves while the offset
    // stays put in pixels -- which silently leaves a different round on
    // screen. Nothing else corrects it: startup placement runs off a view
    // model notification and a fold is not one.
    tester.view.physicalSize = const Size(320, 844);
    // One frame to remeasure, one for the hold to see a stable height, then
    // the jump and its correction.
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(
      tipsState.cardExtent,
      isNot(beforeExtent),
      reason: 'the narrower pane must actually change the layout',
    );
    expect(
      tipsState.scrollController!.offset,
      closeTo(tipsState.scrollController!.position.maxScrollExtent, 0.5),
      reason: 'still at the very end after the fold, not near it',
    );
  });

  group('a queued tip that did not count', () {
    final int tippedAtUtcSeconds =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 600;

    UnconfirmedTip queuedTip({required int deadlineUtcMs}) => UnconfirmedTip(
      compKey: 'comp-1',
      tipperKey: 'tipper-1',
      gameKey: 'nrl-0',
      choice: 'a',
      submittedUtcSeconds: tippedAtUtcSeconds,
      gameLabel: 'NRL Home v NRL Away',
      deadlineUtcMs: deadlineUtcMs,
      queuedAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );

    testWidgets(
      'is reported when the server refuses it while the app is open',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final service = UnconfirmedTipsService();
        di.registerSingleton<UnconfirmedTipsService>(service);
        await pumpHome(tester);

        final tip = queuedTip(
          deadlineUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        await tester.runAsync(() async {
          await service.queued(tip);
          await service.rejected(tip);
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Tip not counted'), findsOneWidget);
        expect(find.textContaining('NRL Home v NRL Away'), findsOneWidget);

        await tester.tap(find.text('OK'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Tip not counted'), findsNothing);
        expect(service.notices, isEmpty);
      },
    );

    /// A tips view model with the loaded tips the device shows, as the home page
    /// reads them, and a service that waits only briefly before it believes a
    /// tip is missing.
    UnconfirmedTipsService serviceWithTipsShown(
      UnconfirmedTip queued, {
      Tip? shown,
    }) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        UnconfirmedTipsService.storageKey: jsonEncode(<Object?>[
          queued.toJson(),
        ]),
      });
      final service = UnconfirmedTipsService(
        settleFor: const Duration(milliseconds: 20),
      );
      di.registerSingleton<UnconfirmedTipsService>(service);
      final tipsViewModel = _MockTipsViewModel();
      when(() => tipsViewModel.isInitialLoadComplete).thenReturn(true);
      when(() => tipsViewModel.initialLoadCompleted).thenAnswer((_) async {});
      when(() => tipsViewModel.submittedTipForGame(any(), any()))
          .thenReturn(shown);
      when(() => tipsViewModel.firstUntippedGameIndex(any(), any()))
          .thenReturn(1);
      when(
        () => tipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
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
      when(() => dauCompsViewModel.selectedTipperTipsViewModel)
          .thenReturn(tipsViewModel);
      when(() => dauCompsViewModel.gamesViewModel).thenReturn(null);
      return service;
    }

    Future<void> letTheServiceSettle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets(
      'is reported when it is missing from the tips the device shows',
      (tester) async {
        serviceWithTipsShown(
          queuedTip(
            deadlineUtcMs: DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 2))
                .millisecondsSinceEpoch,
          ),
        );

        await pumpHome(tester);
        await letTheServiceSettle(tester);

        expect(find.text('Please check your tips'), findsOneWidget);
        expect(find.text('Tip not counted'), findsNothing);
        expect(find.textContaining('could not confirm'), findsOneWidget);
      },
    );

    testWidgets('before its game starts, asks the user to tip again', (
      tester,
    ) async {
      serviceWithTipsShown(
        queuedTip(
          deadlineUtcMs: DateTime.now()
              .toUtc()
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        ),
      );

      await pumpHome(tester);
      await letTheServiceSettle(tester);

      expect(find.text('Please check your tips'), findsOneWidget);
      expect(find.textContaining('tip again if it is missing'), findsOneWidget);
    });

    testWidgets(
      'is not reported while the tips the device shows still include it',
      (tester) async {
        final queued = queuedTip(
          deadlineUtcMs: DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        );
        final service = serviceWithTipsShown(
          queued,
          shown: _FakeTip(
            GameResult.a,
            DateTime.fromMillisecondsSinceEpoch(
              tippedAtUtcSeconds * 1000,
              isUtc: true,
            ),
          ),
        );

        await pumpHome(tester);
        await letTheServiceSettle(tester);

        expect(find.text('Tip not counted'), findsNothing);
        expect(await tester.runAsync(service.pending), hasLength(1));
      },
    );
  });
}
