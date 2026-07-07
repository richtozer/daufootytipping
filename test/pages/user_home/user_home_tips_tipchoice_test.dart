import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:daufootytipping/services/realtime_connection_service.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockGameTipViewModel extends Mock implements GameTipViewModel {}

class MockTipsViewModel extends Mock implements TipsViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

class MockRealtimeConnectionService extends Mock
    implements RealtimeConnectionService {}

class FakeTip extends Fake implements Tip {}

void main() {
  late MockGameTipViewModel gameTipViewModel;
  late MockTipsViewModel tipsViewModel;
  late MockTippersViewModel tippersViewModel;
  late MockRealtimeConnectionService connectionService;
  late Game game;
  late Tipper tipper;

  setUpAll(() {
    registerFallbackValue(FakeTip());
  });

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    gameTipViewModel = MockGameTipViewModel();
    tipsViewModel = MockTipsViewModel();
    tippersViewModel = MockTippersViewModel();
    connectionService = MockRealtimeConnectionService();

    final homeTeam = Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl);
    final awayTeam = Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl);
    game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      location: 'Stadium',
      startTimeUTC: DateTime.now().toUtc().add(const Duration(hours: 4)),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: 0, awayTeamScore: 0),
    );
    tipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: const [],
      authuid: 'auth-1',
      email: 'tipper@example.com',
      name: 'Tipper',
      tipperRole: TipperRole.tipper,
    );

    when(() => gameTipViewModel.savingTip).thenReturn(false);
    when(() => gameTipViewModel.tip).thenReturn(null);
    when(() => gameTipViewModel.game).thenReturn(game);
    when(() => gameTipViewModel.currentTipper).thenReturn(tipper);
    when(() => gameTipViewModel.allTipsViewModel).thenReturn(tipsViewModel);
    when(() => tipsViewModel.tipperViewModel).thenReturn(tippersViewModel);
    when(() => tippersViewModel.inGodMode).thenReturn(false);
    when(() => gameTipViewModel.addTip(any())).thenAnswer((_) async {});

    di.registerSingleton<RealtimeConnectionService>(connectionService);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('shows offline scoring notice after submitting a tip offline', (
    tester,
  ) async {
    when(() => connectionService.consumeOfflineTipNotice()).thenReturn(true);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TipChoice(gameTipViewModel, false))),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, GameResult.b.nrl));
    await tester.pump();

    expect(
      find.text(TipChoice.offlineScoringNoticeMessage),
      findsOneWidget,
    );
    verify(() => gameTipViewModel.addTip(any())).called(1);
  });

  testWidgets('does not show offline scoring notice when connected', (tester) async {
    when(() => connectionService.consumeOfflineTipNotice()).thenReturn(false);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TipChoice(gameTipViewModel, false))),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, GameResult.b.nrl));
    await tester.pump();

    expect(find.text(TipChoice.offlineScoringNoticeMessage), findsNothing);
    verify(() => gameTipViewModel.addTip(any())).called(1);
  });
}
