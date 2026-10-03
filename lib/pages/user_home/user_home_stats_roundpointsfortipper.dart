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
    AppColumn.numeric('Total', sortable: true),
    AppColumn.numeric('NRL', sortable: true),
    AppColumn.numeric('AFL', sortable: true),
    AppColumn.numeric('Margins', sortable: true),
    AppColumn.numeric('UPS', sortable: true),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(List<RoundStats> points) {
    final values = <Object?>[
      widget.statsTipper,
      for (final point in points) ...[
        point.roundNumber,
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
            AppCell.text(
              point.roundNumber.toString(),
              leading: const Icon(Icons.arrow_forward, size: 15),
              leadingSize: const Size(15, 15),
            ),
            AppCell.text((point.nrlPoints + point.aflPoints).toString()),
            AppCell.text(point.nrlPoints.toString()),
            AppCell.text(point.aflPoints.toString()),
            AppCell.text(
              (point.aflMarginTips + point.nrlMarginTips).toString(),
            ),
            AppCell.text((point.aflMarginUPS + point.nrlMarginUPS).toString()),
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

  void _sortPoints(int columnIndex, bool ascending) {
    if (sortedPoints == null) return;

    switch (columnIndex) {
      case 0:
        sortedPoints!.sort(
          (a, b) => ascending
              ? a.roundNumber.compareTo(b.roundNumber)
              : b.roundNumber.compareTo(a.roundNumber),
        );
        break;
      case 1:
        sortedPoints!.sort(
          (a, b) => ascending
              ? (a.nrlPoints + a.aflPoints).compareTo(b.nrlPoints + b.aflPoints)
              : (b.nrlPoints + b.aflPoints).compareTo(
                  a.nrlPoints + a.aflPoints,
                ),
        );
        break;
      case 2:
        sortedPoints!.sort(
          (a, b) => ascending
              ? a.nrlPoints.compareTo(b.nrlPoints)
              : b.nrlPoints.compareTo(a.nrlPoints),
        );
        break;
      case 3:
        sortedPoints!.sort(
          (a, b) => ascending
              ? a.aflPoints.compareTo(b.aflPoints)
              : b.aflPoints.compareTo(a.aflPoints),
        );
        break;
      case 4:
        sortedPoints!.sort(
          (a, b) => ascending
              ? (a.aflMarginTips + a.nrlMarginTips).compareTo(
                  b.aflMarginTips + b.nrlMarginTips,
                )
              : (b.aflMarginTips + b.nrlMarginTips).compareTo(
                  a.aflMarginTips + a.nrlMarginTips,
                ),
        );
        break;
      case 5:
        sortedPoints!.sort(
          (a, b) => ascending
              ? (a.aflMarginUPS + a.nrlMarginUPS).compareTo(
                  b.aflMarginUPS + b.nrlMarginUPS,
                )
              : (b.aflMarginUPS + b.nrlMarginUPS).compareTo(
                  a.aflMarginUPS + a.nrlMarginUPS,
                ),
        );
        break;
    }
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
      body: SafeArea(
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
