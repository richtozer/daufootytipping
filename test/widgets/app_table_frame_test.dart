import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/load_tips_fonts.dart';
import 'app_table_fixture.dart';

const _headingKey = Key('frame-heading');

Future<void> _pumpFrame(WidgetTester tester, Size viewSize) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  final rows = tableRows(count: 60);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        body: AppTableFrame(
          heading: const Text('Leaderboard', key: _headingKey),
          columns: tableColumns,
          rows: rows,
          table: AppTable(columns: tableColumns, rows: rows),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _rowsPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  setUpAll(() => loadTipsFonts(includeFallbacks: true));

  testWidgets('rotating keeps the rows where the reader left them', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpFrame(tester, const Size(800, 1000));
    _rowsPosition(tester).jumpTo(600);
    await tester.pump();

    // Landscape and wide enough for the heading to move into the side rail,
    // which moves the table to a different place in the widget tree.
    await _pumpFrame(tester, const Size(1000, 800));
    final heading = tester.getRect(find.byKey(_headingKey));
    final table = tester.getRect(find.byType(AppTable));
    expect(heading.right, lessThanOrEqualTo(table.left));
    expect(_rowsPosition(tester).pixels, 600);

    await _pumpFrame(tester, const Size(800, 1000));
    expect(_rowsPosition(tester).pixels, 600);
  });
}
