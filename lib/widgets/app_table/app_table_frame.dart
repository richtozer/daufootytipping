import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_table_layout.dart';
import 'app_table_models.dart';

/// The heading block every table page carries: a mark, a title, an optional
/// subtitle and the sentence or two explaining the page.
///
/// Stacks the mark above the title once it is laid out in something too narrow
/// to put them side by side, which is what the landscape rail gives it.
class AppTableHeading extends StatelessWidget {
  const AppTableHeading({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.description,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final String? description;

  /// Below this the mark and the title stop sharing a line.
  static const double sideBySideWidth = 320;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget titleText = Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
    final String? subtitleText = subtitle;
    final String? descriptionText = description;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool sideBySide = constraints.maxWidth >= sideBySideWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sideBySide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(child: titleText),
                ],
              )
            else ...[
              leading,
              const SizedBox(height: 8),
              titleText,
            ],
            if (subtitleText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitleText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (descriptionText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  descriptionText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    // The scheme's own supporting-text colour, not a fixed
                    // grey: these sit over the backdrop rather than on a
                    // surface, and a mid grey went dark-on-dark at night.
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Puts a table and its heading together the way every table page wants them.
///
/// Portrait stacks them, with the heading held to the same rails as the rows
/// beneath it: the table sizes to its content and sits centred, so a heading
/// spanning the whole pane floated free of the thing it describes.
///
/// Landscape has width to spare and no height, so the heading moves into a
/// rail down the side and the table takes the rest. The columns answer by
/// turning their headings on their side, which they already do whenever the
/// pane is tighter than their natural width.
class AppTableFrame extends StatefulWidget {
  const AppTableFrame({
    super.key,
    required this.heading,
    required this.columns,
    required this.rows,
    required this.table,
    this.frozenLeading = 1,
    this.banner,
    this.fill = true,
  });

  final Widget heading;

  /// Measured to find the rails. The same lists the table is given.
  final List<AppColumn> columns;
  final List<AppRow> rows;
  final int frozenLeading;

  /// The table, or whatever stands in for it while it loads or has nothing.
  final Widget table;

  /// Shown with the table rather than with the heading, so it stays in view
  /// in landscape: the live-scores warning.
  final Widget? banner;

  /// Whether this frame has the page to itself.
  ///
  /// A page of stacked sections sets this false: each section is as tall as
  /// its own table, and they align to the left instead of being centred, so
  /// their rails line up as one column down the page rather than each
  /// section sitting in the middle of its own width.
  final bool fill;

  /// A landscape pane narrower than this keeps the portrait stacking: a rail
  /// would take more of it than the table could spare.
  static const double railNeeds = 560;

  /// How much of the pane the rail asks for, and the bounds it is held to.
  static const double railFraction = 0.28;
  static const double railMinWidth = 180;
  static const double railMaxWidth = 280;

  static double railWidth(double paneWidth) =>
      (paneWidth * railFraction).clamp(railMinWidth, railMaxWidth);

  @override
  State<AppTableFrame> createState() => _AppTableFrameState();
}

class _AppTableFrameState extends State<AppTableFrame> {
  /// Its own, not the table's. Resolving the rails needs the same content
  /// measurement the table makes, and at these row counts a second extraction
  /// costs well under a millisecond -- cheaper than threading one cache
  /// through every page to the table inside it.
  final _measurements = AppTableMeasurementCache();

  /// The band the rows occupy, so the heading can sit on the same rails.
  double _contentWidth(BuildContext context, double width) {
    final body =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final metrics = _measurements.measure(
      columns: widget.columns,
      rows: widget.rows,
      textScaler: MediaQuery.textScalerOf(context),
      headingStyle: body.copyWith(fontWeight: FontWeight.w600),
      cellStyle: body,
      direction: Directionality.of(context),
    );
    final layout = AppTableLayout.resolve(
      metrics: metrics,
      width: width,
      frozenLeading: widget.frozenLeading,
    );
    return layout.contentWidth;
  }

  @override
  Widget build(BuildContext context) {
    final bool portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return LayoutBuilder(
      builder: (context, bounds) {
        final double pane = bounds.maxWidth;
        if (!portrait && pane >= AppTableFrame.railNeeds) {
          final double rail = AppTableFrame.railWidth(pane);
          final double rest = pane - rail;
          // The table keeps its own width rather than spreading across what
          // is left, and the pair is centred together. Left to fill, a narrow
          // table drifted into the middle of the space and read as unrelated
          // to the rail describing it.
          final double content = math.min(
            rest,
            _contentWidth(context, rest - _horizontalPadding * 2) +
                AppTableLayout.scrollbarLane +
                _horizontalPadding * 2,
          );
          const EdgeInsets railPadding = EdgeInsets.fromLTRB(16, 8, 8, 8);
          return Align(
            alignment: widget.fill
                ? AlignmentDirectional.center
                : AlignmentDirectional.centerStart,
            child: SizedBox(
              width: rail + content,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: rail,
                    // A frame that owns the page has a bounded height to
                    // scroll a long description within. A stacked section is
                    // only as tall as its table, so its heading is laid out
                    // at its own height instead.
                    child: widget.fill
                        ? SingleChildScrollView(
                            padding: railPadding,
                            child: widget.heading,
                          )
                        : Padding(padding: railPadding, child: widget.heading),
                  ),
                  Expanded(child: _tableArea()),
                ],
              ),
            ),
          );
        }
        final Widget table = _tableArea();
        return Column(
          mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _railed(context, pane, widget.heading),
            if (widget.fill) Expanded(child: table) else table,
          ],
        );
      },
    );
  }

  Widget _tableArea() {
    final banner = widget.banner;
    if (banner == null) return widget.table;
    return Column(
      children: [
        banner,
        Expanded(child: widget.table),
      ],
    );
  }

  /// Holds the heading to the rails the rows are drawn on. The rows are
  /// centred within the pane less the scrollbar lane, so the heading is too.
  Widget _railed(BuildContext context, double pane, Widget heading) {
    final double available = math.max(
      1.0,
      pane - AppTableLayout.scrollbarLane - _horizontalPadding * 2,
    );
    final double content = _contentWidth(
      context,
      pane - _horizontalPadding * 2,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding,
        8,
        _horizontalPadding + AppTableLayout.scrollbarLane,
        8,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: SizedBox(width: math.min(content, available), child: heading),
      ),
    );
  }

  /// The padding every table page puts around its table.
  static const double _horizontalPadding = 5;
}
