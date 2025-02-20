import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundleaderboard.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundWinners extends StatefulWidget {
  //constructor
  const StatRoundWinners({super.key});

  @override
  State<StatRoundWinners> createState() => _StatRoundWinnersState();
}

class _StatRoundWinnersState extends State<StatRoundWinners> {
  late StatsViewModel scoresViewModel;
  bool isAscending = false;
  int? sortColumnIndex = 0;

  final List<String> columns = [
    "Round",
    'Winner',
    'Total',
    'NRL',
    'AFL',
    'Margins',
    'UPS'
  ];

  @override
  void initState() {
    super.initState();
    scoresViewModel = di<StatsViewModel>();
    onSort(0, false);
  }

  @override
  Widget build(BuildContext context) {
    Color currentColor = Colors.transparent;
    Color lastColor = Colors.grey.shade800;
    // if dark mode then set the color to grey.shade800
    // if light mode then set the color to grey.shade200
    if (Theme.of(context).brightness == Brightness.dark) {
      lastColor = Colors.grey.shade800;
      currentColor = Colors.grey.shade600;
    } else {
      lastColor = Colors.grey.shade200;
      currentColor = Colors.grey.shade400;
    }

    int? lastRoundNumber;
    return ChangeNotifierProvider<StatsViewModel>.value(
      value: scoresViewModel,
      child: Consumer<StatsViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          Orientation orientation = MediaQuery.of(context).orientation;
          return Scaffold(
            floatingActionButton: FloatingActionButton(
              backgroundColor: Colors.lightGreen[200],
              foregroundColor: Colors.white70,
              heroTag: 'roundWinners',
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
                      ? const HeaderWidget(
                          text: 'Round Winners',
                          leadingIconAvatar: Hero(
                              tag: 'person',
                              child: Icon(Icons.person, size: 40)),
                        )
                      : const Text('Round Winners'),
                  Expanded(
                      child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: DataTable2(
                      border: TableBorder.all(
                        width: 1.0,
                        color: Colors.grey.shade300,
                      ),
                      //dividerThickness: 0,
                      sortColumnIndex: sortColumnIndex,
                      sortAscending: isAscending,
                      columnSpacing: 0,
                      horizontalMargin: 0,
                      minWidth: 600,
                      fixedTopRows: 1,
                      fixedLeftColumns:
                          orientation == Orientation.portrait ? 2 : 0,
                      showCheckboxColumn: false,
                      isHorizontalScrollBarVisible: true,
                      isVerticalScrollBarVisible: true,
                      columns: getColumns(columns),
                      rows:
                          scoresViewModel.roundWinners.values.expand((winners) {
                        return winners.map((winner) {
                          // Check if the round number has changed
                          if (lastRoundNumber != winner.roundNumber) {
                            // Swap the colors
                            Color temp = currentColor;
                            currentColor = lastColor;
                            lastColor = temp;
                          }
                          lastRoundNumber = winner.roundNumber;

                          return DataRow(
                            color: winner.tipper ==
                                    di<TippersViewModel>().selectedTipper!
                                ? WidgetStateProperty.resolveWith((states) =>
                                    Theme.of(context).highlightColor)
                                : WidgetStateProperty.resolveWith(
                                    (states) => Colors.transparent),
                            cells: [
                              DataCell(
                                SizedBox.expand(
                                  child: Container(
                                    color: currentColor,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        const Icon(Icons.arrow_forward,
                                            size: 15),
                                        Text('  ${winner.roundNumber}'),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  onRowTapped(context, winner);
                                },
                              ),
                              DataCell(
                                SizedBox.expand(
                                  child: Container(
                                    color: currentColor,
                                    child: Row(
                                      children: [
                                        avatarPic(
                                            winner.tipper, winner.roundNumber),
                                        Expanded(
                                          child: Text(
                                              overflow: TextOverflow.fade,
                                              winner.tipper.name.toString()),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  onRowTapped(context, winner);
                                },
                              ),
                              DataCell(
                                SizedBox.expand(
                                  child: Container(
                                    alignment: Alignment.centerRight,
                                    color: currentColor,
                                    child: Text(winner.total.toString()),
                                  ),
                                ),
                                onTap: () {
                                  onRowTapped(context, winner);
                                },
                              ),
                              DataCell(
                                SizedBox.expand(
                                  child: Container(
                                    alignment: Alignment.centerRight,
                                    color: currentColor,
                                    child: Text(winner.nRL.toString()),
                                  ),
                                ),
                                onTap: () {
                                  onRowTapped(context, winner);
                                },
                              ),
                              DataCell(
                                SizedBox.expand(
                                  child: Container(
                                    alignment: Alignment.centerRight,
                                    color: currentColor,
                                    child: Text(winner.aFL.toString()),
                                  ),
                                ),
                                onTap: () {
                                  onRowTapped(context, winner);
                                },
                              ),
                              DataCell(
                                SizedBox.expand(
                                  child: Container(
                                    alignment: Alignment.centerRight,
                                    color: currentColor,
                                    child: Text(
                                        (winner.aflMargins + winner.nrlMargins)
                                            .toString()),
                                  ),
                                ),
                                onTap: () {
                                  onRowTapped(context, winner);
                                },
                              ),
                              DataCell(
                                SizedBox.expand(
                                  child: Container(
                                    alignment: Alignment.centerRight,
                                    color: currentColor,
                                    child: Text((winner.aflUPS + winner.nrlUPS)
                                        .toString()),
                                  ),
                                ),
                                onTap: () {
                                  onRowTapped(context, winner);
                                },
                              ),
                            ],
                          );
                        });
                      }).toList(),
                    ),
                  ))
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void onRowTapped(BuildContext context, RoundWinnerEntry winner) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => StatRoundLeaderboard(winner.roundNumber)));
  }

  void onSort(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      // sort by round number
      scoresViewModel.sortRoundWinnersByRoundNumber(ascending);
      setState(() {
        isAscending = ascending;
        sortColumnIndex = columnIndex;
      });
    }
    if (columnIndex == 1) {
      // sort by winner
      scoresViewModel.sortRoundWinnersByWinner(ascending);
      setState(() {
        isAscending = ascending;
        sortColumnIndex = columnIndex;
      });
    }

    if (columnIndex == 2) {
      // sort by total
      scoresViewModel.sortRoundWinnersByTotal(ascending);
      setState(() {
        isAscending = ascending;
        sortColumnIndex = columnIndex;
      });
    }
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            fixedWidth: column == 'Winner' ? 150 : 60,
            numeric: column == 'Winner' || column == 'Round' ? false : true,
            label: Text(
              column,
            ),
            onSort: onSort,
          ))
      .toList();

  Widget avatarPic(Tipper tipper, int roundNumber) {
    return Hero(
        tag:
            '$roundNumber-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds
        child: circleAvatarWithFallback(
            imageUrl: tipper.photoURL, text: tipper.name, radius: 15));
  }
}

class CellContents extends StatelessWidget {
  const CellContents({
    super.key,
    required this.currentColor,
    required this.cellText,
  });

  final Color currentColor;
  final String cellText;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
        child: Container(
            color: currentColor,
            child: Text(
              cellText,
              textAlign: TextAlign.right,
            )));
  }
}
