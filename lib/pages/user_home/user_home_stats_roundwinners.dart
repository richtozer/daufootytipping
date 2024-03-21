import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
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
    if (columnIndex == 0) {
      if (ascending) {
        for (var winners in scoresViewModel.roundWinners.values) {
          winners.sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
        }
      } else {
        for (var winners in scoresViewModel.roundWinners.values) {
          winners.sort((a, b) => b.roundNumber.compareTo(a.roundNumber));
        }
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

  Widget avatarPic(Tipper tipper) {
    return Hero(
        tag: tipper.dbkey!,
        child: circleAvatarWithFallback(
            imageUrl: tipper.photoURL!, radius: 15, text: tipper.name));
  }
}
