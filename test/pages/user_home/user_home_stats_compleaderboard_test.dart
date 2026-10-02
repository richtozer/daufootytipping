import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundpointsfortipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/load_tips_fonts.dart';
import 'user_home_stats_data_tables_test.dart'
    show MockDAUCompsViewModel, MockStatsViewModel, MockTippersViewModel;

void main() {
  setUpAll(() => loadTipsFonts(includeFallbacks: true));
  late MockStatsViewModel stats;
  late MockTippersViewModel tippers;
  late List<LeaderboardEntry> entries;
  late List<VoidCallback> listeners;

  setUp(() async {
    await di.reset();
    final comps = MockDAUCompsViewModel();
    stats = MockStatsViewModel();
    tippers = MockTippersViewModel();
    listeners = [];
    entries = List.generate(
      24,
      (i) => LeaderboardEntry(
        rank: i + 1,
        tipper: Tipper(
          dbkey: 'tipper-$i',
          authuid: 'auth-$i',
          email: 'tipper-$i@example.com',
          compsPaidFor: <DAUComp>[],
          name: i == 0
              ? 'Test Tipper'
              : i == 1
              ? 'Alexandra Long Tipper Name'
              : 'Member $i',
          tipperRole: TipperRole.tipper,
        ),
        total: 654 - i * 7,
        nRL: 330 - i * 3,
        aFL: 324 - i * 4,
        numRoundsWon: i % 5,
        aflMargins: 24 - i,
        nrlMargins: 30 - i,
        aflUPS: i % 7,
        nrlUPS: i % 3,
        previousRank: i == 3 ? null : i + 1,
        rankChange: i == 3 ? null : [2, -12, 0][i % 3],
      ),
    );
    final comp = DAUComp(
      dbkey: 'comp-2026',
      name: 'Test Competition 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: <DAURound>[],
    );
    when(() => comps.addListener(any())).thenAnswer((_) {});
    when(() => comps.removeListener(any())).thenAnswer((_) {});
    when(() => comps.selectedDAUComp).thenReturn(comp);
    when(() => comps.isSelectedCompActiveComp()).thenReturn(true);
    when(() => stats.addListener(any())).thenAnswer((call) {
      listeners.add(call.positionalArguments.first as VoidCallback);
    });
    when(() => stats.removeListener(any())).thenAnswer((call) {
      listeners.remove(call.positionalArguments.first);
    });
    when(() => stats.compLeaderboard).thenAnswer((_) => entries);
    when(() => stats.hasLiveScoresInUse).thenReturn(false);
    when(() => stats.getTipperRoundPointsForComp(entries.first.tipper))
        .thenAnswer((_) => []);
    when(() => tippers.selectedTipper).thenReturn(entries.first.tipper);
    di.registerSingleton<DAUCompsViewModel>(comps);
    di.registerSingleton<StatsViewModel>(stats);
    di.registerSingleton<TippersViewModel>(tippers);
  });
  tearDown(() async => di.reset());

  void notify() {
    for (final listener in List<VoidCallback>.of(listeners)) {
      listener();
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    double width = 360,
    double height = 800,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const RepaintBoundary(
          key: Key('comp-page'),
          child: StatCompLeaderboard(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppTable table(WidgetTester tester) =>
      tester.widget<AppTable>(find.byType(AppTable));
  AppTableLayout layout(WidgetTester tester) {
    final context = tester.element(find.byType(AppTable));
    final body = Theme.of(context).textTheme.bodyMedium!;
    return AppTableLayout.measure(
      columns: table(tester).columns,
      rows: table(tester).rows,
      width: tester.getSize(find.byType(AppTable)).width,
      textScaler: MediaQuery.textScalerOf(context),
      cellStyle: body,
      headingStyle: body.copyWith(fontWeight: FontWeight.w600),
    );
  }

  for (final width in [360.0, 680.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('competition page golden $width/$scale', (tester) async {
        await pumpPage(tester, width: width, scale: scale);
        final measured = layout(tester);
        expect(measured.frozenLeading, 1);
        // Sizes to its content and leaves the rest to the backdrop, rather
        // than stretching a column across the pane. The halves still agree
        // with each other, which is what the frozen column depends on.
        if (!measured.scrollsHorizontally) {
          expect(
            measured.contentWidth,
            lessThanOrEqualTo(measured.viewportWidth + 0.001),
          );
        }
        expect(
          measured.frozenWidth +
              measured.widths
                  .skip(measured.frozenLeading)
                  .fold<double>(0, (a, b) => a + b),
          closeTo(measured.contentWidth, 0.001),
        );
        // Keep vertical-label growth visible as a deliberate regression budget.
        expect(measured.headerHeight, lessThanOrEqualTo(160));
        expect(tester.getSize(find.byType(ListView)).height, greaterThan(300));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const Key('comp-page')),
          matchesGoldenFile(
            'goldens/comp-leaderboard-${width.toInt()}-$scale.png',
          ),
        );
      });
    }
  }

  testWidgets('competition landscape golden', (tester) async {
    await pumpPage(tester, width: 900, height: 500);
    await expectLater(
      find.byKey(const Key('comp-page')),
      matchesGoldenFile('goldens/comp-leaderboard-landscape.png'),
    );
  });

  testWidgets(
    'competition sorting covers all nine columns and survives ticks',
    (tester) async {
      await pumpPage(tester, width: 1280);
      final keys = <int Function(LeaderboardEntry)>[
        (e) => e.rank,
        // Plain now: the column starts descending rather than sorting backwards.
        (e) => e.rankChange ?? 0,
        (e) => e.total,
        (e) => e.nRL,
        (e) => e.aFL,
        (e) => e.numRoundsWon,
        (e) => e.aflMargins + e.nrlMargins,
        (e) => e.aflUPS + e.nrlUPS,
      ];
      for (var column = 0; column < 9; column++) {
        for (final ascending in [true, false]) {
          table(tester).onSort!(column, ascending);
          await tester.pump();
          notify();
          await tester.pump();
          final ordered = table(tester).rows
              .map(
                (row) => entries.singleWhere(
                  (entry) => ValueKey(entry.tipper.dbkey) == row.key,
                ),
              )
              .toList();
          for (var i = 1; i < ordered.length; i++) {
            final comparison = column == 0
                ? ordered[i - 1].tipper.name.toLowerCase().compareTo(
                    ordered[i].tipper.name.toLowerCase(),
                  )
                : keys[column - 1](ordered[i - 1])
                      .compareTo(keys[column - 1](ordered[i]));
            expect(ascending ? comparison <= 0 : comparison >= 0, isTrue);
          }
          expect(table(tester).sort!.column, column);
          expect(table(tester).sort!.ascending, ascending);
        }
      }
      await tester.tap(find.text('Change'));
      await tester.pump();
      expect(table(tester).rows.first.cells[2].semanticLabel, 'Up 2 places');
      await tester.tap(find.text('Change'));
      await tester.pump();
      expect(table(tester).rows.first.cells[2].semanticLabel, 'Down 12 places');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'competition cache handles unchanged ticks, mutation, scale and selection',
    (tester) async {
      await pumpPage(tester);
      final original = table(tester).rows;
      notify();
      await tester.pump();
      expect(identical(original, table(tester).rows), isTrue);
      await pumpPage(tester, width: 1280);
      expect(identical(original, table(tester).rows), isTrue);
      entries.first.total = 999;
      notify();
      await tester.pump();
      expect(identical(original, table(tester).rows), isFalse);
      expect(table(tester).rows.first.cells[3].text, '999');
      final changed = table(tester).rows;
      final iconWidth = changed.first.cells[2].intrinsicSize.width;
      await pumpPage(tester, width: 1280, scale: 1.5);
      expect(
        table(tester).rows.first.cells[2].intrinsicSize.width,
        greaterThan(iconWidth),
      );
      when(() => tippers.selectedTipper).thenReturn(entries[1].tipper);
      notify();
      await tester.pump();
      expect(table(tester).rows.first.colour, Colors.transparent);
      expect(
        table(tester).rows[1].colour,
        Theme.of(tester.element(find.byType(AppTable))).highlightColor,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rank movement has accessible direction and row navigation', (
    tester,
  ) async {
    await pumpPage(tester, width: 1280);
    expect(
      table(tester).rows.take(4).map((row) => row.cells[2].semanticLabel),
      ['Up 2 places', 'Down 12 places', 'No rank change', '-'],
    );
    await tester.tap(find.text('654'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StatRoundPointsForTipper>(
            find.byType(StatRoundPointsForTipper),
          )
          .statsTipper,
      entries.first.tipper,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'competition last column is clear of scrollbar, names stay frozen',
    (tester) async {
      await pumpPage(tester, scale: 1.5);
      final nameX = tester.getTopLeft(find.text('Name')).dx;
      final nameY = tester.getTopLeft(find.text('Name')).dy;
      final totalX = tester.getTopLeft(find.text('Total')).dx;
      final horizontal = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      horizontal.jumpTo(horizontal.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Name')).dx, nameX);
      expect(tester.getTopLeft(find.text('Total')).dx, lessThan(totalX));
      final tableRight = tester.getRect(find.byType(AppTable)).right;
      expect(
        tester.getRect(find.text('UPS')).right,
        lessThanOrEqualTo(tableRight - AppTableLayout.scrollbarLane),
      );
      final vertical = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      vertical.jumpTo(300);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Name')).dy, nameY);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('competition rotation retains data and sort in short landscape', (
    tester,
  ) async {
    await pumpPage(tester, scale: 1.5);
    table(tester).onSort!(2, true);
    await tester.pump();
    final rows = table(tester).rows;
    await pumpPage(tester, width: 800, height: 360, scale: 1.5);
    expect(identical(rows, table(tester).rows), isTrue);
    expect(table(tester).sort!.column, 2);
    expect(tester.getSize(find.byType(ListView)).height, greaterThan(150));
    expect(tester.takeException(), isNull);
  });
}
