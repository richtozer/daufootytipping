import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
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
  late AllScoresViewModel scoresViewModel;
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
    scoresViewModel = di<AllScoresViewModel>();
    onSort(0, false);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AllScoresViewModel>.value(
      value: scoresViewModel,
      child: Consumer<AllScoresViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          Orientation orientation = MediaQuery.of(context).orientation;
          return Scaffold(
            floatingActionButton: FloatingActionButton(
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
                              child: Icon(Icons.person,
                                  color: Colors.white, size: 50)),
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
                        return winners.map((winner) => DataRow(
                              cells: [
                                DataCell(
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Icon(Icons.arrow_forward, size: 15),
                                      Text('  ${winner.roundNumber}'),
                                    ],
                                  ),
                                  onTap: () {
                                    onRowTapped(context, winner);
                                  },
                                ),
                                DataCell(
                                  Row(
                                    children: [
                                      avatarPic(winner.tipper),
                                      Flexible(
                                          child: Text(
                                              winner.tipper.name.toString())),
                                    ],
                                  ),
                                  onTap: () {
                                    onRowTapped(context, winner);
                                  },
                                ),
                                DataCell(
                                  Text(winner.total.toString()),
                                  onTap: () {
                                    onRowTapped(context, winner);
                                  },
                                ),
                                DataCell(
                                  Text(winner.nRL.toString()),
                                  onTap: () {
                                    onRowTapped(context, winner);
                                  },
                                ),
                                DataCell(
                                  Text(winner.aFL.toString()),
                                  onTap: () {
                                    onRowTapped(context, winner);
                                  },
                                ),
                                DataCell(
                                  Text(winner.aflMargins.toString()),
                                  onTap: () {
                                    onRowTapped(context, winner);
                                  },
                                ),
                                DataCell(
                                  Text(winner.aflUPS.toString()),
                                  onTap: () {
                                    onRowTapped(context, winner);
                                  },
                                ),
                              ],
                            ));
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

  Widget avatarPic(Tipper tipper) {
    return Hero(
        tag: tipper.dbkey!,
        child: circleAvatarWithFallback(
            imageUrl: tipper.photoURL, text: tipper.name, radius: 15));
  }
}
