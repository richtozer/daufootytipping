import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundleaderboard.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
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
  late StatsViewModel statsViewModel;
  bool isAscending = false;
  int? sortColumnIndex = 0;

  final List<String> columns = [
    "Round",
    'Winner',
    'Total',
    'NRL',
    'AFL',
    'Margins',
    'UPS',
  ];

  @override
  void initState() {
    super.initState();
    statsViewModel = di<StatsViewModel>();
    onSort(0, false);
  }

  @override
  Widget build(BuildContext context) {
    Color currentColor = Colors.transparent;
    Color lastColor = Colors.grey.shade800;
    // if dark mode then set the color to grey.shade800
    // if light mode then set the color to grey.shade200
    if (Theme.of(context).brightness == Brightness.dark) {
      lastColor = Colors.grey.shade800;
      currentColor = Colors.grey.shade600;
    } else {
      lastColor = Colors.grey.shade200;
      currentColor = Colors.grey.shade400;
    }

    int? lastRoundNumber;
    return ChangeNotifierProvider<StatsViewModel>.value(
      value: statsViewModel,
      child: Consumer<StatsViewModel>(
        builder: (context, statsViewModelConsumer, child) {
          Orientation orientation = MediaQuery.of(context).orientation;
          final isDarkMode =
              MediaQuery.of(context).platformBrightness == Brightness.dark;
          final fabBackgroundColor = isDarkMode
              ? const Color(0xFF4E7A36)
              : Colors.lightGreen[200];
          final fabForegroundColor =
              isDarkMode ? Colors.white : Colors.black87;
          return SelectedCompBanner(
            child: Scaffold(
              floatingActionButton: FloatingActionButton.small(
                backgroundColor: fabBackgroundColor,
                foregroundColor: fabForegroundColor,
                heroTag: 'roundWinners',
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Icon(Icons.arrow_back),
              ),
              body: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (orientation == Orientation.portrait)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16.0,
                            8.0,
                            16.0,
                            0.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Hero(
                                    tag: 'person',
                                    child: Icon(Icons.person, size: 50),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Round Winners',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'Round winners grouped by round. Tap a row to see the full round leaderboard.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.grey[600]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      LiveScoresWarningCard(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
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
                            fixedLeftColumns: orientation == Orientation.portrait
                                ? 2
                                : 0,
                            showCheckboxColumn: false,
                            isHorizontalScrollBarVisible: true,
                            isVerticalScrollBarVisible: true,
                            columns: getColumns(columns),
                            rows: statsViewModel.roundWinners.values.expand((
                              winners,
                            ) {
                              return winners.map((winner) {
                                if (lastRoundNumber != winner.roundNumber) {
                                  Color temp = currentColor;
                                  currentColor = lastColor;
                                  lastColor = temp;
                                }
                                lastRoundNumber = winner.roundNumber;

                                return DataRow(
                                  color:
                                      winner.tipper ==
                                          di<TippersViewModel>().selectedTipper
                                      ? WidgetStateProperty.resolveWith(
                                          (states) =>
                                              Theme.of(context).highlightColor,
                                        )
                                      : WidgetStateProperty.resolveWith(
                                          (states) => Colors.transparent,
                                        ),
                                  cells: [
                                    DataCell(
                                      SizedBox.expand(
                                        child: Container(
                                          color: currentColor,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceEvenly,
                                            children: [
                                              const Icon(
                                                Icons.arrow_forward,
                                                size: 15,
                                              ),
                                              Text('  ${winner.roundNumber}'),
                                            ],
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        onRowTapped(context, winner);
                                      },
                                    ),
                                    DataCell(
                                      SizedBox.expand(
                                        child: Container(
                                          color: currentColor,
                                          child: Row(
                                            children: [
                                              avatarPic(
                                                winner.tipper,
                                                winner.roundNumber,
                                              ),
                                              Expanded(
                                                child: Text(
                                                  overflow: TextOverflow.fade,
                                                  winner.tipper.name.toString(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        onRowTapped(context, winner);
                                      },
                                    ),
                                    DataCell(
                                      SizedBox.expand(
                                        child: Container(
                                          alignment: Alignment.centerRight,
                                          color: currentColor,
                                          child: Text(winner.total.toString()),
                                        ),
                                      ),
                                      onTap: () {
                                        onRowTapped(context, winner);
                                      },
                                    ),
                                    DataCell(
                                      SizedBox.expand(
                                        child: Container(
                                          alignment: Alignment.centerRight,
                                          color: currentColor,
                                          child: Text(winner.nRL.toString()),
                                        ),
                                      ),
                                      onTap: () {
                                        onRowTapped(context, winner);
                                      },
                                    ),
                                    DataCell(
                                      SizedBox.expand(
                                        child: Container(
                                          alignment: Alignment.centerRight,
                                          color: currentColor,
                                          child: Text(winner.aFL.toString()),
                                        ),
                                      ),
                                      onTap: () {
                                        onRowTapped(context, winner);
                                      },
                                    ),
                                    DataCell(
                                      SizedBox.expand(
                                        child: Container(
                                          alignment: Alignment.centerRight,
                                          color: currentColor,
                                          child: Text(
                                            (winner.aflMargins + winner.nrlMargins)
                                                .toString(),
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        onRowTapped(context, winner);
                                      },
                                    ),
                                    DataCell(
                                      SizedBox.expand(
                                        child: Container(
                                          alignment: Alignment.centerRight,
                                          color: currentColor,
                                          child: Text(
                                            (winner.aflUPS + winner.nrlUPS)
                                                .toString(),
                                          ),
                                        ),
                                      ),
                                      onTap: () {
                                        onRowTapped(context, winner);
                                      },
                                    ),
                                  ],
                                );
                              });
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
        builder: (context) => StatRoundLeaderboard(winner.roundNumber),
      ),
    );
  }

  void onSort(int columnIndex, bool ascending) {
    switch (columnIndex) {
      case 0:
        // sort by round number
        statsViewModel.sortRoundWinnersByRoundNumber(ascending);
        break;
      case 1:
        // sort by winner
        statsViewModel.sortRoundWinnersByWinner(ascending);
        break;
      case 2:
        // sort by total
        statsViewModel.sortRoundWinnersByTotal(ascending);
        break;
      case 3:
        // sort by nrl
        statsViewModel.sortRoundWinnersByNRL(ascending);
        break;
      case 4:
        // sort by afl
        statsViewModel.sortRoundWinnersByAFL(ascending);
        break;
      case 5:
        // sort by margins
        statsViewModel.sortRoundWinnersByMargins(ascending);
        break;
      case 6:
        // sort by ups
        statsViewModel.sortRoundWinnersByUPS(ascending);
        break;
    }

    setState(() {
      isAscending = ascending;
      sortColumnIndex = columnIndex;
    });
  }

  List<DataColumn> getColumns(List<String> columns) => columns
      .asMap()
      .entries
      .map(
        (entry) {
          int index = entry.key;
          String column = entry.value;
          return DataColumn2(
            fixedWidth: column == 'Winner' ? 150 : 50,
            numeric: column == 'Winner' || column == 'Round' ? false : true,
            label: Text(column),
            onSort: (columnIndex, ascending) => onSort(index, ascending),
          );
        },
      )
      .toList();

  Widget avatarPic(Tipper tipper, int roundNumber) {
    return Hero(
      tag:
          '$roundNumber-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds
      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 15,
      ),
    );
  }
}

class CellContents extends StatelessWidget {
  const CellContents({
    super.key,
    required this.currentColor,
    required this.cellText,
  });

  final Color currentColor;
  final String cellText;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        color: currentColor,
        child: Text(cellText, textAlign: TextAlign.right),
      ),
    );
  }
}
