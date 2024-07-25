import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundgamescoresfortipper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundLeaderboard extends StatefulWidget {
  //constructor
  const StatRoundLeaderboard(this.roundNumberToDisplay, {super.key});

  final int roundNumberToDisplay;

  @override
  State<StatRoundLeaderboard> createState() => _StatRoundLeaderboardState();
}

class _StatRoundLeaderboardState extends State<StatRoundLeaderboard> {
  late ScoresViewModel scoresViewModel;
  Map<Tipper, RoundScores> roundLeaderboard = {};

  bool isAscending = true;
  int? sortColumnIndex = 0;

  final List<String> columns = [
    'Name',
    "Rank",
    'Total',
    'NRL',
    'AFL',
    'Margins',
    'UPS'
  ];

  @override
  void initState() {
    super.initState();

    scoresViewModel = di<ScoresViewModel>();

    getConsolidatedScoresForRoundLeaderboard();
    onSort(1, true);
  }

  void getConsolidatedScoresForRoundLeaderboard() {
    for (var tipper in scoresViewModel.allTipperRoundScores.keys) {
      roundLeaderboard[tipper] = scoresViewModel
          .allTipperRoundScores[tipper]![widget.roundNumberToDisplay - 1]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScoresViewModel>.value(
      value: scoresViewModel,
      child: Consumer<ScoresViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          return buildScaffold(
            context,
            scoresViewModelConsumer,
            'Round ${widget.roundNumberToDisplay} Leaderboard',
            Colors.blue,
          );
        },
      ),
    );
  }

  Widget buildScaffold(
    BuildContext context,
    ScoresViewModel scoresViewModelConsumer,
    String name,
    Color color,
  ) {
    Orientation orientation = MediaQuery.of(context).orientation;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'roundleaderboard',
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
                    text: 'Round ${widget.roundNumberToDisplay} Leaderboard',
                    leadingIconAvatar: const Hero(
                        tag: 'one_two_three',
                        child: Icon(Icons.onetwothree, size: 50)),
                  )
                : Text('Round ${widget.roundNumberToDisplay} Leaderboard'),
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
                        .map((MapEntry<Tipper, RoundScores> entry) {
                      return DataRow(
                        color: entry.key ==
                                di<TippersViewModel>().selectedTipper!
                            ? WidgetStateProperty.resolveWith(
                                (states) => Theme.of(context).highlightColor)
                            : WidgetStateProperty.resolveWith(
                                (states) => Colors.transparent),
                        cells: [
                          DataCell(
                              Row(
                                children: [
                                  const Icon(
                                    Icons.arrow_forward,
                                    size: 15,
                                  ),
                                  avatarPic(
                                      entry.key, widget.roundNumberToDisplay),
                                  Expanded(
                                    child: Text(
                                      softWrap: false,
                                      entry.key.name,
                                      overflow: TextOverflow.fade,
                                    ),
                                  ),
                                ],
                              ), onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        StatRoundGameScoresForTipper(entry.key,
                                            widget.roundNumberToDisplay)));
                          }),
                          DataCell(Text(entry.value.rank.toString())),
                          DataCell(Text(
                              (entry.value.aflScore + entry.value.nrlScore)
                                  .toString())),
                          DataCell(Text(entry.value.nrlScore.toString())),
                          DataCell(Text(entry.value.aflScore.toString())),
                          DataCell(Text((entry.value.aflMarginTips +
                                  entry.value.nrlMarginTips)
                              .toString())),
                          DataCell(Text((entry.value.aflMarginUPS +
                                  entry.value.nrlMarginUPS)
                              .toString())),
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
              a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase()));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 1 || columnIndex == 2) {
      if (ascending) {
        // Sort by RoundScores.rank and then by name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) {
            if (a.value.rank == b.value.rank) {
              return a.key.name
                  .toLowerCase()
                  .compareTo(b.key.name.toLowerCase());
            } else {
              return a.value.rank.compareTo(b.value.rank);
            }
          });

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.rank and then by name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) {
            if (a.value.rank == b.value.rank) {
              return a.key.name
                  .toLowerCase()
                  .compareTo(b.key.name.toLowerCase());
            } else {
              return b.value.rank.compareTo(a.value.rank);
            }
          });

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 3) {
      if (ascending) {
        // Sort by RoundScores.nrlScore and then name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) {
            if (a.value.nrlScore == b.value.nrlScore) {
              return a.key.name
                  .toLowerCase()
                  .compareTo(b.key.name.toLowerCase());
            } else {
              return a.value.nrlScore.compareTo(b.value.nrlScore);
            }
          });

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.nrlScore and then name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) {
            if (a.value.nrlScore == b.value.nrlScore) {
              return a.key.name
                  .toLowerCase()
                  .compareTo(b.key.name.toLowerCase());
            } else {
              return b.value.nrlScore.compareTo(a.value.nrlScore);
            }
          });

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 4) {
      if (ascending) {
        // Sort by RoundScores.aflScore
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) => a.value.aflScore.compareTo(b.value.aflScore));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.aflScore
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) => b.value.aflScore.compareTo(a.value.aflScore));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 5) {
      if (ascending) {
        // Sort by RoundScores.aflMarginTips + RoundScores.nrlMarginTips
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) => (a.value.aflMarginTips + a.value.nrlMarginTips)
              .compareTo(b.value.aflMarginTips + b.value.nrlMarginTips));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.aflMarginTips + RoundScores.nrlMarginTips
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) => (b.value.aflMarginTips + b.value.nrlMarginTips)
              .compareTo(a.value.aflMarginTips + a.value.nrlMarginTips));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 6) {
      if (ascending) {
        // Sort by RoundScores.aflMarginUPS + RoundScores.nrlMarginUPS
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) => (a.value.aflMarginUPS + a.value.nrlMarginUPS)
              .compareTo(b.value.aflMarginUPS + b.value.nrlMarginUPS));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.aflMarginUPS + RoundScores.nrlMarginUPS
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) => (b.value.aflMarginUPS + b.value.nrlMarginUPS)
              .compareTo(a.value.aflMarginUPS + a.value.nrlMarginUPS));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 7) {
      if (ascending) {
      } else {}
    }

    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            fixedWidth: column == 'Name'
                ? 150
                : column == '#\nrounds\nwon' || column == 'Margins'
                    ? 75
                    : 55,
            numeric: column == 'Name' ? false : true,
            label: Text(
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
