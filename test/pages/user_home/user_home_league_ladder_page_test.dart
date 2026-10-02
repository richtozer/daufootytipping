import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_historical.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart';
import 'package:daufootytipping/pages/user_home/user_home_team_games_history_page.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/load_tips_fonts.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  setUpAll(() => loadTipsFonts(includeFallbacks: true));
  late MockDAUCompsViewModel dauCompsViewModel;
  late ValueNotifier<int> ladderRevision;
  late LeagueLadder currentLadder;

  LeagueLadder ladder(String firstTeam, String secondTeam) {
    return LeagueLadder(
      league: League.nrl,
      teams: <LadderTeam>[
        LadderTeam(dbkey: 'first', teamName: firstTeam, originalRank: 1),
        LadderTeam(dbkey: 'second', teamName: secondTeam, originalRank: 2),
      ],
    );
  }

  /// A full ladder, so the table has enough rows and columns to scroll.
  LeagueLadder fullLadder() => LeagueLadder(
    league: League.nrl,
    teams: <LadderTeam>[
      for (var i = 0; i < 12; i++)
        LadderTeam(
          dbkey: 'team-$i',
          teamName: i == 0 ? 'Rabbitohs' : 'Team $i',
          originalRank: i + 1,
          played: 20,
          won: 20 - i,
          lost: i,
          drawn: 0,
          byes: 1,
          pointsFor: 500 - i * 7,
          pointsAgainst: 300 + i * 5,
          points: 40 - i * 2,
          percentage: 166.0 - i,
        ),
    ],
  );

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    dauCompsViewModel = MockDAUCompsViewModel();
    ladderRevision = ValueNotifier<int>(0);
    currentLadder = ladder('Original Leader', 'Original Runner-up');

    final selectedComp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );

    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(selectedComp);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);
    when(() => dauCompsViewModel.leagueLadderRevision)
        .thenReturn(ladderRevision);
    when(
      () => dauCompsViewModel.getOrCalculateLeagueLadder(
        League.nrl,
        forceRecalculate: any(named: 'forceRecalculate'),
      ),
    ).thenAnswer((_) async => currentLadder);
    when(() => dauCompsViewModel.getLeagueLadderAvailability(League.nrl))
        .thenReturn(LeagueLadderAvailability.ready);

    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  Future<void> pumpLadder(
    WidgetTester tester, {
    List<String>? compare,
    double width = 400,
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: RepaintBoundary(
          key: const Key('ladder-page'),
          child: LeagueLadderPage(
            league: League.nrl,
            teamDbKeysToDisplay: compare,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  for (final width in [360.0, 768.0]) {
    testWidgets('league ladder golden $width', (tester) async {
      currentLadder = fullLadder();
      await pumpLadder(tester, width: width, height: 900);
      await expectLater(
        find.byKey(const Key('ladder-page')),
        matchesGoldenFile('goldens/league-ladder-${width.toInt()}.png'),
      );
    });
  }

  AppTable table(WidgetTester tester) =>
      tester.widget<AppTable>(find.byType(AppTable).first);

  testWidgets('the ladder is an AppTable with rank and team held still', (
    tester,
  ) async {
    currentLadder = fullLadder();
    await pumpLadder(tester);

    final ladderTable = table(tester);
    expect(ladderTable.columns.length, 11);
    expect(ladderTable.frozenLeading, 2);
    expect(ladderTable.rows.length, 12);
    expect(ladderTable.columns.first.label, '#');
    expect(ladderTable.columns[1].label, 'Team');
    // Every column sorts, as the page's own instructions tell the user.
    expect(ladderTable.columns.every((column) => column.sortable), isTrue);
    // The whole ladder fills the page below the header, as every other table
    // page does, rather than running the page itself as one long scroll.
    expect(tester.getSize(find.byType(AppTable)).height, greaterThan(500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sorting reorders the view without touching the ladder', (
    tester,
  ) async {
    currentLadder = fullLadder();
    final originalOrder = [for (final team in currentLadder.teams) team.dbkey];
    await pumpLadder(tester);

    // '%' descending: the figures, not the rank the row came in with.
    table(tester).onSort!(10, false);
    await tester.pump();
    expect(table(tester).rows.first.key, const ValueKey('team-0'));
    table(tester).onSort!(10, true);
    await tester.pump();
    expect(table(tester).rows.first.key, const ValueKey('team-11'));

    // The unfiltered view is handed the cached ladder itself. Sorting its
    // list in place reordered what every other reader of the cache sees.
    expect([for (final team in currentLadder.teams) team.dbkey], originalOrder);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rank column sorts by the ladder position', (tester) async {
    currentLadder = fullLadder();
    await pumpLadder(tester);

    table(tester).onSort!(0, false);
    await tester.pump();
    expect(table(tester).rows.first.key, const ValueKey('team-11'));
    table(tester).onSort!(0, true);
    await tester.pump();
    expect(table(tester).rows.first.key, const ValueKey('team-0'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row opens that team\'s game history', (tester) async {
    currentLadder = fullLadder();
    await pumpLadder(tester);

    await tester.tap(find.text('Rabbitohs'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TeamGamesHistoryPage>(find.byType(TeamGamesHistoryPage))
          .team
          .dbkey,
      'team-0',
    );
  });

  testWidgets('comparison mode stacks the ladder over the matchups', (
    tester,
  ) async {
    await pumpLadder(tester, compare: const ['first', 'second']);

    // Two rows, sized to them rather than filling the page, so the historical
    // section below is reachable by scrolling the page.
    expect(table(tester).rows.length, 2);
    final tableHeight = tester.getSize(find.byType(AppTable).first).height;
    expect(tableHeight, lessThan(300), reason: 'sized to two rows, not to 900');
    expect(find.byType(LeagueLadderHistoricalMatchups), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow portrait ladder lays out without overflowing', (
    tester,
  ) async {
    currentLadder = fullLadder();
    await pumpLadder(tester, width: 320, height: 640);
    expect(find.byType(AppTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshes an open ladder when fixture scores invalidate it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LeagueLadderPage(league: League.nrl)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Original Leader'), findsOneWidget);
    expect(find.text('Original Runner-up'), findsOneWidget);

    currentLadder = ladder('Updated Leader', 'Updated Runner-up');
    ladderRevision.value++;

    await tester.pump();
    await tester.pump();

    expect(find.text('Updated Leader'), findsOneWidget);
    expect(find.text('Updated Runner-up'), findsOneWidget);
    expect(find.text('Original Leader'), findsNothing);
    expect(find.text('Original Runner-up'), findsNothing);
  });
}
