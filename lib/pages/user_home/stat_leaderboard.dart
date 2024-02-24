import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/leaderboard.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class StatLeaderboard extends WatchingWidget {
  //constructor
  StatLeaderboard({super.key});

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

  @override
  Widget build(BuildContext context) {
    final leaderboard = watchFuture(
        (ScoresViewModel scoresViewModel) =>
            scoresViewModel.getLeaderboardForComp(),
        initialValue: [
          LeaderboardEntry(
              rank: 0,
              name: '',
              total: 0,
              nRL: 0,
              aFL: 0,
              numRoundsWon: 0,
              aflMargins: 0,
              aflUPS: 0,
              nrlMargins: 0,
              nrlUPS: 0)
        ]);
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
            leaderboard.data!.length,
            (index) => DataRow(
                    cells: [
                      DataCell(Text(leaderboard.data![index].rank.toString())),
                      DataCell(Text(leaderboard.data![index].name)),
                      DataCell(Text(leaderboard.data![index].total.toString())),
                      DataCell(Text(leaderboard.data![index].nRL.toString())),
                      DataCell(Text(leaderboard.data![index].aFL.toString())),
                      DataCell(Text(
                          leaderboard.data![index].numRoundsWon.toString())),
                      DataCell(
                          Text(leaderboard.data![index].aflMargins.toString())),
                      DataCell(
                          Text(leaderboard.data![index].aflUPS.toString())),
                    ],
                    onSelectChanged: (bool? selected) {
                      if (selected!) {
                        print('Selected ${leaderboard.data![index].name}');
                      }
                    })),
      ),
    ));
  }
}
