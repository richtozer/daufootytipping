import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_rounds_table.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_warning.dart';
import 'package:daufootytipping/services/rounds_linking_service.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/app_controls_test_app.dart';

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
  late AppControlsViewModel appControls;

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
    appControls = registerAppControlsViewModel();

    globalDauCompsViewModel = MockGlobalDauCompsViewModel();
    pageDauCompsViewModel = MockGlobalDauCompsViewModel();
    pageStatsViewModel = MockStatsViewModel();
    activeRound = _buildRound(
      26,
      DateTime.utc(2026, 3, 1),
      DateTime.utc(2026, 3, 2),
    );
    viewedRound = _buildRound(
      3,
      DateTime.utc(2024, 3, 14),
      DateTime.utc(2024, 3, 17),
    );
    activeComp = _buildComp(
      'active-comp',
      'DAU Footy Tipping 2026',
      rounds: <DAURound>[activeRound],
    );
    viewedComp = _buildComp(
      'viewed-comp',
      'DAU Footy Tipping 2024',
      rounds: <DAURound>[viewedRound],
    );

    when(() => globalDauCompsViewModel.initDAUCompDbKey)
        .thenReturn(activeComp.dbkey);
    when(() => globalDauCompsViewModel.activeDAUComp).thenReturn(activeComp);
    when(() => globalDauCompsViewModel.selectedDAUComp).thenReturn(activeComp);
    when(
      () => globalDauCompsViewModel.changeDisplayedDAUComp(activeComp, false),
    ).thenAnswer((_) async {});
    when(() => globalDauCompsViewModel.linkGamesWithRounds(any()))
        .thenAnswer((_) async {});
    when(() => globalDauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => globalDauCompsViewModel.removeListener(any()))
        .thenAnswer((_) {});

    when(() => pageDauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => pageDauCompsViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => pageDauCompsViewModel.activeDAUComp).thenReturn(activeComp);
    when(() => pageDauCompsViewModel.selectedDAUComp).thenReturn(viewedComp);
    when(() => pageDauCompsViewModel.unassignedGames).thenReturn(const []);
    when(() => pageDauCompsViewModel.splitRoundGames).thenReturn(const []);
    when(() => pageDauCompsViewModel.isDownloading).thenReturn(false);
    when(() => pageDauCompsViewModel.otherViewModelsLoadComplete)
        .thenAnswer((_) async {});
    when(() => pageDauCompsViewModel.statsViewModel)
        .thenReturn(pageStatsViewModel);
    when(() => pageDauCompsViewModel.linkGamesWithRounds(any()))
        .thenAnswer((_) async {});
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
        appWithControls(
          appControls,
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

  testWidgets('offers Run updates in the corner beside Save and Back', (
    tester,
  ) async {
    await tester.pumpWidget(
      appWithControls(appControls, home: const SizedBox.shrink()),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => DAUCompsEditPage(
              viewedComp,
              adminDauCompsViewModel: pageDauCompsViewModel,
            ),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.byIcon(Icons.save), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Run Updates'), findsNothing, reason: 'no in-page button');
  });

  group('Run updates availability', () {
    Future<void> openEditPage(WidgetTester tester) async {
      await tester.pumpWidget(
        appWithControls(appControls, home: const SizedBox.shrink()),
      );
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => DAUCompsEditPage(
                viewedComp,
                adminDauCompsViewModel: pageDauCompsViewModel,
              ),
            ),
          );
      await tester.pumpAndSettle();
    }

    // The action is enabled when its tap handler is set.
    VoidCallback? runUpdatesOnTap(WidgetTester tester) => tester
        .widget<InkResponse>(
          find.ancestor(
            of: find.byIcon(Icons.sync),
            matching: find.byType(InkResponse),
          ),
        )
        .onTap;

    testWidgets(
      'is available as soon as the admin view models have loaded, with no form edit',
      (tester) async {
        // The admin view models load after the page opens, and loading does
        // not notify listeners; the stats view model simply appears.
        final loaded = Completer<void>();
        StatsViewModel? loadedStats;
        when(() => pageDauCompsViewModel.statsViewModel)
            .thenAnswer((_) => loadedStats);
        when(() => pageDauCompsViewModel.otherViewModelsLoadComplete)
            .thenAnswer((_) => loaded.future);

        await openEditPage(tester);
        expect(
          runUpdatesOnTap(tester),
          isNull,
          reason: 'nothing to run updates against until loading finishes',
        );

        loadedStats = pageStatsViewModel;
        loaded.complete();
        await tester.pumpAndSettle();

        expect(
          runUpdatesOnTap(tester),
          isNotNull,
          reason:
              'Run updates must not wait for an unrelated change to the form',
        );
      },
    );

    testWidgets(
      'follows the download, disabled while it runs and enabled after',
      (tester) async {
        final listeners = <VoidCallback>[];
        when(() => pageDauCompsViewModel.addListener(any())).thenAnswer((
          invocation,
        ) {
          listeners.add(invocation.positionalArguments.first as VoidCallback);
        });

        await openEditPage(tester);
        expect(runUpdatesOnTap(tester), isNotNull);

        when(() => pageDauCompsViewModel.isDownloading).thenReturn(true);
        for (final listener in List<VoidCallback>.of(listeners)) {
          listener();
        }
        await tester.pumpAndSettle();
        expect(
          runUpdatesOnTap(tester),
          isNull,
          reason: 'a download is running',
        );

        when(() => pageDauCompsViewModel.isDownloading).thenReturn(false);
        for (final listener in List<VoidCallback>.of(listeners)) {
          listener();
        }
        await tester.pumpAndSettle();
        expect(runUpdatesOnTap(tester), isNotNull);
      },
    );
  });

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
      );
      await tester.pump();

      verify(
        () => pageDauCompsViewModel.linkGamesWithRounds(viewedComp.daurounds),
      ).called(1);
      verifyNever(() => globalDauCompsViewModel.linkGamesWithRounds(any()));
    },
  );

  testWidgets(
    'save button stays enabled after a round start edit followed by a text edit',
    (tester) async {
      await tester.pumpWidget(
        appWithControls(appControls, home: const SizedBox.shrink()),
      );
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => DAUCompsEditPage(
                viewedComp,
                adminDauCompsViewModel: pageDauCompsViewModel,
              ),
            ),
          );
      await tester.pumpAndSettle();

      VoidCallback? saveOnTap() => tester
          .widget<InkResponse>(
            find.ancestor(
              of: find.byIcon(Icons.save),
              matching: find.byType(InkResponse),
            ),
          )
          .onTap;

      expect(saveOnTap(), isNull);

      final roundsTable = tester.widget<AdminDaucompsEditRoundsTable>(
        find.byType(AdminDaucompsEditRoundsTable),
      );
      roundsTable.onRoundDateChanged(
        viewedRound,
        DateTime.utc(2024, 3, 14, 11),
      );
      await tester.pumpAndSettle();
      expect(saveOnTap(), isNotNull);

      final nameField = find.byType(TextFormField).first;
      await tester.enterText(nameField, 'Renamed Comp');
      await tester.pumpAndSettle();
      expect(saveOnTap(), isNotNull);

      // Even reverting the text field back to the original name keeps Save
      // enabled while the round start date override remains modified.
      await tester.enterText(nameField, viewedComp.name);
      await tester.pumpAndSettle();
      expect(saveOnTap(), isNotNull);
    },
  );

  testWidgets(
    'shows both unassigned and split-round warnings and clears split warning when round start moves back',
    (tester) async {
      final teamHome = Team(
        dbkey: 'nrl-home',
        name: 'Broncos',
        league: League.nrl,
      );
      final teamAway = Team(
        dbkey: 'nrl-away',
        name: 'Roosters',
        league: League.nrl,
      );
      final earlyGame = Game(
        dbkey: 'nrl-02-001',
        league: League.nrl,
        homeTeam: teamHome,
        awayTeam: teamAway,
        location: 'Suncorp',
        startTimeUTC: DateTime.utc(2030, 3, 9, 9, 0),
        fixtureRoundNumber: 2,
        fixtureMatchNumber: 1,
      );
      final homeGame1 = Game(
        dbkey: 'nrl-02-002',
        league: League.nrl,
        homeTeam: teamHome,
        awayTeam: teamAway,
        location: 'Suncorp',
        startTimeUTC: DateTime.utc(2030, 3, 15, 9, 0),
        fixtureRoundNumber: 2,
        fixtureMatchNumber: 2,
      );
      final homeGame2 = Game(
        dbkey: 'nrl-02-003',
        league: League.nrl,
        homeTeam: teamHome,
        awayTeam: teamAway,
        location: 'Suncorp',
        startTimeUTC: DateTime.utc(2030, 3, 16, 9, 0),
        fixtureRoundNumber: 2,
        fixtureMatchNumber: 3,
      );
      final unassignedGame = Game(
        dbkey: 'nrl-00-001',
        league: League.nrl,
        homeTeam: teamHome,
        awayTeam: teamAway,
        location: 'Suncorp',
        startTimeUTC: DateTime.utc(2030, 2, 1, 9, 0),
        fixtureRoundNumber: 0,
        fixtureMatchNumber: 1,
      );

      final round1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.utc(2030, 3, 1, 8, 0),
        lastGameKickOffUTC: DateTime.utc(2030, 3, 3, 12, 0),
        games: [earlyGame],
      )..nrlGameCount = 1;
      final round2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: DateTime.utc(2030, 3, 14, 8, 0),
        lastGameKickOffUTC: DateTime.utc(2030, 3, 16, 12, 0),
        games: [homeGame1, homeGame2],
      )..nrlGameCount = 2;

      final splitComp = _buildComp(
        'split-comp',
        'Split Comp',
        rounds: [round1, round2],
      );

      const linking = RoundsLinkingService();
      var currentUnassigned = <Game>[unassignedGame];
      var currentSplit = linking.computeSplitRoundGames(
        rounds: splitComp.daurounds,
        now: DateTime.utc(2030, 1, 1),
      );

      when(() => pageDauCompsViewModel.selectedDAUComp).thenReturn(splitComp);
      when(() => pageDauCompsViewModel.unassignedGames)
          .thenAnswer((_) => currentUnassigned);
      when(() => pageDauCompsViewModel.splitRoundGames)
          .thenAnswer((_) => currentSplit);
      when(() => pageDauCompsViewModel.linkGamesWithRounds(any())).thenAnswer((
        invocation,
      ) async {
        final rounds = invocation.positionalArguments.first as List<DAURound>;
        final all = <Game>[unassignedGame, earlyGame, homeGame1, homeGame2];
        for (final r in rounds) {
          r.games = all
              .where(
                (g) =>
                    g.getDAURound(splitComp)?.dAUroundNumber ==
                    r.dAUroundNumber,
              )
              .toList();
        }
        currentUnassigned = linking.finalizeRoundsAndComputeUnassigned(
          rounds: rounds,
          allGames: all,
        );
        currentSplit = linking.computeSplitRoundGames(
          rounds: rounds,
          now: DateTime.utc(2030, 1, 1),
        );
      });

      await tester.pumpWidget(
        appWithControls(
          appControls,
          home: DAUCompsEditPage(
            splitComp,
            adminDauCompsViewModel: pageDauCompsViewModel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(kUnassignedGamesWarningTitle), findsOneWidget);
      expect(find.text(kSplitRoundGamesWarningTitle), findsOneWidget);
      expect(
        find.textContaining('in DAU Round 1, home DAU Round 2'),
        findsOneWidget,
      );

      final roundsTable = tester.widget<AdminDaucompsEditRoundsTable>(
        find.byType(AdminDaucompsEditRoundsTable),
      );
      // Move Round 2 start back before earlyGame -> earlyGame joins Round 2.
      roundsTable.onRoundDateChanged(round2, DateTime.utc(2030, 3, 9, 8, 0));
      await tester.pumpAndSettle();

      expect(find.text(kUnassignedGamesWarningTitle), findsOneWidget);
      expect(find.text(kSplitRoundGamesWarningTitle), findsNothing);
    },
  );
}

DAUComp _buildComp(
  String dbKey,
  String name, {
  required List<DAURound> rounds,
}) {
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
        homeTeam: Team(
          dbkey: 'nrl-home-$number',
          name: 'Home $number',
          league: League.nrl,
        ),
        awayTeam: Team(
          dbkey: 'nrl-away-$number',
          name: 'Away $number',
          league: League.nrl,
        ),
        location: 'Test Stadium',
        startTimeUTC: start,
        fixtureRoundNumber: number,
        fixtureMatchNumber: 1,
      ),
    ],
  );
}
