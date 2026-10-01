import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/load_tips_fonts.dart';
import 'app_table_fixture.dart';

Future<void> pumpTable(
  WidgetTester tester, {
  double width = 360,
  double height = 520,
  double scale = 1,
  int frozen = 1,
  List<AppRow>? rows,
  AppSort? sort,
  void Function(int, bool)? onSort,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        body: Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: const Key('table-picture'),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: AppTable(
                    columns: tableColumns,
                    rows: rows ?? tableRows(),
                    frozenLeading: frozen,
                    sort: sort,
                    onSort: onSort,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => loadTipsFonts(includeFallbacks: true));

  for (final width in [360.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('component golden $width at $scale', (tester) async {
        await pumpTable(
          tester,
          width: width,
          scale: scale,
          frozen: 2,
          sort: const AppSort(column: 1, ascending: true),
          onSort: (_, _) {},
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const Key('table-picture')),
          matchesGoldenFile('goldens/app-table-${width.toInt()}-$scale.png'),
        );
      });
    }
  }

  testWidgets('sort toggles controlled direction and rows remain tappable', (
    tester,
  ) async {
    (int, bool)? requested;
    var taps = 0;
    await pumpTable(
      tester,
      rows: tableRows(onTap: () => taps++),
      sort: const AppSort(column: 1, ascending: true),
      onSort: (c, a) => requested = (c, a),
    );
    await tester.tap(find.text('Rank'));
    expect(requested, (1, false));
    await tester.tap(find.text('Name'));
    expect(requested, (0, true));
    await tester.tap(find.text('Tipper 1'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header stays fixed while two frozen cells track vertical rows', (
    tester,
  ) async {
    await pumpTable(tester, scale: 2, frozen: 2);
    final headerY = tester.getTopLeft(find.text('Name')).dy;
    final vertical = tester.widget<ListView>(find.byType(ListView)).controller;
    expect(vertical, isNotNull);
    vertical?.jumpTo(300);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Name')).dy, headerY);
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller;
    final nameX = tester.getTopLeft(find.text('Name')).dx;
    final rankX = tester.getTopLeft(find.text('Rank')).dx;
    final pointsX = tester.getTopLeft(find.text('Total points')).dx;
    horizontal?.jumpTo(40);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Name')).dx, closeTo(nameX, 0.01));
    expect(tester.getTopLeft(find.text('Rank')).dx, closeTo(rankX, 0.01));
    expect(tester.getTopLeft(find.text('Total points')).dx, lessThan(pointsX));
    expect(tester.takeException(), isNull);
  });

  testWidgets('full names remain available through semantics and tooltips', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpTable(tester);
      expect(find.byTooltip('Alexandra Montgomery'), findsOneWidget);
      expect(find.bySemanticsLabel('Alexandra Montgomery'), findsWidgets);
      expect(find.bySemanticsLabel('Up one place'), findsWidgets);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty rows, resize and RTL scrolling do not overflow', (
    tester,
  ) async {
    await pumpTable(tester, rows: []);
    expect(tester.takeException(), isNull);
    await pumpTable(
      tester,
      direction: TextDirection.rtl,
      scale: 3.2,
      frozen: 2,
    );
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller;
    horizontal?.jumpTo(40);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await pumpTable(tester, width: 1280);
    expect(horizontal?.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short landscape panes at large text remain scrollable', (
    tester,
  ) async {
    await pumpTable(tester, width: 360, height: 200, scale: 3.2, frozen: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrollbars have their own lanes and custom cells keep their size',
    (tester) async {
      await pumpTable(tester, scale: 2, frozen: 2);
      final viewport = tester.getRect(find.byKey(const Key('table-picture')));
      final horizontal = tester.getRect(find.byType(SingleChildScrollView));
      expect(
        horizontal.right,
        closeTo(viewport.right - AppTableLayout.scrollbarLane, 0.01),
      );
      expect(
        horizontal.bottom,
        closeTo(viewport.bottom - AppTableLayout.scrollbarLane, 0.01),
      );
      final arrow = find.byIcon(Icons.arrow_upward).first;
      expect(tester.getSize(arrow), const Size(20, 20));
    },
  );

  testWidgets(
    'horizontal dragging preserves frozen row taps and highlighting',
    (tester) async {
      var taps = 0;
      await pumpTable(
        tester,
        scale: 2,
        frozen: 2,
        rows: tableRows(onTap: () => taps++),
      );
      final horizontal = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller;
      final before = tester.getTopLeft(find.text('Tipper 1'));
      await tester.drag(
        find.byKey(const ValueKey('row-0')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      expect(horizontal?.offset, greaterThan(0));
      expect(tester.getTopLeft(find.text('Tipper 1')), before);
      await tester.tap(find.text('Tipper 1'));
      expect(taps, 1);
      final coloured = tester.widgetList<Material>(
        find.descendant(
          of: find.byKey(const ValueKey('row-1')),
          matching: find.byType(Material),
        ),
      );
      expect(
        coloured
            .where((material) => material.color == Colors.lightGreen.shade100)
            .length,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large datasets build only visible rows', (tester) async {
    await pumpTable(tester, rows: tableRows(count: 1000));
    expect(find.byKey(const ValueKey('row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-999')), findsNothing);
    final vertical = tester.widget<ListView>(find.byType(ListView)).controller;
    vertical?.jumpTo(vertical.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row-999')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text tooltips appear only for values that are shortened', (
    tester,
  ) async {
    await pumpTable(tester);
    expect(find.byTooltip('Alexandra Montgomery'), findsOneWidget);
    expect(find.byTooltip('3'), findsNothing);
    await pumpTable(tester, width: 1280);
    expect(find.byTooltip('Alexandra Montgomery'), findsNothing);
  });

  testWidgets('the vertical track covers the rows, not the heading', (
    tester,
  ) async {
    await pumpTable(tester, scale: 2, frozen: 2);
    final bar = tester.getRect(
      find.byKey(const Key('appTableVerticalScrollbar')),
    );
    final list = tester.getRect(find.byType(ListView));
    final position = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .position;
    // RawScrollbar measures its track from the scrollable's viewport rather
    // than from its own box, so a bar wrapping the heading as well subtracts
    // that height twice -- once because the rows exclude it, again from any
    // padding meant to clear it -- and the thumb stops a heading short of the
    // last row. Its box has to be the rows.
    expect(bar.top, list.top);
    expect(bar.height, closeTo(position.viewportDimension, 0.01));
  });

  testWidgets('short tables do not request a permanent vertical thumb', (
    tester,
  ) async {
    await pumpTable(tester, rows: tableRows(count: 5));
    expect(
      tester
          .widget<RawScrollbar>(
            find.byKey(const Key('appTableVerticalScrollbar')),
          )
          .thumbVisibility,
      isFalse,
    );
    await pumpTable(tester);
    expect(
      tester
          .widget<RawScrollbar>(
            find.byKey(const Key('appTableVerticalScrollbar')),
          )
          .thumbVisibility,
      isTrue,
    );
  });

  testWidgets('frozen and scrolling halves expose one accessible row action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await pumpTable(tester, rows: tableRows(onTap: () {}), frozen: 2);
      var taps = 0;
      void count(SemanticsNode node) {
        if (node.getSemanticsData().hasAction(SemanticsAction.tap)) taps++;
        node.visitChildren((child) {
          count(child);
          return true;
        });
      }

      count(tester.getSemantics(find.byKey(const ValueKey('row-0'))));
      expect(taps, 1);
    } finally {
      handle.dispose();
    }
  });
}
