import 'dart:developer';

import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundgamescoresfortipper.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_under_controls_area.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundPointsForTipper extends StatefulWidget {
  const StatRoundPointsForTipper(this.statsTipper, {super.key});

  final Tipper statsTipper;

  @override
  State<StatRoundPointsForTipper> createState() =>
      _StatRoundPointsForTipperState();
}

class _StatRoundPointsForTipperState extends State<StatRoundPointsForTipper> {
  StatsViewModel? statsViewModel;
  bool isAscending = false;
  int? sortColumnIndex = 0;
  int highestRoundNumber = 0;
  List<RoundStats>? sortedPoints;

  static const columns = [
    AppColumn.numeric('Round', sortable: true),
    // Where the tipper placed among all tippers in the round, 1 being the round
    // winner: the round's own rank, not a place on the season ladder.
    AppColumn.numeric('Round rank', sortable: true, descendingFirst: false),
    AppColumn.numeric('Total', sortable: true),
    AppColumn.numeric('NRL', sortable: true, headingGroup: 'league'),
    AppColumn.numeric('AFL', sortable: true, headingGroup: 'league'),
    AppColumn.numeric('Margins', sortable: true, headingGroup: 'margins'),
    AppColumn.numeric('UPS', sortable: true, headingGroup: 'margins'),
    // The tipper's points added up to and including the round.
    AppColumn.numeric('Season', sortable: true),
    AppColumn.navigation(),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(List<RoundStats> points) {
    final values = <Object?>[
      widget.statsTipper,
      for (final point in points) ...[
        point.roundNumber,
        point.rank,
        point.nrlPoints,
        point.aflPoints,
        point.aflMarginTips,
        point.nrlMarginTips,
        point.aflMarginUPS,
        point.nrlMarginUPS,
      ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    final seasonTotals = _seasonTotals(points);
    _rows = [
      for (final point in points)
        AppRow(
          key: ValueKey(point.roundNumber),
          onTap: () => Navigator.push(
            context,
            appPageRoute(
              (context) => StatRoundGameScoresForTipper(
                widget.statsTipper,
                point.roundNumber,
              ),
            ),
          ),
          cells: [
            AppCell.text(point.roundNumber.toString()),
            AppCell.text(point.rank > 0 ? point.rank.toString() : '-'),
            AppCell.total((point.nrlPoints + point.aflPoints).toString()),
            AppCell.text(point.nrlPoints.toString()),
            AppCell.text(point.aflPoints.toString()),
            AppCell.text(
              (point.aflMarginTips + point.nrlMarginTips).toString(),
            ),
            AppCell.text((point.aflMarginUPS + point.nrlMarginUPS).toString()),
            AppCell.text(seasonTotals[point.roundNumber].toString()),
            AppCell.navigation(),
          ],
        ),
    ];
    return _rows;
  }

  @override
  void initState() {
    super.initState();
    if (di<DAUCompsViewModel>().selectedDAUComp == null) {
      return;
    }
    statsViewModel = di<StatsViewModel>();
    statsViewModel!.addListener(_handlePointsChanged);
    _refreshPoints();
  }

  @override
  void didUpdateWidget(covariant StatRoundPointsForTipper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statsTipper != widget.statsTipper) {
      _refreshPoints();
    }
  }

  @override
  void dispose() {
    statsViewModel?.removeListener(_handlePointsChanged);
    super.dispose();
  }

  void _handlePointsChanged() {
    if (!mounted) return;
    setState(_refreshPoints);
  }

  void _refreshPoints() {
    final selectedComp = di<DAUCompsViewModel>().selectedDAUComp;
    final localStatsViewModel = statsViewModel;
    if (selectedComp == null || localStatsViewModel == null) {
      sortedPoints = const <RoundStats>[];
      return;
    }

    highestRoundNumber = selectedComp.latestsCompletedRoundNumber();
    log(
      'StatRoundPointsForTipper() highest round number is $highestRoundNumber',
    );

    final rawPoints = localStatsViewModel.getTipperRoundPointsForComp(
      widget.statsTipper,
    )..removeWhere((element) => element.roundNumber > highestRoundNumber + 1);

    sortedPoints = List<RoundStats>.from(rawPoints);
    _sortPoints(sortColumnIndex!, isAscending);
  }

  /// Each round's points added to those of the rounds before it, by round
  /// number whatever order the rows are shown in.
  Map<int, int> _seasonTotals(List<RoundStats> points) {
    final inRoundOrder = List<RoundStats>.of(points)
      ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
    var running = 0;
    return {
      for (final point in inRoundOrder)
        point.roundNumber: running += point.nrlPoints + point.aflPoints,
    };
  }

  void _sortPoints(int columnIndex, bool ascending) {
    final points = sortedPoints;
    if (points == null) return;

    final seasonTotals = _seasonTotals(points);
    int value(RoundStats point) => switch (columnIndex) {
      0 => point.roundNumber,
      1 => point.rank,
      2 => point.nrlPoints + point.aflPoints,
      3 => point.nrlPoints,
      4 => point.aflPoints,
      5 => point.aflMarginTips + point.nrlMarginTips,
      6 => point.aflMarginUPS + point.nrlMarginUPS,
      7 => seasonTotals[point.roundNumber] ?? 0,
      _ => 0,
    };
    points.sort(
      (a, b) => ascending
          ? value(a).compareTo(value(b))
          : value(b).compareTo(value(a)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SelectedCompBanner(
      child: buildScaffold(
        context,
        sortedPoints ?? const <RoundStats>[],
        MediaQuery.of(context).size.width > 500,
      ),
    );
  }

  Scaffold buildScaffold(
    BuildContext context,
    List<RoundStats> points,
    bool isLargeScreen,
  ) {
    return Scaffold(
      body: AppUnderControlsArea(
        child: AppTableFrame(
          columns: columns,
          rows: _tableRows(points),
          frozenLeading: 1,
          banner: LiveScoresWarningCard(),
          heading: AppTableHeading(
            leading: avatarPic(widget.statsTipper),
            title: 'Round Points',
            subtitle: widget.statsTipper.name,
            description: 'Tap a row to see tips for that round.',
          ),
          table: Padding(
            padding: const EdgeInsets.all(5.0),
            child: AppTable(
              columns: columns,
              rows: _tableRows(points),
              frozenLeading: 1,
              sort: AppSort(
                column: sortColumnIndex ?? 0,
                ascending: isAscending,
              ),
              onSort: (column, ascending) => onSort(column, ascending, points),
            ),
          ),
        ),
      ),
    );
  }

  void onSort(int columnIndex, bool ascending, List<RoundStats> points) {
    setState(() {
      _sortPoints(columnIndex, ascending);
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  Widget avatarPic(Tipper tipper) {
    return Hero(
      tag: tipper.dbkey!,
      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 30,
      ),
    );
  }
}
