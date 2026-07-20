import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_rounds_table.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockGlobalDauCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockStatsViewModel extends Mock implements StatsViewModel {}

class MockConfigViewModel extends Mock implements ConfigViewModel {}

void main() {
  late MockGlobalDauCompsViewModel globalDauCompsViewModel;
  late MockGlobalDauCompsViewModel pageDauCompsViewModel;
  late DAUComp activeComp;
  late DAUComp viewedComp;
  late DAURound activeRound;
  late DAURound viewedRound;
  late MockStatsViewModel pageStatsViewModel;

  test('admin view model receives the shared config providers', () async {
    final configViewModel = MockConfigViewModel();
    when(() => configViewModel.cloudFunctionsBaseURL)
        .thenReturn('https://fixture.example.com');
    when(() => configViewModel.adminScoringRescoreURL)
        .thenReturn('https://rescore.example.com');
    when(() => configViewModel.loadAdminScoringRescoreURL())
        .thenAnswer((_) async => 'https://rescore.example.com');

    final viewModel = createAdminDauCompsViewModel(
      compKey: 'comp-2026',
      configViewModel: configViewModel,
      skipInit: true,
      cloudFunctionsBaseURLOverride: 'not-a-url',
    );

    expect(
      viewModel.resolveConfiguredCloudFunctionsBaseURL(),
      'https://fixture.example.com',
    );
    expect(
      viewModel.resolveConfiguredAdminScoringRescoreURL(),
      'https://rescore.example.com',
    );

  });

  setUp(() async {
    await di.reset();

    globalDauCompsViewModel = MockGlobalDauCompsViewModel();
    pageDauCompsViewModel = MockGlobalDauCompsViewModel();
    pageStatsViewModel = MockStatsViewModel();
    activeRound = _buildRound(26, DateTime.utc(2026, 3, 1), DateTime.utc(2026, 3, 2));
    viewedRound = _buildRound(3, DateTime.utc(2024, 3, 14), DateTime.utc(2024, 3, 17));
    activeComp = _buildComp('active-comp', 'DAU Footy Tipping 2026', rounds: <DAURound>[activeRound]);
    viewedComp = _buildComp('viewed-comp', 'DAU Footy Tipping 2024', rounds: <DAURound>[viewedRound]);

    when(
      () => globalDauCompsViewModel.initDAUCompDbKey,
    ).thenReturn(activeComp.dbkey);
    when(() => globalDauCompsViewModel.activeDAUComp).thenReturn(activeComp);
    when(() => globalDauCompsViewModel.selectedDAUComp).thenReturn(activeComp);
    when(
      () => globalDauCompsViewModel.changeDisplayedDAUComp(activeComp, false),
    ).thenAnswer((_) async {});
    when(() => globalDauCompsViewModel.linkGamesWithRounds(any())).thenAnswer((_) async {});
    when(() => globalDauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => globalDauCompsViewModel.removeListener(any())).thenAnswer((_) {});

    when(() => pageDauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => pageDauCompsViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => pageDauCompsViewModel.activeDAUComp).thenReturn(activeComp);
    when(() => pageDauCompsViewModel.selectedDAUComp).thenReturn(viewedComp);
    when(() => pageDauCompsViewModel.unassignedGames).thenReturn(const []);
    when(() => pageDauCompsViewModel.isDownloading).thenReturn(false);
    when(() => pageDauCompsViewModel.statsViewModel).thenReturn(pageStatsViewModel);
    when(() => pageDauCompsViewModel.linkGamesWithRounds(any())).thenAnswer((_) async {});
    when(() => pageStatsViewModel.isUpdateScoringRunning).thenReturn(false);
    when(() => pageStatsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => pageStatsViewModel.removeListener(any())).thenAnswer((_) {});

    di.registerSingleton<DAUCompsViewModel>(globalDauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets(
    'leaving admin edit does not reset the global selected competition',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DAUCompsEditPage(
                        viewedComp,
                        adminDauCompsViewModel: pageDauCompsViewModel,
                      ),
                    ),
                  );
                },
                child: const Text('Open admin edit'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open admin edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit DAU Comp'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Open admin edit'), findsOneWidget);
      verifyNever(
        () => globalDauCompsViewModel.changeDisplayedDAUComp(activeComp, false),
      );
    },
  );

  testWidgets(
    'admin edit uses the viewed comp rounds and relinks through the page view model',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DAUCompsEditPage(
            viewedComp,
            adminDauCompsViewModel: pageDauCompsViewModel,
          ),
        ),
      );

      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('26'), findsNothing);

      final roundsTable = tester.widget<AdminDaucompsEditRoundsTable>(
        find.byType(AdminDaucompsEditRoundsTable),
      );
      roundsTable.onRoundDateChanged(
        viewedRound,
        DateTime.utc(2024, 3, 14, 11),
        true,
      );
      await tester.pump();

      verify(
        () => pageDauCompsViewModel.linkGamesWithRounds(viewedComp.daurounds),
      ).called(1);
      verifyNever(
        () => globalDauCompsViewModel.linkGamesWithRounds(any()),
      );
    },
  );
}

DAUComp _buildComp(String dbKey, String name, {required List<DAURound> rounds}) {
  return DAUComp(
    dbkey: dbKey,
    name: name,
    aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
    nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
    daurounds: rounds,
  );
}

DAURound _buildRound(int number, DateTime start, DateTime end) {
  return DAURound(
    dAUroundNumber: number,
    firstGameKickOffUTC: start,
    lastGameKickOffUTC: end,
    games: <Game>[
      Game(
        dbkey: 'nrl-${number.toString().padLeft(2, '0')}-001',
        league: League.nrl,
        homeTeam: Team(dbkey: 'nrl-home-$number', name: 'Home $number', league: League.nrl),
        awayTeam: Team(dbkey: 'nrl-away-$number', name: 'Away $number', league: League.nrl),
        location: 'Test Stadium',
        startTimeUTC: start,
        fixtureRoundNumber: number,
        fixtureMatchNumber: 1,
      ),
    ],
  );
}
