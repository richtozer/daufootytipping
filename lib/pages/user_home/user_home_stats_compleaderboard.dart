import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
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
  late AllScoresViewModel scoresViewModel;
  bool isAscending = true;
  int? sortColumnIndex = 1;

  final List<String> columns = [
    'Name',
    "Rank",
    'Total',
    'NRL',
    'AFL',
    '#\nrounds\nwon',
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
          return buildScaffold(
              context,
              scoresViewModelConsumer,
              di<TippersViewModel>().selectedTipper!.name,
              Theme.of(context).highlightColor);
        },
      ),
    );
  }

  Widget buildScaffold(
    BuildContext context,
    AllScoresViewModel scoresViewModelConsumer,
    String name,
    Color color,
  ) {
    Orientation orientation = MediaQuery.of(context).orientation;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        //heroTag: 'compLeaderboard',
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
                      child: Icon(Icons.emoji_events,
                          color: Colors.white, size: 50),
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
                    fixedLeftColumns:
                        orientation == Orientation.portrait ? 1 : 0,
                    showCheckboxColumn: false,
                    isHorizontalScrollBarVisible: true,
                    isVerticalScrollBarVisible: true,
                    columns: getColumns(columns),
                    rows: List<DataRow>.generate(
                        scoresViewModelConsumer.leaderboard.length,
                        (index) => DataRow(
                              color: scoresViewModelConsumer
                                          .leaderboard[index].tipper.name ==
                                      name
                                  ? MaterialStateProperty.resolveWith(
                                      (states) => color)
                                  : MaterialStateProperty.resolveWith(
                                      (states) => Colors.transparent),
                              cells: [
                                DataCell(
                                    Row(
                                      children: [
                                        const Icon(Icons.arrow_forward,
                                            size: 15),
                                        avatarPic(scoresViewModelConsumer
                                            .leaderboard[index].tipper),
                                        Expanded(
                                          child: Text(
                                            scoresViewModelConsumer
                                                .leaderboard[index].tipper.name,
                                            overflow: TextOverflow.fade,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () => onTipperTapped(context,
                                        scoresViewModelConsumer, index)),
                                DataCell(
                                    Text(scoresViewModelConsumer
                                        .leaderboard[index].rank
                                        .toString()),
                                    onTap: () => onTipperTapped(context,
                                        scoresViewModelConsumer, index)),
                                DataCell(
                                    Text(scoresViewModelConsumer
                                        .leaderboard[index].total
                                        .toString()),
                                    onTap: () => onTipperTapped(context,
                                        scoresViewModelConsumer, index)),
                                DataCell(
                                    Text(scoresViewModelConsumer
                                        .leaderboard[index].nRL
                                        .toString()),
                                    onTap: () => onTipperTapped(context,
                                        scoresViewModelConsumer, index)),
                                DataCell(
                                    Text(scoresViewModelConsumer
                                        .leaderboard[index].aFL
                                        .toString()),
                                    onTap: () => onTipperTapped(context,
                                        scoresViewModelConsumer, index)),
                                DataCell(
                                    Text(scoresViewModelConsumer
                                        .leaderboard[index].numRoundsWon
                                        .toString()),
                                    onTap: () => onTipperTapped(context,
                                        scoresViewModelConsumer, index)),
                                DataCell(
                                    Text((scoresViewModelConsumer
                                                .leaderboard[index].aflMargins +
                                            scoresViewModelConsumer
                                                .leaderboard[index].nrlMargins)
                                        .toString()),
                                    onTap: () => onTipperTapped(context,
                                        scoresViewModelConsumer, index)),
                                DataCell(
                                    Text((scoresViewModelConsumer
                                                .leaderboard[index].aflUPS +
                                            scoresViewModelConsumer
                                                .leaderboard[index].nrlUPS)
                                        .toString()),
                                    onTap: () => onTipperTapped(context,
                                        scoresViewModelConsumer, index)),
                              ],
                            )),
                  )),
            ),
          ],
        ),
      ),
    );
  }

  void onTipperTapped(BuildContext context,
      AllScoresViewModel scoresViewModelConsumer, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => StatRoundScoresForTipper(
              scoresViewModelConsumer.leaderboard[index].tipper)),
    );
  }

  void onSort(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      if (ascending) {
        scoresViewModel.leaderboard.sort((a, b) =>
            a.tipper.name.toLowerCase().compareTo(b.tipper.name.toLowerCase()));
      } else {
        scoresViewModel.leaderboard.sort((a, b) =>
            b.tipper.name.toLowerCase().compareTo(a.tipper.name.toLowerCase()));
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

  Widget avatarPic(Tipper tipper) {
    return Hero(
        tag: tipper.dbkey!,
        child: circleAvatarWithFallback(
            imageUrl: tipper.photoURL, text: tipper.name, radius: 15));
  }
}
