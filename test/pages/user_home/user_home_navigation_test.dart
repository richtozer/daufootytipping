import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class _MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  late _MockDAUCompsViewModel dauCompsViewModel;
  late _MockTippersViewModel tippersViewModel;

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
    final now = DateTime.now().toUtc();
    final round = DAURound(
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
      ];
    final comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: [round],
    );
    final tipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: [comp],
      authuid: 'auth-1',
      email: 'tipper@example.com',
      name: 'Tipper',
      tipperRole: TipperRole.tipper,
    );

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

  testWidgets('reselecting Tips restores its default scroll position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();

    final tipsState = tester.state<TipsTabState>(find.byType(TipsTab));
    final defaultOffset = tipsState.scrollController.offset;

    tipsState.scrollController.jumpTo(defaultOffset + 400);
    expect(tipsState.scrollController.offset, greaterThan(defaultOffset));

    await tester.tap(find.text('TIPS'));
    await tester.pump();

    expect(tipsState.scrollController.offset, closeTo(defaultOffset, 0.1));
  });
}
