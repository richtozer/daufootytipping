import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/scoring_update_report.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_buttons.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockStatsViewModel extends Mock implements StatsViewModel {}

void main() {
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockStatsViewModel statsViewModel;
  late DAUComp comp;

  setUp(() {
    dauCompsViewModel = MockDAUCompsViewModel();
    statsViewModel = MockStatsViewModel();

    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );

    when(() => dauCompsViewModel.statsViewModel).thenReturn(statsViewModel);
    when(() => statsViewModel.isUpdateScoringRunning).thenReturn(false);
    when(() => statsViewModel.updateStatsWithReport(comp, null, null)).thenAnswer(
      (_) async => const ScoringUpdateReport(
        resultMessage: 'Completed updates for 2 tippers and 3 rounds.',
        leaderboardChanges: <ScoringLeaderboardChange>[
          ScoringLeaderboardChange(
            tipperDbKey: 'tipper-1',
            tipperName: 'Alice',
            beforeRank: 3,
            afterRank: 1,
            beforeTotal: 18,
            afterTotal: 22,
            beforeNrl: 8,
            afterNrl: 10,
            beforeAfl: 10,
            afterAfl: 12,
            beforeRoundsWon: 0,
            afterRoundsWon: 1,
            beforeMargins: 2,
            afterMargins: 3,
            beforeUps: 1,
            afterUps: 2,
          ),
        ],
        roundChanges: <ScoringRoundChange>[
          ScoringRoundChange(
            tipperDbKey: 'tipper-1',
            tipperName: 'Alice',
            roundNumber: 7,
            beforeTotal: 2,
            afterTotal: 0,
            beforeNrl: 2,
            afterNrl: 0,
            beforeAfl: 0,
            afterAfl: 0,
            beforeRank: 4,
            afterRank: 6,
          ),
        ],
      ),
    );
  });

  testWidgets('shows a scoring change dialog after manual rescore', (
    tester,
  ) async {
    final disableBackStates = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: disableBackStates.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Rescore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(disableBackStates, <bool>[true]);
    expect(find.text('Rescore complete'), findsOneWidget);
    expect(find.text('Leaderboard changes'), findsOneWidget);
    expect(find.text('Round score changes'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Round 7 • Alice'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(disableBackStates, <bool>[true, false]);
  });
}
