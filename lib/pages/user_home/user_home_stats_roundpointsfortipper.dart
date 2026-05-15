import 'dart:developer';

import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundgamescoresfortipper.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
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

  final List<String> columns = [
    'Round',
    'Total',
    'NRL',
    'AFL',
    'Margins',
    'UPS',
  ];

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
              : (b.nrlPoints + b.aflPoints).compareTo(a.nrlPoints + a.aflPoints),
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
    Orientation orientation = MediaQuery.of(context).orientation;
    final isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final fabBackgroundColor = isDarkMode
        ? const Color(0xFF4E7A36)
        : Colors.lightGreen[200];
    final fabForegroundColor =
        isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: fabBackgroundColor,
        foregroundColor: fabForegroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.arrow_back),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
            if (orientation == Orientation.portrait)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        avatarPic(widget.statsTipper),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Round Points',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  widget.statsTipper.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: Colors.grey[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Tap a row to see tips for that round.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            LiveScoresWarningCard(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(5.0),
                child: DataTable2(
                  border: TableBorder.all(
                    width: 1.0,
                    color: Colors.grey.shade300,
                  ),
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: isAscending,
                  columnSpacing: 0,
                  horizontalMargin: 0,
                  minWidth: 600,
                  fixedTopRows: 1,
                  fixedLeftColumns: orientation == Orientation.portrait ? 1 : 0,
                  showCheckboxColumn: false,
                  isHorizontalScrollBarVisible: true,
                  isVerticalScrollBarVisible: true,
                  columns: getColumns(columns, points),
                  rows: List<DataRow>.generate(
                    points.length,
                    (index) => buildDataRow(points, index),
                  ).toList(),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  DataRow buildDataRow(List<RoundStats> points, int index) {
    final roundPoints = points[index];
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              const Icon(Icons.arrow_forward, size: 15),
              Text((roundPoints.roundNumber).toString()),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  roundPoints.roundNumber,
                ),
              ),
            );
          },
        ),
        DataCell(
          Text((roundPoints.nrlPoints + roundPoints.aflPoints).toString()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  roundPoints.roundNumber,
                ),
              ),
            );
          },
        ),
        DataCell(
          Text(roundPoints.nrlPoints.toString()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  roundPoints.roundNumber,
                ),
              ),
            );
          },
        ),
        DataCell(
          Text(roundPoints.aflPoints.toString()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  roundPoints.roundNumber,
                ),
              ),
            );
          },
        ),
        DataCell(
          Text((roundPoints.aflMarginTips + roundPoints.nrlMarginTips).toString()),
        ),
        DataCell(
          Text((roundPoints.aflMarginUPS + roundPoints.nrlMarginUPS).toString()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  roundPoints.roundNumber,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void onSort(int columnIndex, bool ascending, List<RoundStats> points) {
    setState(() {
      _sortPoints(columnIndex, ascending);
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns, List<RoundStats> points) =>
      columns.asMap().entries.map((entry) {
        int index = entry.key;
        String column = entry.value;
        return DataColumn2(
          fixedWidth: column == 'Round'
              ? 75
              : column == 'Total' || column == 'Margins'
              ? 75
              : 60,
          numeric: column != 'Round',
          label: Text(column),
          onSort: (columnIndex, ascending) => onSort(index, ascending, points),
        );
      }).toList();

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
