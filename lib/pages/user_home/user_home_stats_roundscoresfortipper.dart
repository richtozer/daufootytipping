import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
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
  late ScoresViewModel scoresViewModel;
  bool isAscending = false;
  int? sortColumnIndex = 0;

  final List<String> columns = [
    'Round',
    'Total',
    'NRL',
    'AFL',
    'Margins',
    'UPS'
  ];

  List<RoundScores> sortedScores = [];

  @override
  void initState() {
    super.initState();
    scoresViewModel = di<ScoresViewModel>();
  }

  @override
  Widget build(BuildContext context) {
    return FutureProvider<List<RoundScores>>(
      initialData: const [],
      create: (context) async {
        var scores = scoresViewModel
            .getTipperRoundScoresForComp(widget.statsTipper);
        scores.sort(
            (a, b) => b.roundNumber.compareTo(a.roundNumber)); // Initial sort
        return scores;
      },
      child: Consumer<List<RoundScores>>(
        builder: (context, scores, child) {
          sortedScores = scores;
          return buildScaffold(
              context, scores, MediaQuery.of(context).size.width > 500);
        },
      ),
    );
  }

  Scaffold buildScaffold(
      BuildContext context, List<RoundScores> scores, bool isLargeScreen) {
    Orientation orientation = MediaQuery.of(context).orientation;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'roundscoresfortipper',
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
                    leadingIconAvatar: avatarPic(widget.statsTipper))
                : Text('Round scores\n${widget.statsTipper.name}'),
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
                    fixedLeftColumns:
                        orientation == Orientation.portrait ? 1 : 0,
                    showCheckboxColumn: false,
                    isHorizontalScrollBarVisible: true,
                    isVerticalScrollBarVisible: true,
                    columns: getColumns(columns),
                    rows: List<DataRow>.generate(sortedScores.length,
                        (index) => buildDataRow(sortedScores, index)).toList(),
                  )),
            ),
          ],
        ),
      ),
    );
  }

  DataRow buildDataRow(List<RoundScores> scores, int index) {
    var score = scores[index];
    return DataRow(
      cells: [
        DataCell(
            Row(
              children: [
                const Icon(Icons.arrow_forward, size: 15),
                Text((score.roundNumber).toString()),
              ],
            ), onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => StatRoundGameScoresForTipper(
                      widget.statsTipper, index + 1)));
        }),
        DataCell(Text((score.nrlScore + score.aflScore).toString()), onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => StatRoundGameScoresForTipper(
                      widget.statsTipper, index + 1)));
        }),
        DataCell(Text(score.nrlScore.toString()), onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => StatRoundGameScoresForTipper(
                      widget.statsTipper, index + 1)));
        }),
        DataCell(Text(score.aflScore.toString()), onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => StatRoundGameScoresForTipper(
                      widget.statsTipper, index + 1)));
        }),
        DataCell(Text((score.aflMarginTips + score.nrlMarginTips).toString())),
        DataCell(Text((score.aflMarginUPS + score.nrlMarginUPS).toString()),
            onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => StatRoundGameScoresForTipper(
                      widget.statsTipper, index + 1)));
        }),
      ],
    );
  }

  void onSort(int columnIndex, bool ascending, List<RoundScores> scores) {
    switch (columnIndex) {
      case 0:
        scores.sort((a, b) => ascending
            ? a.roundNumber.compareTo(b.roundNumber)
            : b.roundNumber.compareTo(a.roundNumber));

        break;
      case 1:
        scores.sort((a, b) => ascending
            ? (a.nrlScore + a.aflScore).compareTo(b.nrlScore + b.aflScore)
            : (b.nrlScore + b.aflScore).compareTo(a.nrlScore + a.aflScore));
        break;
      case 2:
        scores.sort((a, b) => ascending
            ? a.nrlScore.compareTo(b.nrlScore)
            : b.nrlScore.compareTo(a.nrlScore));
        break;
      case 3:
        scores.sort((a, b) => ascending
            ? a.aflScore.compareTo(b.aflScore)
            : b.aflScore.compareTo(a.aflScore));
        break;
      case 4:
        scores.sort((a, b) => ascending
            ? (a.aflMarginTips + a.nrlMarginTips)
                .compareTo(b.aflMarginTips + b.nrlMarginTips)
            : (b.aflMarginTips + b.nrlMarginTips)
                .compareTo(a.aflMarginTips + a.nrlMarginTips));
        break;
      case 5:
        scores.sort((a, b) => ascending
            ? (a.aflMarginUPS + a.nrlMarginUPS)
                .compareTo(b.aflMarginUPS + b.nrlMarginUPS)
            : (b.aflMarginUPS + b.nrlMarginUPS)
                .compareTo(a.aflMarginUPS + a.nrlMarginUPS));
        break;
    }

    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            fixedWidth: column == 'Round'
                ? 75
                : column == 'Total' || column == 'Margins'
                    ? 75
                    : 60,
            numeric: column != 'Round',
            label: Text(
              column,
            ),
            onSort: (columnIndex, ascending) =>
                onSort(columnIndex, ascending, sortedScores),
          ))
      .toList();

  Widget avatarPic(Tipper tipper) {
    return Hero(
        tag: tipper.dbkey!,
        child: circleAvatarWithFallback(
            imageUrl: tipper.photoURL, text: tipper.name, radius: 30));
  }
}
