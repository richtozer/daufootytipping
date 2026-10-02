import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_historical.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart';
import 'package:daufootytipping/pages/user_home/user_home_team_games_history_page.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
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
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ColorScheme scheme = dark
        ? FlexThemeData.dark(scheme: FlexScheme.green).colorScheme
        : FlexThemeData.light(scheme: FlexScheme.green).colorScheme;
    await tester.pumpWidget(
      MaterialApp(
        // The app's own scheme, with the test font, so the goldens show the
        // colours the pages actually resolve.
        theme: ThemeData(fontFamily: 'Roboto', colorScheme: scheme),
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

  AppTable table(WidgetTester tester) =>
      tester.widget<AppTable>(find.byType(AppTable).first);

  AppTableLayout measuredLayout(WidgetTester tester) {
    final context = tester.element(find.byType(AppTable).first);
    final body = Theme.of(context).textTheme.bodyMedium!;
    return AppTableLayout.measure(
      columns: table(tester).columns,
      rows: table(tester).rows,
      width: tester.getSize(find.byType(AppTable).first).width,
      textScaler: MediaQuery.textScalerOf(context),
      cellStyle: body,
      headingStyle: body.copyWith(fontWeight: FontWeight.w700),
      frozenLeading: 2,
    );
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

  testWidgets('comparison landscape golden', (tester) async {
    await pumpLadder(
      tester,
      compare: const ['first', 'second'],
      width: 1000,
      height: 500,
    );
    await expectLater(
      find.byKey(const Key('ladder-page')),
      matchesGoldenFile('goldens/league-ladder-comparison-landscape.png'),
    );
  });

  testWidgets('comparison landscape golden in dark mode', (tester) async {
    // Supporting text is drawn over the backdrop rather than on a surface, so
    // a fixed mid grey went dark-on-dark here.
    await pumpLadder(
      tester,
      compare: const ['first', 'second'],
      width: 1000,
      height: 500,
      dark: true,
    );
    await expectLater(
      find.byKey(const Key('ladder-page')),
      matchesGoldenFile('goldens/league-ladder-comparison-dark.png'),
    );
  });

  testWidgets('league ladder landscape golden', (tester) async {
    currentLadder = fullLadder();
    // A phone on its side: the rail has to earn its width against the widest
    // table in the app.
    await pumpLadder(tester, width: 728, height: 372);
    await expectLater(
      find.byKey(const Key('ladder-page')),
      matchesGoldenFile('goldens/league-ladder-landscape.png'),
    );
  });

  testWidgets('the ladder is an AppTable with rank and team held still', (
    tester,
  ) async {
    currentLadder = fullLadder();
    await pumpLadder(tester);

    final ladderTable = table(tester);
    expect(ladderTable.columns.length, 11);
    expect(ladderTable.frozenLeading, 2);
    expect(ladderTable.rows.length, 12);
    // Spelled out, because a narrow pane turns them on their side.
    expect(
      [for (final column in ladderTable.columns) column.label],
      [
        'Rank',
        'Team',
        'Games',
        'Points',
        'Won',
        'Lost',
        'Drawn',
        'Byes',
        'For',
        'Against',
        '%',
      ],
    );
    // Every column sorts, as the page's own instructions tell the user.
    expect(ladderTable.columns.every((column) => column.sortable), isTrue);
    // The whole ladder fills the page below the header, as every other table
    // page does, rather than running the page itself as one long scroll.
    expect(tester.getSize(find.byType(AppTable)).height, greaterThan(500));
    // Keep the cost of spelling the headings out visible. A rotated heading
    // sets the header's height for every column, so one long word is paid for
    // across the whole table -- which is why '%' was left as it is.
    expect(measuredLayout(tester).headerHeight, lessThanOrEqualTo(160));
    // The ladder arrives ranked, so the heading says so from the start
    // instead of showing a table that looks unsorted.
    expect(ladderTable.sort?.column, 0);
    expect(ladderTable.sort?.ascending, isTrue);
    expect(ladderTable.rows.first.key, const ValueKey('team-0'));
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

  testWidgets('the comparison names the teams and the season', (tester) async {
    await pumpLadder(tester, compare: const ['first', 'second']);
    // The competition's own season, not the current year: a comparison opened
    // on a past competition belongs to that one.
    expect(
      find.text('Original Leader v Original Runner-up in 2026'),
      findsOneWidget,
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
