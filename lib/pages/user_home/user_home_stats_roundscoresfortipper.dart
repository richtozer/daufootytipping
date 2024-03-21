import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundScoresForTipper extends StatefulWidget {
  const StatRoundScoresForTipper(this.statsTipper, {super.key});

  final Tipper statsTipper;

  @override
  State<StatRoundScoresForTipper> createState() =>
      _StatRoundScoresForTipperState();
}

class _StatRoundScoresForTipperState extends State<StatRoundScoresForTipper> {
  late AllScoresViewModel scoresViewModel;
  bool isAscending = true;
  int? sortColumnIndex = 1;
  int initialRound = 1;

  final List<String> columns = [
    'Round',
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
          return buildScaffold(context, scoresViewModelConsumer,
              MediaQuery.of(context).size.width > 500);
        },
      ),
    );
  }

  Scaffold buildScaffold(BuildContext context,
      AllScoresViewModel scoresViewModelConsumer, bool isLargeScreen) {
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
                text: '${widget.statsTipper.name} - Round scores',
                leadingIconAvatar: avatarPic(widget.statsTipper)),
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
                    fixedLeftColumns: isLargeScreen ? 1 : 0,
                    showCheckboxColumn: false,
                    isHorizontalScrollBarVisible: true,
                    isVerticalScrollBarVisible: true,
                    columns: getColumns(columns),
                    rows: List<DataRow>.generate(
                            scoresViewModelConsumer
                                .getTipperRoundScoresForComp(widget.statsTipper)
                                .length,
                            (index) =>
                                buildDataRow(scoresViewModelConsumer, index))
                        .reversed
                        .toList(),
                  )),
            ),
          ],
        ),
      ),
    );
  }

  DataRow buildDataRow(AllScoresViewModel scoresViewModelConsumer, int index) {
    var scores = scoresViewModelConsumer
        .getTipperRoundScoresForComp(widget.statsTipper)[index];
    return DataRow(
      cells: [
        DataCell(Text((index + 1).toString())),
        DataCell(Text((scores.nrlScore + scores.aflScore).toString())),
        DataCell(Text(scores.nrlScore.toString())),
        DataCell(Text(scores.aflScore.toString())),
        DataCell(
            Text((scores.aflMarginTips + scores.nrlMarginTips).toString())),
        DataCell(Text((scores.aflMarginUPS + scores.nrlMarginUPS).toString())),
      ],
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
      child: CircleAvatar(
        radius: 30,
        backgroundImage: tipper.photoURL != ''
            ? CachedNetworkImageProvider(tipper.photoURL!)
            : null,
      ),
    );
  }
}
