import 'package:flutter/material.dart';

/// Column intent, not a caller-assigned width. Numeric headings may rotate.
@immutable
class AppColumn {
  const AppColumn.text(this.label, {this.grow = false, this.sortable = false})
      : numeric = false;
  const AppColumn.numeric(this.label, {this.sortable = false})
      : numeric = true, grow = false;

  final String label;
  final bool numeric;
  final bool grow;
  final bool sortable;
}

/// A measurable cell. Text can be shortened visually without losing its label.
/// Custom widgets declare their rendered size at the current text scale.
@immutable
class AppCell {
  const AppCell.text(String value, {this.style, this.leading,
    this.leadingSize = Size.zero, this.maxLines = 1})
      : text = value, child = null, intrinsicSize = Size.zero, semanticLabel = value;
  const AppCell.widget(Widget widget, {required this.intrinsicSize,
    required this.semanticLabel})
      : child = widget, text = null, style = null, leading = null,
        leadingSize = Size.zero, maxLines = 1;

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
