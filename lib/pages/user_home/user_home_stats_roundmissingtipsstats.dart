import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class RoundMissingTipsStats extends StatefulWidget {
  //constructor
  const RoundMissingTipsStats(this.roundNumberToDisplay, {super.key});

  final int roundNumberToDisplay;

  @override
  State<RoundMissingTipsStats> createState() => _RoundMissingTipsStatsState();
}

class _RoundMissingTipsStatsState extends State<RoundMissingTipsStats> {
  late StatsViewModel statsViewModel;
  Map<Tipper, RoundStats> roundLeaderboard = {};

  bool isAscending = false; // Default to descending
  int? sortColumnIndex = 1;

  final List<String> columns = [
    'Name',
    'Tips\nNeeded',
    'NRL',
    'AFL',
  ];

  @override
  void initState() {
    super.initState();

    statsViewModel = di<StatsViewModel>();
    _loadLeaderboard();
  }

  void _loadLeaderboard() {
    roundLeaderboard =
        statsViewModel.getRoundLeaderBoard(widget.roundNumberToDisplay);
    onSort(1, false); // Default to descending
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StatsViewModel>.value(
      value: statsViewModel,
      child: Consumer<StatsViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          return buildScaffold(
            context,
            scoresViewModelConsumer,
            'Round ${widget.roundNumberToDisplay} - missing tips',
            Colors.blue,
          );
        },
      ),
    );
  }

  Widget buildScaffold(
    BuildContext context,
    StatsViewModel scoresViewModelConsumer,
    String name,
    Color color,
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
                    text: name,
                    leadingIconAvatar: const Hero(
                        tag: 'magifyingglass',
                        child: Icon(Icons.search, size: 50)),
                  )
                : Text(name),
            orientation == Orientation.portrait
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                        'Below is a list of any tippers who have not submitted all tips for round ${widget.roundNumberToDisplay}.'),
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
                    fixedLeftColumns:
                        orientation == Orientation.portrait ? 1 : 0,
                    showCheckboxColumn: false,
                    isHorizontalScrollBarVisible: true,
                    isVerticalScrollBarVisible: true,
                    columns: getColumns(columns),
                    rows: roundLeaderboard.entries
                        .where((entry) =>
                            entry.value.nrlTipsOutstanding +
                                entry.value.aflTipsOutstanding >
                            0)
                        .map((MapEntry<Tipper, RoundStats> entry) {
                      return DataRow(
                        color: entry.key ==
                                di<TippersViewModel>().selectedTipper
                            ? WidgetStateProperty.resolveWith(
                                (states) => Theme.of(context).highlightColor)
                            : WidgetStateProperty.resolveWith(
                                (states) => Colors.transparent),
                        cells: [
                          DataCell(Row(
                            children: [
                              avatarPic(entry.key, widget.roundNumberToDisplay),
                              Expanded(
                                child: Text(
                                  softWrap: false,
                                  entry.key.name,
                                  overflow: TextOverflow.fade,
                                ),
                              ),
                            ],
                          )),
                          DataCell(Text((entry.value.nrlTipsOutstanding +
                                  entry.value.aflTipsOutstanding)
                              .toString())),
                          DataCell(
                              Text(entry.value.nrlTipsOutstanding.toString())),
                          DataCell(
                              Text(entry.value.aflTipsOutstanding.toString())),
                        ],
                      );
                    }).toList(),
                  )),
            ),
          ],
        ),
      ),
    );
  }

  void onSort(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      if (ascending) {
        // Sort by tipper.name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) =>
              a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase()));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by tipper.name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) =>
              b.key.name.toLowerCase().compareTo(a.key.name.toLowerCase()));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 1) {
      if (ascending) {
        // Sort by total tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) =>
              (a.value.nrlTipsOutstanding + a.value.aflTipsOutstanding)
                  .compareTo(
                      b.value.nrlTipsOutstanding + b.value.aflTipsOutstanding));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by total tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) =>
              (b.value.nrlTipsOutstanding + b.value.aflTipsOutstanding)
                  .compareTo(
                      a.value.nrlTipsOutstanding + a.value.aflTipsOutstanding));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 2) {
      if (ascending) {
        // Sort by nrl tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) =>
              a.value.nrlTipsOutstanding.compareTo(b.value.nrlTipsOutstanding));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by nrl tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) =>
              b.value.nrlTipsOutstanding.compareTo(a.value.nrlTipsOutstanding));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 3) {
      if (ascending) {
        // Sort by afl tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) =>
              a.value.aflTipsOutstanding.compareTo(b.value.aflTipsOutstanding));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by afl tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) =>
              b.value.aflTipsOutstanding.compareTo(a.value.aflTipsOutstanding));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }

    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            fixedWidth: column == 'Name' ? 175 : 70,
            numeric: column == 'Name' ? false : true,
            label: Text(
              softWrap: false,
              overflow: TextOverflow.fade,
              column,
            ),
            onSort: onSort,
          ))
      .toList();

  Widget avatarPic(Tipper tipper, int round) {
    return Hero(
        tag:
            '$round-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds
        child: circleAvatarWithFallback(
            imageUrl: tipper.photoURL, text: tipper.name, radius: 15));
  }
}
