import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/leaderboard.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatLeaderboard extends StatefulWidget {
  //constructor
  StatLeaderboard({super.key});

  @override
  State<StatLeaderboard> createState() => _StatLeaderboardState();
}

class _StatLeaderboardState extends State<StatLeaderboard> {
  // Future<List<LeaderboardEntry>> leaderBoardFuture =
  ScoresViewModel scoresViewModel =
      ScoresViewModel(di<DAUCompsViewModel>().selectedDAUCompDbKey);

  final List<String> columns = [
    "Rank",
    'Name',
    'Total',
    'NRL',
    'AFL',
    '#\nrounds\nwon',
    'Margins',
    'UPS'
  ];

  @override
  void initState() {
    leaderBoardFuture = scoresViewModel.updateLeaderboardForComp();
    super.initState();
  }

  late Future<List<LeaderboardEntry>> leaderBoardFuture;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScoresViewModel>(
      create: (context) => scoresViewModel,
      child: Consumer<ScoresViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          return FutureBuilder(
              future: leaderBoardFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text(
                          'Error loading leaderboardFuture: ${snapshot.error}'));
                } else if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                } else {
                  //var leaderboard = scoresViewModel.leaderboard;
                  var leaderboard = scoresViewModelConsumer.leaderboard;

                  return Center(
                      child: Padding(
                          padding: const EdgeInsets.all(0.0),
                          child: DataTable2(
                            columnSpacing: 0,
                            horizontalMargin: 0,
                            minWidth: 300,
                            fixedTopRows: 1,
                            fixedLeftColumns: 2,
                            columns: getColumns(columns),
                            rows: List<DataRow>.generate(
                                leaderboard!.length,
                                (index) => DataRow(
                                        cells: [
                                          DataCell(Text(leaderboard[index]
                                              .rank
                                              .toString())),
                                          DataCell(
                                              Text(leaderboard[index].name)),
                                          DataCell(Text(leaderboard[index]
                                              .total
                                              .toString())),
                                          DataCell(Text(leaderboard[index]
                                              .nRL
                                              .toString())),
                                          DataCell(Text(leaderboard[index]
                                              .aFL
                                              .toString())),
                                          DataCell(Text(leaderboard[index]
                                              .numRoundsWon
                                              .toString())),
                                          DataCell(Text(leaderboard[index]
                                              .aflMargins
                                              .toString())),
                                          DataCell(Text(leaderboard[index]
                                              .aflUPS
                                              .toString())),
                                        ],
                                        onSelectChanged: (bool? selected) {
                                          if (selected!) {
                                            print(
                                                'Selected ${leaderboard[index].name}');
                                          }
                                        })),
                          )));
                }
              });
        },
      ),
    );
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .map((String column) => DataColumn2(
            size: column == 'Rank' ? ColumnSize.S : ColumnSize.L,
            numeric: true,
            label: Text(
              column,
            ),
            //onSort: onSort,
          ))
      .toList();
}
