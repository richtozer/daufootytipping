import 'dart:developer';

import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundgamescoresfortipper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundScoresForTipper extends StatefulWidget {
  const StatRoundScoresForTipper(this.statsTipper, {super.key});

  final Tipper statsTipper;

  @override
  State<StatRoundScoresForTipper> createState() =>
      _StatRoundScoresForTipperState();
}

class _StatRoundScoresForTipperState extends State<StatRoundScoresForTipper> {
  late StatsViewModel scoresViewModel;
  bool isAscending = false;
  int? sortColumnIndex = 0;
  int highestRoundNumber = 0;
  List<RoundStats>? sortedScores;

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
    // is selected daucomp is not null then get the scores model
    if (di<DAUCompsViewModel>().selectedDAUComp != null) {
      scoresViewModel = di<StatsViewModel>();
    }

    // get the highest round number will RoundState.allGamesEnded
    // and store that number
    highestRoundNumber = di<DAUCompsViewModel>().selectedDAUComp!
        .latestsCompletedRoundNumber();
    log(
      'StatRoundScoresForTipper() highest round number is $highestRoundNumber',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StatsViewModel>.value(
      value: scoresViewModel,
      child: Consumer<StatsViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          // get scores for the selected tipper
          List<RoundStats> rawScores = scoresViewModelConsumer
              .getTipperRoundScoresForComp(widget.statsTipper);
          //do not display scores for rounds higher than the highest round number
          rawScores.removeWhere(
            (element) => element.roundNumber > highestRoundNumber + 1,
          );

          // If sortedScores is null or data has changed, initialize with default sort
          if (sortedScores == null ||
              sortedScores!.length != rawScores.length) {
            sortedScores = List.from(rawScores);
            sortedScores!.sort(
              (a, b) => b.roundNumber.compareTo(a.roundNumber),
            ); // Initial sort - descending by round number
          }

          return buildScaffold(
            context,
            sortedScores!,
            MediaQuery.of(context).size.width > 500,
          );
        },
      ),
    );
  }

  Scaffold buildScaffold(
    BuildContext context,
    List<RoundStats> scores,
    bool isLargeScreen,
  ) {
    Orientation orientation = MediaQuery.of(context).orientation;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.lightGreen[200],
        foregroundColor: Colors.white70,
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.arrow_back),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            orientation == Orientation.portrait
                ? HeaderWidget(
                    text: 'Round scores\n${widget.statsTipper.name}',
                    leadingIconAvatar: avatarPic(widget.statsTipper),
                  )
                : Text('Round scores\n${widget.statsTipper.name}'),
            orientation == Orientation.portrait
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Click a row to see ${widget.statsTipper.name}\'s tips for that round.',
                    ),
                  )
                : Container(),
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
                  columns: getColumns(columns, scores),
                  rows: List<DataRow>.generate(
                    scores.length,
                    (index) => buildDataRow(scores, index),
                  ).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow buildDataRow(List<RoundStats> scores, int index) {
    var score = scores[index];
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              const Icon(Icons.arrow_forward, size: 15),
              Text((score.roundNumber).toString()),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  score.roundNumber,
                ),
              ),
            );
          },
        ),
        DataCell(
          Text((score.nrlScore + score.aflScore).toString()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  score.roundNumber,
                ),
              ),
            );
          },
        ),
        DataCell(
          Text(score.nrlScore.toString()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  score.roundNumber,
                ),
              ),
            );
          },
        ),
        DataCell(
          Text(score.aflScore.toString()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  score.roundNumber,
                ),
              ),
            );
          },
        ),
        DataCell(Text((score.aflMarginTips + score.nrlMarginTips).toString())),
        DataCell(
          Text((score.aflMarginUPS + score.nrlMarginUPS).toString()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatRoundGameScoresForTipper(
                  widget.statsTipper,
                  score.roundNumber,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void onSort(int columnIndex, bool ascending, List<RoundStats> scores) {
    if (sortedScores == null) return;

    switch (columnIndex) {
      case 0:
        sortedScores!.sort(
          (a, b) => ascending
              ? a.roundNumber.compareTo(b.roundNumber)
              : b.roundNumber.compareTo(a.roundNumber),
        );
        break;
      case 1:
        sortedScores!.sort(
          (a, b) => ascending
              ? (a.nrlScore + a.aflScore).compareTo(b.nrlScore + b.aflScore)
              : (b.nrlScore + b.aflScore).compareTo(a.nrlScore + a.aflScore),
        );
        break;
      case 2:
        sortedScores!.sort(
          (a, b) => ascending
              ? a.nrlScore.compareTo(b.nrlScore)
              : b.nrlScore.compareTo(a.nrlScore),
        );
        break;
      case 3:
        sortedScores!.sort(
          (a, b) => ascending
              ? a.aflScore.compareTo(b.aflScore)
              : b.aflScore.compareTo(a.aflScore),
        );
        break;
      case 4:
        sortedScores!.sort(
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
        sortedScores!.sort(
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

    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns, List<RoundStats> scores) =>
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
          onSort: (columnIndex, ascending) => onSort(index, ascending, scores),
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
