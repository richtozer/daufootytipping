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
    when(() => dauCompsViewModel.isDownloading).thenReturn(false);
    when(() => statsViewModel.isUpdateScoringRunning).thenReturn(false);
    when(
      () => statsViewModel.updateStatsWithReport(
        comp,
        null,
        null,
        rebuildGameStats: true,
      ),
    ).thenAnswer(
      (_) async => const ScoringUpdateReport(
        resultMessage: 'Completed updates for 2 tippers and 3 rounds.',
        leaderboardChanges: <ScoringLeaderboardChange>[
          ScoringLeaderboardChange(
            tipperDbKey: 'tipper-1',
            tipperName: 'Alice',
            beforeRank: 3,
            afterRank: 3,
            beforeTotal: 18,
            afterTotal: 18,
            beforeNrl: 8,
            afterNrl: 8,
            beforeAfl: 10,
            afterAfl: 10,
            beforeRoundsWon: 0,
            afterRoundsWon: 0,
            beforeMargins: 2,
            afterMargins: 3,
            beforeUps: 1,
            afterUps: 1,
          ),
        ],
        roundChanges: <ScoringRoundChange>[
          ScoringRoundChange(
            tipperDbKey: 'tipper-1',
            tipperName: 'Alice',
            roundNumber: 7,
            beforeTotal: 2,
            afterTotal: 2,
            beforeNrl: 2,
            afterNrl: 2,
            beforeAfl: 0,
            afterAfl: 0,
            beforeRank: 4,
            afterRank: 3,
          ),
        ],
        gameStatsChanges: <ScoringGameStatsChange>[
          ScoringGameStatsChange(
            gameDbKey: 'afl-10-082',
            gameName: 'Lions v Cats',
            isPaidCohort: true,
            beforeAveragePoints: 0,
            afterAveragePoints: 0.14,
            beforeTipCount: 57,
            afterTipCount: 57,
          ),
        ],
      ),
    );
  });

  testWidgets('disables fixture download on web and shows a tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditFixtureButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
            isWebOverride: true,
          ),
        ),
      ),
    );

    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);

    await tester.ensureVisible(find.text('Download'));
    await tester.longPress(find.text('Download'));
    await tester.pumpAndSettle();

    expect(
      find.text(AdminDaucompsEditFixtureButton.webDisabledTooltip),
      findsOneWidget,
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
    await tester.pump();

    expect(disableBackStates, contains(true));
    expect(find.text('Rescore complete'), findsOneWidget);
    expect(find.text('Leaderboard changes'), findsOneWidget);
    expect(find.text('Round point changes'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Round 7 • Alice'), findsOneWidget);
    expect(find.text('Game average changes'), findsOneWidget);
    expect(find.text('Lions v Cats • Paid'), findsOneWidget);
    expect(find.text('Avg 0.0 -> 0.14'), findsOneWidget);
    expect(find.text('Margins 2 -> 3 (+1)'), findsOneWidget);
    expect(find.text('Round rank 4 -> 3 (up 1)'), findsOneWidget);
    expect(find.textContaining('Total 18 -> 18'), findsNothing);
    expect(find.textContaining('NRL 8 -> 8'), findsNothing);
    expect(find.textContaining('Rank 3 -> 3'), findsNothing);
    expect(find.textContaining('Rounds won 0 -> 0'), findsNothing);
    expect(find.textContaining('UPS 1 -> 1'), findsNothing);
    expect(find.textContaining('Total 2 -> 2'), findsNothing);
    verify(
      () => statsViewModel.updateStatsWithReport(
        comp,
        null,
        null,
        rebuildGameStats: true,
      ),
    ).called(1);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(disableBackStates.last, false);
  });

  testWidgets('shows the no-changes wording once', (tester) async {
    when(
      () => statsViewModel.updateStatsWithReport(
        comp,
        null,
        null,
        rebuildGameStats: true,
      ),
    ).thenAnswer(
      (_) async => const ScoringUpdateReport(
        resultMessage: 'Completed updates for 2 tippers and 3 rounds.',
        leaderboardChanges: <ScoringLeaderboardChange>[],
        roundChanges: <ScoringRoundChange>[],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Rescore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(find.text('Rescore complete'), findsOneWidget);
    expect(find.text('No scoring changes detected.'), findsOneWidget);
  });
}
