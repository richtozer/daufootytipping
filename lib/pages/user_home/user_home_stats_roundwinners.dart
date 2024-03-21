import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
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
    //scoresViewModel =
    //    AllScoresViewModel(di<DAUCompsViewModel>().selectedDAUCompDbKey);
    scoresViewModel = di<AllScoresViewModel>();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AllScoresViewModel>.value(
      value: scoresViewModel,
      child: Consumer<AllScoresViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          return Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Icon(Icons.arrow_back),
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HeaderWidget(
                    text: 'Round Winners',
                    leadingIconAvatar: const Hero(
                        tag: 'person',
                        child:
                            Icon(Icons.person, color: Colors.white, size: 50)),
                  ),
                  Expanded(
                      child: Padding(
                    padding: const EdgeInsets.all(5.0),
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
                      fixedLeftColumns: 2,
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
                                      const CircleAvatar(
                                          child: Icon(Icons.arrow_forward,
                                              size: 20)),
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
                                      const CircleAvatar(
                                          radius: 10,
                                          child: Icon(Icons.person, size: 10)),
                                      Text(winner.tipper.name.toString()),
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
    if (columnIndex == 1) {
      if (ascending) {
        scoresViewModel.leaderboard.sort((a, b) =>
            a.tipper.name.toLowerCase().compareTo(b.tipper.name.toLowerCase()));
      } else {
        scoresViewModel.leaderboard.sort((a, b) =>
            b.tipper.name.toLowerCase().compareTo(a.tipper.name.toLowerCase()));
      }
    }
    if (columnIndex == 0) {
      if (ascending) {
        scoresViewModel.leaderboard.sort((a, b) => a.rank.compareTo(b.rank));
      } else {
        scoresViewModel.leaderboard.sort((a, b) => b.rank.compareTo(a.rank));
      }
    }
    if (columnIndex == 2) {
      if (ascending) {
        scoresViewModel.leaderboard.sort((a, b) => a.total.compareTo(b.total));
      } else {
        scoresViewModel.leaderboard.sort((a, b) => b.total.compareTo(a.total));
      }
    }
    if (columnIndex == 3) {
      if (ascending) {
        scoresViewModel.leaderboard.sort((a, b) => a.nRL.compareTo(b.nRL));
      } else {
        scoresViewModel.leaderboard.sort((a, b) => b.nRL.compareTo(a.nRL));
      }
    }
    if (columnIndex == 4) {
      if (ascending) {
        scoresViewModel.leaderboard.sort((a, b) => a.aFL.compareTo(b.aFL));
      } else {
        scoresViewModel.leaderboard.sort((a, b) => b.aFL.compareTo(a.aFL));
      }
    }
    if (columnIndex == 5) {
      if (ascending) {
        scoresViewModel.leaderboard
            .sort((a, b) => a.numRoundsWon.compareTo(b.numRoundsWon));
      } else {
        scoresViewModel.leaderboard
            .sort((a, b) => b.numRoundsWon.compareTo(a.numRoundsWon));
      }
    }
    if (columnIndex == 6) {
      if (ascending) {
        scoresViewModel.leaderboard.sort((a, b) => (a.aflMargins + a.nrlMargins)
            .compareTo(b.aflMargins + b.nrlMargins));
      } else {
        scoresViewModel.leaderboard.sort((a, b) => (b.aflMargins + b.nrlMargins)
            .compareTo(a.aflMargins + a.nrlMargins));
      }
    }
    if (columnIndex == 7) {
      if (ascending) {
        scoresViewModel.leaderboard.sort(
            (a, b) => (a.aflUPS + a.nrlUPS).compareTo(b.aflUPS + b.nrlUPS));
      } else {
        scoresViewModel.leaderboard.sort(
            (a, b) => (b.aflUPS + b.nrlUPS).compareTo(a.aflUPS + a.nrlUPS));
      }
    }

    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            size: column == 'Rank' ? ColumnSize.S : ColumnSize.M,
            numeric: column == 'Name' ? false : true,
            label: Text(
              column,
            ),
            onSort: onSort,
          ))
      .toList();
}
