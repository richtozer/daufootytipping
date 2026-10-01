import 'dart:collection';

import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/load_tips_fonts.dart';
import 'app_table_fixture.dart';

const _body = TextStyle(fontFamily: 'Roboto', fontSize: 14);
const _heading = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 14,
  fontWeight: FontWeight.w600,
);

AppTableLayout measure(
  double width, {
  double scale = 1,
  int frozen = 1,
  List<AppColumn> columns = tableColumns,
  List<AppRow>? rows,
}) => AppTableLayout.measure(
  columns: columns,
  rows: rows ?? tableRows(),
  width: width,
  textScaler: TextScaler.linear(scale),
  headingStyle: _heading,
  cellStyle: _body,
  frozenLeading: frozen,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTipsFonts);

  test('compact headings wrap at words, never inside Result or Score', () {
    const columns = [
      AppColumn.text('Result', sortable: true),
      AppColumn.text('Opponent', sortable: true),
      AppColumn.numeric('Score', sortable: true),
    ];
    final result = measure(
      360,
      scale: 1.5,
      columns: columns,
      rows: const [
        AppRow(
          cells: [
            AppCell.text('Won'),
            AppCell.text('A very long opponent name'),
            AppCell.text('125 - 120'),
          ],
        ),
      ],
    );
    for (var i = 0; i < columns.length; i++) {
      if (result.headings[i] == AppHeadingLayout.rotated) continue;
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(1.5),
        text: TextSpan(text: columns[i].label, style: _heading),
      )..layout();
      expect(
        result.widths[i] -
            result.padding * 2 -
            AppTableLayout.sortIconSize -
            AppTableLayout.sortGap,
        greaterThanOrEqualTo(painter.width - 0.01),
      );
      painter.dispose();
    }
  });

  test('a wide table sizes to its content and leaves the rest', () {
    final result = measure(1280);
    expect(result.headings, everyElement(AppHeadingLayout.horizontal));
    expect(result.scrollsHorizontally, isFalse);
    expect(result.widths.first, greaterThan(result.widths[1]));
    // Spare width stays spare. Spending it stretched one column across the
    // gap between a name and its numbers, and ran the table edge to edge on
    // a desktop browser.
    expect(result.contentWidth, lessThan(result.viewportWidth));
  });

  test(
    'at 360px numeric columns are narrow and long numeric headings rotate',
    () {
      final result = measure(360);
      expect(result.padding, 4);
      expect(result.headings[2], AppHeadingLayout.rotated);
      expect(result.widths[2], lessThan(40));
      expect(result.contentWidth, lessThanOrEqualTo(result.viewportWidth));
      expect(result.scrollsHorizontally, isFalse);
      expect(
        result.frozenWidth +
            result.widths
                .skip(result.frozenLeading)
                .fold<double>(0, (a, b) => a + b),
        closeTo(result.contentWidth, 0.0001),
      );
    },
  );

  test(
    'large text grows rows and columns without shrinking numeric values',
    () {
      final normal = measure(360);
      final large = measure(360, scale: 3.2);
      expect(large.rowHeight, greaterThan(normal.rowHeight));
      expect(large.headerHeight, greaterThan(normal.headerHeight));
      expect(large.widths[2], greaterThan(normal.widths[2]));
      expect(large.scrollsHorizontally, isTrue);
    },
  );

  test('two frozen columns share one budget including the scrollbar lane', () {
    final result = measure(360, frozen: 2);
    expect(result.frozenLeading, 2);
    expect(
      result.frozenWidth,
      closeTo(result.widths[0] + result.widths[1], 0.0001),
    );
    expect(result.viewportWidth + AppTableLayout.scrollbarLane, 360);
    // The halves agree with each other, which is the property the frozen
    // column needs. Whether they fill the pane is a separate question.
    expect(
      result.frozenWidth +
          result.widths
              .skip(result.frozenLeading)
              .fold<double>(0, (a, b) => a + b),
      closeTo(result.contentWidth, 0.0001),
    );
    expect(result.contentWidth, lessThanOrEqualTo(result.viewportWidth + 0.01));
  });

  test('custom cell footprints are preserved and can force scrolling', () {
    final result = measure(
      360,
      columns: const [AppColumn.text('Chart')],
      rows: const [
        AppRow(
          cells: [
            AppCell.widget(
              SizedBox(),
              intrinsicSize: Size(500, 90),
              semanticLabel: 'Chart',
            ),
          ],
        ),
      ],
    );
    expect(result.widths.single, greaterThanOrEqualTo(508));
    expect(result.rowHeight, 106);
    expect(result.scrollsHorizontally, isTrue);
    expect(result.frozenLeading, 0);
  });

  test('empty data measures headings and rejects mismatched rows', () {
    expect(measure(360, rows: []).widths.length, tableColumns.length);
    expect(
      () => measure(360, rows: const [AppRow(cells: [])]),
      throwsArgumentError,
    );
    expect(() => measure(double.infinity), throwsArgumentError);
  });

  test('nonlinear text scaling is passed through to text measurement', () {
    final linear = measure(360, scale: 2);
    final custom = AppTableLayout.measure(
      columns: tableColumns,
      rows: tableRows(),
      width: 360,
      textScaler: const _NonlinearScaler(),
      headingStyle: _heading,
      cellStyle: _body,
    );
    expect(custom.widths, linear.widths);
    expect(custom.rowHeight, linear.rowHeight);
  });

  test('resolving resize widths never reads the rows again', () {
    final rows = _CountingRows(tableRows(count: 300));
    final metrics = AppTableMetrics.extract(
      columns: tableColumns,
      rows: rows,
      textScaler: TextScaler.noScaling,
      headingStyle: _heading,
      cellStyle: _body,
    );
    rows.reads = 0;
    for (final width in [360.0, 500.0, 768.0, 1280.0]) {
      final resolved = AppTableLayout.resolve(metrics: metrics, width: width);
      expect(
        resolved.contentWidth,
        lessThanOrEqualTo(resolved.viewportWidth + 0.001),
      );
    }
    expect(rows.reads, 0);
  });

  test('cache reuses content and invalidates every measurement dependency', () {
    final cache = AppTableMeasurementCache();
    final rows = tableRows();
    AppTableMetrics get({
      List<AppRow>? data,
      List<AppColumn>? columns,
      double scale = 1,
      TextStyle body = _body,
      TextStyle heading = _heading,
      TextDirection direction = TextDirection.ltr,
    }) => cache.measure(
      columns: columns ?? tableColumns,
      rows: data ?? rows,
      textScaler: TextScaler.linear(scale),
      headingStyle: heading,
      cellStyle: body,
      direction: direction,
    );
    final original = get();
    expect(identical(original, get()), isTrue);
    expect(identical(original, get(data: [...rows])), isFalse);
    get();
    expect(identical(original, get(columns: [...tableColumns])), isFalse);
    final reset = get();
    expect(identical(reset, get(scale: 1.5)), isFalse);
    final restyled = get(body: _body.copyWith(fontSize: 18));
    expect(restyled.content[0], greaterThan(original.content[0]));
    final headingChanged = get(
      heading: _heading.copyWith(fontWeight: FontWeight.w900),
    );
    expect(identical(headingChanged, restyled), isFalse);
    expect(
      identical(headingChanged, get(direction: TextDirection.rtl)),
      isFalse,
    );
  });

  test('rotated sortable headings always reserve the full indicator width', () {
    final result = measure(360);
    for (var i = 0; i < tableColumns.length; i++) {
      if (result.headings[i] == AppHeadingLayout.rotated &&
          tableColumns[i].sortable) {
        expect(
          result.widths[i] - result.padding * 2,
          greaterThanOrEqualTo(AppTableLayout.sortIconSize),
        );
      }
    }
  });
}

class _CountingRows extends ListBase<AppRow> {
  _CountingRows(this.values);
  final List<AppRow> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => values.length = value;
  @override
  AppRow operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, AppRow value) => values[index] = value;
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) =>
      fontSize <= 14 ? fontSize * 2 : fontSize * 1.5;
  @override
  double get textScaleFactor => 2;
}
