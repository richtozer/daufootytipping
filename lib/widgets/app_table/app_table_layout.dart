import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_table_models.dart';

enum AppHeadingLayout { horizontal, wrapped, rotated }

/// Width-independent content metrics. Row/column lists must be replaced, not
/// mutated in place, when content changes. Custom sizes use the current scale.
class AppTableMetrics {
  AppTableMetrics._({required this.columns, required this.content,
    required this.minimum, required this.headingSizes, required this.cellWidths,
    required this.rowHeight, required this.textScaler, required this.headingStyle,
    required this.direction});
  final List<AppColumn> columns;
  final List<double> content;
  final List<double> minimum;
  final List<Size> headingSizes;
  final Map<AppCell, double> cellWidths;
  final double rowHeight;
  final TextScaler textScaler;
  final TextStyle headingStyle;
  final TextDirection direction;

  static AppTableMetrics extract({required List<AppColumn> columns,
    required List<AppRow> rows, required TextScaler textScaler,
    required TextStyle headingStyle, required TextStyle cellStyle,
    TextDirection direction = TextDirection.ltr}) {
    if (columns.isEmpty || rows.any((row) => row.cells.length != columns.length)) {
      throw ArgumentError('AppTable needs columns and matching row cell counts.');
    }
    final painter = TextPainter(textDirection: direction, textScaler: textScaler);
    final cache = <(String, TextStyle), Size>{};
    Size text(String value, TextStyle style) => cache.putIfAbsent((value, style), () {
      painter.text = TextSpan(text: value, style: style);
      painter.layout();
      return painter.size;
    });
    try {
      final headingSizes = [for (final column in columns) text(column.label, headingStyle)];
      final content = List<double>.filled(columns.length, 0);
      final minimum = List<double>.filled(columns.length, 0);
      final cellWidths = <AppCell, double>{};
      var rowHeight = math.max(48.0, text('Mg', cellStyle).height + 16);
      for (final row in rows) {
        for (var index = 0; index < columns.length; index++) {
          final cell = row.cells[index];
          final value = cell.text;
          final style = cellStyle.merge(cell.style);
          final leading = cell.leading == null ? 0.0 : cell.leadingSize.width + 8;
          final size = value == null ? cell.intrinsicSize : text(value, style);
          if (!size.width.isFinite || !size.height.isFinite || size.width < 0 || size.height < 0) {
            throw ArgumentError('Custom cell dimensions must be finite and non-negative.');
          }
          cellWidths[cell] = size.width + leading;
          content[index] = math.max(content[index], size.width + leading);
          minimum[index] = math.max(minimum[index], value == null || columns[index].numeric
              ? size.width + leading : math.min(size.width, text('MMMM', style).width) + leading);
          rowHeight = math.max(rowHeight, math.max(size.height, cell.leadingSize.height) + 16);
        }
      }
      return AppTableMetrics._(columns: List.unmodifiable(columns),
        content: List.unmodifiable(content), minimum: List.unmodifiable(minimum),
        headingSizes: List.unmodifiable(headingSizes), cellWidths: Map.unmodifiable(cellWidths),
        rowHeight: rowHeight, textScaler: textScaler, headingStyle: headingStyle, direction: direction);
    } finally {
      painter.dispose();
    }
  }
}

/// Single-entry cache; resizing and interaction-only rebuilds reuse extraction.
/// Callers must provide new lists when rows, cells or columns change.
class AppTableMeasurementCache {
  Object? _key;
  AppTableMetrics? _metrics;

  AppTableMetrics measure({required List<AppColumn> columns, required List<AppRow> rows,
    required TextScaler textScaler, required TextStyle headingStyle,
    required TextStyle cellStyle, TextDirection direction = TextDirection.ltr}) {
    final key = (columns, rows, textScaler, headingStyle, cellStyle, direction);
    final cached = _metrics;
    if (key == _key && cached != null) return cached;
    final measured = AppTableMetrics.extract(columns: columns, rows: rows,
      textScaler: textScaler, headingStyle: headingStyle, cellStyle: cellStyle, direction: direction);
    _key = key;
    _metrics = measured;
    return measured;
  }
}

/// Pure sizing result shared by heading, body and frozen cells.
class AppTableLayout {
  AppTableLayout._({required this.widths, required this.headings,
    required this.padding, required this.headerHeight, required this.rowHeight,
    required this.viewportWidth, required this.frozenLeading});

  static const scrollbarLane = 14.0;
  static const sortIconSize = 18.0;
  static const sortGap = 4.0;
  final List<double> widths;
  final List<AppHeadingLayout> headings;
  final double padding;
  final double headerHeight;
  final double rowHeight;
  final double viewportWidth;
  final int frozenLeading;
  double get contentWidth => widths.fold(0, (sum, width) => sum + width);
  double get frozenWidth => widths.take(frozenLeading).fold(0, (sum, width) => sum + width);
  bool get scrollsHorizontally => contentWidth > viewportWidth + 0.01;

  static AppTableLayout measure({required List<AppColumn> columns,
    required List<AppRow> rows, required double width, required TextScaler textScaler,
    required TextStyle headingStyle, required TextStyle cellStyle,
    TextDirection direction = TextDirection.ltr, int frozenLeading = 1}) {
    return resolve(metrics: AppTableMetrics.extract(columns: columns, rows: rows,
        textScaler: textScaler, headingStyle: headingStyle, cellStyle: cellStyle,
        direction: direction), width: width, frozenLeading: frozenLeading);
  }

  /// Resolve widths from cached content without visiting any rows.
  static AppTableLayout resolve({required AppTableMetrics metrics,
    required double width, int frozenLeading = 1}) {
    final columns = metrics.columns;
    final headingSizes = metrics.headingSizes;
    final content = metrics.content;
    final minimum = metrics.minimum;
    final rowHeight = metrics.rowHeight;
    final headingStyle = metrics.headingStyle;
    if (!width.isFinite || width <= scrollbarLane) {
      throw ArgumentError('AppTable needs columns and a finite width greater than its scrollbar lane.');
    }
    if (frozenLeading < 0 || frozenLeading > columns.length) {
      throw ArgumentError('Invalid frozen column count or row cell count.');
    }
    final viewport = width - scrollbarLane;
    final painter = TextPainter(textDirection: metrics.direction, textScaler: metrics.textScaler);
    final cache = <(String, TextStyle, double), Size>{};
    Size text(String value, TextStyle style, [double maxWidth = double.infinity]) {
      final key = (value, style, maxWidth);
      return cache.putIfAbsent(key, () {
        painter.text = TextSpan(text: value, style: style);
        painter.layout(maxWidth: math.max(1, maxWidth));
        return painter.size;
      });
    }
    double iconWidth(int index) => columns[index].sortable ? sortIconSize + sortGap : 0;
    var padding = 12.0;
    List<double> natural() => [for (var i = 0; i < columns.length; i++)
      math.max(content[i], headingSizes[i].width + iconWidth(i)) + padding * 2];
    var widths = natural();
    double total() => widths.fold(0, (sum, value) => sum + value);
    final headings = List.filled(columns.length, AppHeadingLayout.horizontal);
    if (total() > viewport) {
      padding = 4;
      widths = natural();
    }
    if (total() > viewport) {
      for (var i = 0; i < columns.length; i++) {
        final target = math.max(content[i], math.max(headingSizes[i].height,
            columns[i].sortable ? sortIconSize : 0.0));
        if (target >= headingSizes[i].width + iconWidth(i)) continue;
        final wrapped = text(columns[i].label, headingStyle, target - iconWidth(i));
        if (wrapped.height <= headingSizes[i].height * 2 + 0.01 && target > iconWidth(i)) {
          headings[i] = AppHeadingLayout.wrapped;
          widths[i] = target + padding * 2;
        } else if (columns[i].numeric) {
          headings[i] = AppHeadingLayout.rotated;
          widths[i] = target + padding * 2;
        }
      }
    }
    // Shorten widest text columns only after using compact headings.
    final textColumns = [for (var i = 0; i < columns.length; i++) if (!columns[i].numeric) i]
      ..sort((a, b) => widths[b].compareTo(widths[a]));
    for (final i in textColumns) {
      if (total() <= viewport) break;
      final floor = math.max(minimum[i], headingSizes[i].height + iconWidth(i)) + padding * 2;
      widths[i] -= math.min(math.max(0, widths[i] - floor), total() - viewport);
      if (widths[i] < headingSizes[i].width + iconWidth(i) + padding * 2) {
        headings[i] = AppHeadingLayout.wrapped;
      }
    }
    final slack = viewport - total();
    if (slack > 0) {
      var recipients = [for (var i = 0; i < columns.length; i++) if (columns[i].grow) i];
      if (recipients.isEmpty) recipients = List.generate(columns.length, (index) => index);
      for (final i in recipients) { widths[i] += slack / recipients.length; }
      widths[recipients.last] += viewport - total();
    }
    var headerHeight = 48.0;
    for (var i = 0; i < columns.length; i++) {
      final available = widths[i] - padding * 2 - iconWidth(i);
      final height = headings[i] == AppHeadingLayout.rotated
          ? headingSizes[i].width + iconWidth(i)
          : math.max(text(columns[i].label, headingStyle, available).height,
              columns[i].sortable ? sortIconSize : 0);
      headerHeight = math.max(headerHeight, height + 16);
    }
    painter.dispose();
    // On extremely narrow panes keep some scrollable content reachable.
    var frozen = frozenLeading;
    while (frozen > 0 && total() > viewport &&
        widths.take(frozen).fold<double>(0, (sum, value) => sum + value) > viewport - 48) {
      frozen--;
    }
    return AppTableLayout._(widths: List.unmodifiable(widths),
      headings: List.unmodifiable(headings), padding: padding,
      headerHeight: headerHeight.ceilToDouble(), rowHeight: rowHeight.ceilToDouble(),
      viewportWidth: viewport, frozenLeading: frozen);
  }
}
