import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_submit.dart';
import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGameTipViewModel extends Mock implements GameTipViewModel {}

class MockTipsViewModel extends Mock implements TipsViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

class FakeTip extends Fake implements Tip {}

void main() {
  late MockGameTipViewModel gameTipViewModel;

  setUpAll(() {
    registerFallbackValue(FakeTip());
  });

  setUp(() {
    final Tipper tipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: const [],
      authuid: 'auth-1',
      email: 'tipper@example.com',
      name: 'Tipper',
      tipperRole: TipperRole.tipper,
    );
    final Game game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
      location: 'Stadium',
      startTimeUTC: DateTime.now().toUtc().add(const Duration(hours: 4)),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(),
    );
    final MockTippersViewModel tippersViewModel = MockTippersViewModel();
    when(() => tippersViewModel.inGodMode).thenReturn(false);
    final MockTipsViewModel tipsViewModel = MockTipsViewModel();
    when(() => tipsViewModel.tipperViewModel).thenReturn(tippersViewModel);

    gameTipViewModel = MockGameTipViewModel();
    when(() => gameTipViewModel.currentTipper).thenReturn(tipper);
    when(() => gameTipViewModel.game).thenReturn(game);
    when(() => gameTipViewModel.allTipsViewModel).thenReturn(tipsViewModel);
    when(() => gameTipViewModel.tip).thenReturn(null);
  });

  Future<void> submit(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () =>
                  submitTip(context, gameTipViewModel, GameResult.b),
              child: const Text('tip'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tip'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a tip the server has not confirmed says it is queued, not that it failed',
    (tester) async {
      when(
        () => gameTipViewModel.addTip(any()),
      ).thenAnswer((_) async => throw const WriteNotConfirmedException('tip'));

      await submit(tester);

      expect(find.textContaining('not been confirmed yet'), findsOneWidget);
      expect(find.textContaining('Error submitting tip'), findsNothing);
    },
  );

  testWidgets('a tip the server rejects is reported as an error', (
    tester,
  ) async {
    when(() => gameTipViewModel.addTip(any()))
        .thenAnswer((_) async => throw Exception('permission denied'));

    await submit(tester);

    expect(find.textContaining('Error submitting tip'), findsOneWidget);
    expect(find.textContaining('not been confirmed yet'), findsNothing);
  });
}
