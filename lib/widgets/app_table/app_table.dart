import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'app_table_layout.dart';
import 'app_table_models.dart';

export 'app_table_layout.dart';
export 'app_table_models.dart';

/// Content-sized table with a sticky header and frozen leading columns.
/// Requires bounded width and height. Sorting and row data are caller-owned.
/// Replace row/column lists when content changes; do not mutate them in place.
class AppTable extends StatefulWidget {
  const AppTable({super.key, required this.columns, required this.rows,
    this.frozenLeading = 1, this.sort, this.onSort, this.empty,
    this.sortAscendingLabel = 'Ascending', this.sortDescendingLabel = 'Descending'});
  final List<AppColumn> columns;
  final List<AppRow> rows;
  final int frozenLeading;
  final AppSort? sort;
  final void Function(int column, bool ascending)? onSort;
  final Widget? empty;
  /// Localizable descriptions for assistive technology.
  final String sortAscendingLabel;
  final String sortDescendingLabel;

  @override
  State<AppTable> createState() => _AppTableState();
}

class _AppTableState extends State<AppTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _headingVertical = ScrollController();
  final _measurements = AppTableMeasurementCache();
  late AppTableMetrics _metrics;

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    _headingVertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final heading = body.copyWith(fontWeight: FontWeight.w600);
    final direction = Directionality.of(context);
    _metrics = _measurements.measure(columns: widget.columns, rows: widget.rows,
      textScaler: MediaQuery.textScalerOf(context), headingStyle: heading,
      cellStyle: body, direction: direction);
    return LayoutBuilder(builder: (context, bounds) {
      if (!bounds.hasBoundedHeight) {
        throw FlutterError('AppTable requires a bounded height, for example an Expanded child.');
      }
      final layout = AppTableLayout.resolve(metrics: _metrics, width: bounds.maxWidth,
        frozenLeading: widget.frozenLeading);
      final lane = AppTableLayout.scrollbarLane;
      final horizontalLane = layout.scrollsHorizontally ? lane : 0.0;
      final contentHeight = math.max(0.0, bounds.maxHeight - horizontalLane);
      final headerViewport = math.min(layout.headerHeight,
          math.max(0.0, contentHeight - math.min(layout.rowHeight, contentHeight / 2)));
      Widget header = _row(context, layout, heading, body, null);
      if (headerViewport < layout.headerHeight) {
        // Very short landscape panes retain room for rows. The heading stays
        // pinned and can be scrolled to read its full labels without shrinking text.
        header = SizedBox(height: headerViewport,
          child: NotificationListener<ScrollNotification>(onNotification: (_) => true,
            child: SingleChildScrollView(controller: _headingVertical, child: header)));
      }
      // The scrollbar tracks occupy explicit lanes outside the content viewport.
      final scrollsVertically = widget.rows.length * layout.rowHeight > contentHeight - headerViewport;
      return RawScrollbar(controller: _vertical, thumbVisibility: scrollsVertically, thickness: 8,
        scrollbarOrientation: direction == TextDirection.ltr
            ? ScrollbarOrientation.right : ScrollbarOrientation.left,
        notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
        child: Padding(padding: EdgeInsetsDirectional.only(end: lane),
          child: RawScrollbar(controller: _horizontal, thumbVisibility: layout.scrollsHorizontally,
            thickness: 8, scrollbarOrientation: ScrollbarOrientation.bottom,
            notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
            child: Padding(padding: EdgeInsets.only(bottom: horizontalLane),
              child: ScrollConfiguration(behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(controller: _horizontal, scrollDirection: Axis.horizontal,
                  child: SizedBox(width: layout.contentWidth, height: contentHeight,
                    child: Column(children: [
                      header,
                      Expanded(child: widget.rows.isEmpty && widget.empty != null
                        ? SingleChildScrollView(controller: _vertical, child: widget.empty)
                        : ListView.builder(controller: _vertical, primary: false,
                            padding: EdgeInsets.zero, itemExtent: layout.rowHeight,
                            itemCount: widget.rows.length,
                            itemBuilder: (context, index) => _row(context, layout, heading, body, index))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _row(BuildContext context, AppTableLayout layout, TextStyle heading,
      TextStyle body, int? index) {
    final theme = Theme.of(context);
    final row = index == null ? null : widget.rows[index];
    final colour = index == null ? theme.colorScheme.surfaceContainerHighest
        : Color.alphaBlend(row?.colour ?? Colors.transparent, theme.colorScheme.surface);
    final height = index == null ? layout.headerHeight : layout.rowHeight;
    Widget cell(int column) => SizedBox(width: layout.widths[column], height: height,
      child: row == null ? _heading(context, layout, column, heading)
          : _cell(layout, row.cells[column], widget.columns[column], body, column));
    Widget surface(Widget child, {bool frozen = false}) => Material(color: colour, child: InkWell(
      excludeFromSemantics: true, canRequestFocus: !frozen && row?.onTap != null,
      onTap: row?.onTap, child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: child)));
    final scrollingCells = surface(Row(children: [
      SizedBox(width: layout.frozenWidth),
      for (var i = layout.frozenLeading; i < widget.columns.length; i++) cell(i),
    ]));
    final frozenCells = surface(Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < layout.frozenLeading; i++) cell(i),
    ]), frozen: true);
    return Semantics(container: true, button: row?.onTap != null, onTap: row?.onTap,
      child: SizedBox(key: row?.key, height: height,
      child: AnimatedBuilder(animation: _horizontal, builder: (context, child) {
        final offset = _horizontal.hasClients
            ? _horizontal.offset.clamp(0.0, (layout.contentWidth - layout.viewportWidth).clamp(0.0, double.infinity))
            : 0.0;
        return Stack(children: [
          scrollingCells,
          if (layout.frozenLeading > 0)
            PositionedDirectional(start: offset, top: 0, bottom: 0,
              child: frozenCells),
        ]);
      }),
    ));
  }

  Widget _heading(BuildContext context, AppTableLayout layout, int index, TextStyle style) {
    final column = widget.columns[index];
    final selected = widget.sort?.column == index;
    final ascending = selected ? !(widget.sort?.ascending ?? false) : true;
    final sortable = column.sortable && widget.onSort != null;
    final rotated = layout.headings[index] == AppHeadingLayout.rotated;
    final indicator = SizedBox(width: AppTableLayout.sortIconSize, height: AppTableLayout.sortIconSize,
          child: selected ? ExcludeSemantics(child: Icon(
            widget.sort?.ascending == true ? Icons.arrow_upward : Icons.arrow_downward,
            size: AppTableLayout.sortIconSize)) : null);
    final label = rotated ? Column(mainAxisSize: MainAxisSize.min, children: [
      RotatedBox(quarterTurns: 3, child: Text(column.label, style: style)),
      if (column.sortable) ...[const SizedBox(height: AppTableLayout.sortGap), indicator],
    ]) : Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(column.label, style: style)),
      if (column.sortable) ...[
        const SizedBox(width: AppTableLayout.sortGap), indicator,
      ],
    ]);
    return Semantics(container: true, sortKey: OrdinalSortKey(index.toDouble()),
      header: true, button: sortable,
      label: column.label, value: selected ? (widget.sort?.ascending == true
          ? widget.sortAscendingLabel : widget.sortDescendingLabel) : null,
      child: Tooltip(message: column.label, child: InkWell(
        onTap: sortable ? () => widget.onSort?.call(index, ascending) : null,
        child: Padding(padding: EdgeInsets.symmetric(horizontal: layout.padding, vertical: 8),
          child: Align(alignment: column.numeric ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart, child: ExcludeSemantics(child: label))),
      )),
    );
  }

  Widget _cell(AppTableLayout layout, AppCell cell, AppColumn column, TextStyle body, int index) {
    final value = cell.text;
    Widget child;
    if (value != null) {
      child = Text(value, style: body.merge(cell.style), maxLines: 1,
        overflow: TextOverflow.ellipsis, textAlign: column.numeric ? TextAlign.end : TextAlign.start);
      if (cell.leading != null) {
        child = Row(children: [SizedBox.fromSize(size: cell.leadingSize, child: cell.leading),
          const SizedBox(width: 8), Expanded(child: child)]);
      }
    } else {
      child = SizedBox.fromSize(size: cell.intrinsicSize, child: cell.child);
    }
    final shortened = value != null &&
        (_metrics.cellWidths[cell] ?? 0) > layout.widths[index] - layout.padding * 2 + 0.01;
    if (shortened || value == null) child = Tooltip(message: cell.semanticLabel, child: child);
    return Semantics(container: true, sortKey: OrdinalSortKey(index.toDouble()),
      label: cell.semanticLabel, excludeSemantics: true,
      child: Padding(padding: EdgeInsets.symmetric(horizontal: layout.padding, vertical: 8),
          child: Align(alignment: column.numeric ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart, child: child)));
  }
}
