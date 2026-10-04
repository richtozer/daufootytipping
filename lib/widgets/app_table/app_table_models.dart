import 'package:flutter/material.dart';

/// Column intent, not a caller-assigned width. Numeric headings may rotate.
@immutable
class AppColumn {
  const AppColumn.text(
    this.label, {
    this.sortable = false,
    this.descendingFirst = false,
  }) : numeric = false;
  const AppColumn.numeric(
    this.label, {
    this.sortable = false,
    this.descendingFirst = true,
  }) : numeric = true;

  /// The last column of a table whose rows open something: the arrow that says
  /// so, with no heading and nothing to sort.
  const AppColumn.navigation()
    : label = '',
      numeric = false,
      sortable = false,
      descendingFirst = false;

  final String label;
  final bool numeric;
  final bool sortable;

  /// Which way the first tap on this heading sorts. Taps after it toggle, as
  /// they always have.
  ///
  /// A column of figures is asked "who has the most" before it is asked who
  /// has the least, so numeric columns start descending. A column of names is
  /// asked for A first. The exception is a column that is already a standing
  /// -- a rank or a ladder position -- where first place is the low number.
  final bool descendingFirst;
}

/// A measurable cell. Text can be shortened visually without losing its label.
/// Custom widgets declare their rendered size at the current text scale.
@immutable
class AppCell {
  const AppCell.text(
    String value, {
    this.style,
    this.leading,
    this.leadingSize = Size.zero,
    this.maxLines = 1,
    String? semanticLabel,
  }) : text = value,
       child = null,
       intrinsicSize = Size.zero,
       semanticLabel = semanticLabel ?? value;
  const AppCell.widget(
    Widget widget, {
    required this.intrinsicSize,
    required this.semanticLabel,
  }) : child = widget,
       text = null,
       style = null,
       leading = null,
       leadingSize = Size.zero,
       maxLines = 1;

  /// The forward arrow that ends a row which opens something, to sit under an
  /// [AppColumn.navigation]. The row itself is the control, so the arrow carries
  /// no label of its own.
  factory AppCell.navigation({Color? color}) => AppCell.widget(
    Icon(Icons.arrow_forward, size: navigationIconSize, color: color),
    intrinsicSize: const Size.square(navigationIconSize),
    semanticLabel: '',
  );

  /// The size of the arrow in an [AppCell.navigation].
  static const double navigationIconSize = 15;

  final String? text;

  /// Explicit lines remain measurable; long content still elides per cell.
  final int maxLines;
  final TextStyle? style;
  final Widget? child;
  final Widget? leading;
  final Size leadingSize;
  final Size intrinsicSize;
  final String semanticLabel;
}

/// Row interaction and colour remain owned by the caller; no selection state.
@immutable
class AppRow {
  const AppRow({required this.cells, this.onTap, this.colour, this.key});
  final List<AppCell> cells;
  final VoidCallback? onTap;
  final Color? colour;
  final LocalKey? key;
}

/// Controlled sorting: the caller sorts data in response to AppTable.onSort.
@immutable
class AppSort {
  const AppSort({required this.column, required this.ascending});
  final int column;
  final bool ascending;
}
