import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundWinners extends StatefulWidget {
  //constructor
  StatRoundWinners({super.key});

  @override
  State<StatRoundWinners> createState() => _StatRoundWinnersState();
}

class _StatRoundWinnersState extends State<StatRoundWinners> {
  late ScoresViewModel scoresViewModel;
  bool isAscending = true;
  int? sortColumnIndex = 1;

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
    scoresViewModel =
        ScoresViewModel(di<DAUCompsViewModel>().selectedDAUCompDbKey);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScoresViewModel>(
      create: (context) => scoresViewModel,
      child: Consumer<ScoresViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/teams/daulogo.jpg',
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                      ListTile(
                        title: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                                style: TextStyle(fontWeight: FontWeight.bold),
                                'Round Winners')),
                        leading: const Icon(
                            size: 30, color: Colors.white, Icons.arrow_back),
                        onTap: () {
                          Navigator.pop(context);
                        },
                      ),
                    ],
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
                      rows: List<DataRow>.generate(
                          scoresViewModelConsumer.leaderboard.length,
                          (index) => DataRow(
                                cells: [
                                  DataCell(Text(
                                      overflow: TextOverflow.ellipsis,
                                      scoresViewModelConsumer
                                          .roundWinners[index].name)),
                                  DataCell(Text(scoresViewModelConsumer
                                      .roundWinners[index].roundNumber
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .roundWinners[index].total
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .roundWinners[index].nRL
                                      .toString())),
                                  DataCell(Text(scoresViewModelConsumer
                                      .roundWinners[index].aFL
                                      .toString())),
                                  DataCell(Text((scoresViewModelConsumer
                                              .roundWinners[index].aflMargins +
                                          scoresViewModelConsumer
                                              .roundWinners[index].nrlMargins)
                                      .toString())),
                                  DataCell(Text((scoresViewModelConsumer
                                              .roundWinners[index].aflUPS +
                                          scoresViewModelConsumer
                                              .roundWinners[index].nrlUPS)
                                      .toString())),
                                ],
                              )),
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

  void onSort(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      if (ascending) {
        scoresViewModel.leaderboard.sort((a, b) => a.name.compareTo(b.name));
      } else {
        scoresViewModel.leaderboard.sort((a, b) => b.name.compareTo(a.name));
      }
    }
    if (columnIndex == 1) {
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
