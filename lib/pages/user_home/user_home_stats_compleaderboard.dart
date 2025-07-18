import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundscoresfortipper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatCompLeaderboard extends StatefulWidget {
  //constructor
  const StatCompLeaderboard({super.key});

  @override
  State<StatCompLeaderboard> createState() => _StatCompLeaderboardState();
}

class _StatCompLeaderboardState extends State<StatCompLeaderboard> {
  late StatsViewModel scoresViewModel;
  bool isAscending = true;
  int? sortColumnIndex = 1;

  final List<String> columns = [
    'Name',
    "Rank",
    'Cng',
    'Total',
    'NRL',
    'AFL',
    '#\nrounds\nwon',
    'Margins',
    'UPS',
  ];

  @override
  void initState() {
    super.initState();
    scoresViewModel = di<StatsViewModel>();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StatsViewModel>.value(
      value: scoresViewModel,
      child: Consumer<StatsViewModel>(
        builder: (context, scoresViewModelConsumer, child) {
          return buildScaffold(
            context,
            scoresViewModelConsumer,
            di<TippersViewModel>().selectedTipper.dbkey ?? '',
            Theme.of(context).highlightColor,
          );
        },
      ),
    );
  }

  Widget buildScaffold(
    BuildContext context,
    StatsViewModel scoresViewModelConsumer,
    String dbkey,
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
                ? const HeaderWidget(
                    text: 'C o m p   L e a d e r b o a r d',
                    leadingIconAvatar: Hero(
                      tag: 'trophy',
                      child: Icon(Icons.emoji_events, size: 40),
                    ),
                  )
                : Container(),
            orientation == Orientation.portrait
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'This is the competition leaderboard up to round ${di<DAUCompsViewModel>().selectedDAUComp!.latestRoundWithGamesCompletedorUnderway() == 0 ? '1' : di<DAUCompsViewModel>().selectedDAUComp!.latestRoundWithGamesCompletedorUnderway()}. Click a Tipper row below to see the breakdown of their round scores. Click column headings to sort.',
                    ),
                  )
                : Container(), // Return an empty container in landscape mode
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
                  fixedLeftColumns: orientation == Orientation.portrait ? 1 : 0,
                  showCheckboxColumn: false,
                  isHorizontalScrollBarVisible: true,
                  isVerticalScrollBarVisible: true,
                  columns: getColumns(columns),
                  rows: List<DataRow>.generate(
                    scoresViewModelConsumer.compLeaderboard.length,
                    (index) => DataRow(
                      color:
                          scoresViewModelConsumer
                                  .compLeaderboard[index]
                                  .tipper
                                  .dbkey ==
                              dbkey
                          ? WidgetStateProperty.resolveWith((states) => color)
                          : WidgetStateProperty.resolveWith(
                              (states) => Colors.transparent,
                            ),
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              const Icon(Icons.arrow_forward, size: 15),
                              avatarPic(
                                scoresViewModelConsumer
                                    .compLeaderboard[index]
                                    .tipper,
                              ),
                              Expanded(
                                child: Text(
                                  softWrap: false,
                                  scoresViewModelConsumer
                                      .compLeaderboard[index]
                                      .tipper
                                      .name,
                                  overflow: TextOverflow.fade,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                        DataCell(
                          Text(
                            scoresViewModelConsumer.compLeaderboard[index].rank
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                        DataCell(
                          _buildRankChangeCell(
                            scoresViewModelConsumer.compLeaderboard[index],
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                        DataCell(
                          Text(
                            scoresViewModelConsumer.compLeaderboard[index].total
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                        DataCell(
                          Text(
                            scoresViewModelConsumer.compLeaderboard[index].nRL
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                        DataCell(
                          Text(
                            scoresViewModelConsumer.compLeaderboard[index].aFL
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                        DataCell(
                          Text(
                            scoresViewModelConsumer
                                .compLeaderboard[index]
                                .numRoundsWon
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                        DataCell(
                          Text(
                            (scoresViewModelConsumer
                                        .compLeaderboard[index]
                                        .aflMargins +
                                    scoresViewModelConsumer
                                        .compLeaderboard[index]
                                        .nrlMargins)
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                        DataCell(
                          Text(
                            (scoresViewModelConsumer
                                        .compLeaderboard[index]
                                        .aflUPS +
                                    scoresViewModelConsumer
                                        .compLeaderboard[index]
                                        .nrlUPS)
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(
                            context,
                            scoresViewModelConsumer,
                            index,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void onTipperTapped(
    BuildContext context,
    StatsViewModel scoresViewModelConsumer,
    int index,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatRoundScoresForTipper(
          scoresViewModelConsumer.compLeaderboard[index].tipper,
        ),
      ),
    );
  }

  void onSort(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => (a.tipper.name.toLowerCase()).compareTo(
            b.tipper.name.toLowerCase(),
          ),
        );
      } else {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => (b.tipper.name.toLowerCase()).compareTo(
            a.tipper.name.toLowerCase(),
          ),
        );
      }
    }
    if (columnIndex == 1) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => a.rank.compareTo(b.rank),
        );
      } else {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => b.rank.compareTo(a.rank),
        );
      }
    }
    if (columnIndex == 2) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => (a.rankChange ?? 0).compareTo(b.rankChange ?? 0),
        );
      } else {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => (b.rankChange ?? 0).compareTo(a.rankChange ?? 0),
        );
      }
    }
    if (columnIndex == 3) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => a.total.compareTo(b.total),
        );
      } else {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => b.total.compareTo(a.total),
        );
      }
    }
    if (columnIndex == 4) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort((a, b) => a.nRL.compareTo(b.nRL));
      } else {
        scoresViewModel.compLeaderboard.sort((a, b) => b.nRL.compareTo(a.nRL));
      }
    }
    if (columnIndex == 5) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort((a, b) => a.aFL.compareTo(b.aFL));
      } else {
        scoresViewModel.compLeaderboard.sort((a, b) => b.aFL.compareTo(a.aFL));
      }
    }
    if (columnIndex == 6) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => a.numRoundsWon.compareTo(b.numRoundsWon),
        );
      } else {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => b.numRoundsWon.compareTo(a.numRoundsWon),
        );
      }
    }
    if (columnIndex == 7) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => (a.aflMargins + a.nrlMargins).compareTo(
            b.aflMargins + b.nrlMargins,
          ),
        );
      } else {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => (b.aflMargins + b.nrlMargins).compareTo(
            a.aflMargins + a.nrlMargins,
          ),
        );
      }
    }
    if (columnIndex == 8) {
      if (ascending) {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => (a.aflUPS + a.nrlUPS).compareTo(b.aflUPS + b.nrlUPS),
        );
      } else {
        scoresViewModel.compLeaderboard.sort(
          (a, b) => (b.aflUPS + b.nrlUPS).compareTo(a.aflUPS + a.nrlUPS),
        );
      }
    }

    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns) =>
      columns.map((String column) {
        if (column == 'Name') {
          return DataColumn2(
            fixedWidth: 140,
            numeric: false,
            label: Text(column),
            onSort: onSort,
          );
        } else if (column == 'Cng') {
          return DataColumn2(
            fixedWidth: 45,
            numeric: true,
            label: Text(column),
            onSort: onSort,
          );
        } else if (column == 'Rank') {
          return DataColumn2(
            fixedWidth: 50,
            numeric: true,
            label: Text(column),
            onSort: onSort,
          );
        } else {
          return DataColumn2(
            fixedWidth: 50,
            numeric: true,
            label: Text(column),
            onSort: onSort,
          );
        }
      }).toList();

  Widget _buildRankChangeCell(dynamic leaderboardEntry) {
    if (leaderboardEntry.previousRank == null ||
        leaderboardEntry.rankChange == null) {
      return const Text('-');
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        //Text('${leaderboardEntry.previousRank}'),
        //const SizedBox(width: 2),
        leaderboardEntry.rankChange > 0
            ? const Icon(color: Colors.green, Icons.arrow_upward, size: 16)
            : leaderboardEntry.rankChange < 0
            ? const Icon(color: Colors.red, Icons.arrow_downward, size: 16)
            : const Icon(color: Colors.green, Icons.sync_alt, size: 16),
        //const SizedBox(width: 2),
        Text('${leaderboardEntry.rankChange.abs()}'),
      ],
    );
  }

  Widget avatarPic(Tipper tipper) {
    return Hero(
      tag: tipper.dbkey!,
      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 15,
      ),
    );
  }
}
