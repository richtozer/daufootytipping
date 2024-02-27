import 'package:data_table_2/data_table_2.dart';
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
  late ScoresViewModel scoresViewModel;

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
    scoresViewModel =
        ScoresViewModel(di<DAUCompsViewModel>().selectedDAUCompDbKey);
    super.initState();
  }

  //late Future<void> leaderBoardFuture;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScoresViewModel>(
      create: (context) => scoresViewModel,
      child: Consumer<ScoresViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
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
                        scoresViewModelConsumer.leaderboard.length,
                        (index) => DataRow(
                                cells: [
                                  DataCell(Text(scoresViewModelConsumer
                                      .leaderboard[index].rank
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .leaderboard[index].name)),
                                  DataCell(Text(scoresViewModelConsumer
                                      .leaderboard[index].total
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .leaderboard[index].nRL
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .leaderboard[index].aFL
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .leaderboard[index].numRoundsWon
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .leaderboard[index].aflMargins
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .leaderboard[index].aflUPS
                                      .toString())),
                                ],
                                onSelectChanged: (bool? selected) {
                                  if (selected!) {
                                    print(
                                        'Selected ${scoresViewModelConsumer.leaderboard[index].name}');
                                  }
                                })),
                  )));
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
