import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundgamescoresfortipper.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class StatRoundLeaderboard extends StatefulWidget {
  //constructor
  const StatRoundLeaderboard(this.roundNumberToDisplay, {super.key});

  final int roundNumberToDisplay;

  @override
  State<StatRoundLeaderboard> createState() => _StatRoundLeaderboardState();
}

class _StatRoundLeaderboardState extends State<StatRoundLeaderboard> {
  late StatsViewModel statsViewModel;
  Map<Tipper, RoundStats> roundLeaderboard = {};

  bool isAscending = true;
  int? sortColumnIndex = 1;

  final List<String> columns = [
    'Name',
    "Rank",
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
    statsViewModel.addListener(_handleLeaderboardChanged);
    _loadLeaderboard();
  }

  @override
  void dispose() {
    statsViewModel.removeListener(_handleLeaderboardChanged);
    super.dispose();
  }

  void _handleLeaderboardChanged() {
    if (!mounted) return;
    setState(_loadLeaderboard);
  }

  void _loadLeaderboard() {
    roundLeaderboard = statsViewModel.getRoundLeaderBoard(
      widget.roundNumberToDisplay,
    );
    _sortLeaderboard(sortColumnIndex ?? 1, isAscending);
  }

  @override
  Widget build(BuildContext context) {
    return SelectedCompBanner(
      child: buildScaffold(
        context,
        'Round ${widget.roundNumberToDisplay} Leaderboard',
        Colors.blue,
      ),
    );
  }

  Widget buildScaffold(
    BuildContext context,
    String name,
    Color color,
  ) {
    Orientation orientation = MediaQuery.of(context).orientation;
    final isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final fabBackgroundColor = isDarkMode
        ? const Color(0xFF4E7A36)
        : Colors.lightGreen[200];
    final fabForegroundColor =
        isDarkMode ? Colors.white : Colors.black87;
    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: fabBackgroundColor,
        foregroundColor: fabForegroundColor,
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
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Hero(
                          tag: 'one_two_three',
                          child: Icon(Icons.onetwothree, size: 50),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Round ${widget.roundNumberToDisplay} Leaderboard',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Tap a row to see the tips for that tipper.',
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
                  rows: roundLeaderboard.entries.map((
                    MapEntry<Tipper, RoundStats> entry,
                  ) {
                    return DataRow(
                      color: entry.key == di<TippersViewModel>().selectedTipper
                          ? WidgetStateProperty.resolveWith(
                              (states) => Theme.of(context).highlightColor,
                            )
                          : WidgetStateProperty.resolveWith(
                              (states) => Colors.transparent,
                            ),
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              const Icon(Icons.arrow_forward, size: 15),
                              avatarPic(entry.key, widget.roundNumberToDisplay),
                              Expanded(
                                child: Text(
                                  softWrap: false,
                                  entry.key.name,
                                  overflow: TextOverflow.fade,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    StatRoundGameScoresForTipper(
                                      entry.key,
                                      widget.roundNumberToDisplay,
                                    ),
                              ),
                            );
                          },
                        ),
                        DataCell(Text(entry.value.rank.toString())),
                        DataCell(
                          Text(
                            (entry.value.aflScore + entry.value.nrlScore)
                                .toString(),
                          ),
                        ),
                        DataCell(Text(entry.value.nrlScore.toString())),
                        DataCell(Text(entry.value.aflScore.toString())),
                        DataCell(
                          Text(
                            (entry.value.aflMarginTips +
                                    entry.value.nrlMarginTips)
                                .toString(),
                          ),
                        ),
                        DataCell(
                          Text(
                            (entry.value.aflMarginUPS +
                                    entry.value.nrlMarginUPS)
                                .toString(),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  void _sortLeaderboard(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      // Sort by tipper.name
      var sortedEntries = roundLeaderboard.entries.toList()
        ..sort(
          (a, b) => ascending
              ? a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase())
              : b.key.name.toLowerCase().compareTo(a.key.name.toLowerCase()),
        );

      roundLeaderboard = Map.fromEntries(sortedEntries);
    }
    if (columnIndex == 1 || columnIndex == 2) {
      if (ascending) {
        // Sort by RoundScores.rank and then by name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) {
            if (a.value.rank == b.value.rank) {
              return a.key.name.toLowerCase().compareTo(
                b.key.name.toLowerCase(),
              );
            } else {
              return a.value.rank.compareTo(b.value.rank);
            }
          });

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.rank and then by name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) {
            if (a.value.rank == b.value.rank) {
              return b.key.name.toLowerCase().compareTo(
                a.key.name.toLowerCase(),
              );
            } else {
              return b.value.rank.compareTo(a.value.rank);
            }
          });

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 3) {
      if (ascending) {
        // Sort by RoundScores.nrlScore and then name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) {
            if (a.value.nrlScore == b.value.nrlScore) {
              return a.key.name.toLowerCase().compareTo(
                b.key.name.toLowerCase(),
              );
            } else {
              return a.value.nrlScore.compareTo(b.value.nrlScore);
            }
          });

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.nrlScore and then name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) {
            if (a.value.nrlScore == b.value.nrlScore) {
              return (a.key.name.toLowerCase()).compareTo(
                b.key.name.toLowerCase(),
              );
            } else {
              return b.value.nrlScore.compareTo(a.value.nrlScore);
            }
          });

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 4) {
      if (ascending) {
        // Sort by RoundScores.aflScore
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) => a.value.aflScore.compareTo(b.value.aflScore));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.aflScore
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort((a, b) => b.value.aflScore.compareTo(a.value.aflScore));

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 5) {
      if (ascending) {
        // Sort by RoundScores.aflMarginTips + RoundScores.nrlMarginTips
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => (a.value.aflMarginTips + a.value.nrlMarginTips).compareTo(
              b.value.aflMarginTips + b.value.nrlMarginTips,
            ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.aflMarginTips + RoundScores.nrlMarginTips
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => (b.value.aflMarginTips + b.value.nrlMarginTips).compareTo(
              a.value.aflMarginTips + a.value.nrlMarginTips,
            ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 6) {
      if (ascending) {
        // Sort by RoundScores.aflMarginUPS + RoundScores.nrlMarginUPS
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => (a.value.aflMarginUPS + a.value.nrlMarginUPS).compareTo(
              b.value.aflMarginUPS + b.value.nrlMarginUPS,
            ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by RoundScores.aflMarginUPS + RoundScores.nrlMarginUPS
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => (b.value.aflMarginUPS + b.value.nrlMarginUPS).compareTo(
              a.value.aflMarginUPS + a.value.nrlMarginUPS,
            ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }

  }

  void onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortLeaderboard(columnIndex, ascending);
      sortColumnIndex = columnIndex;
      isAscending = ascending;
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
            fixedWidth: column == 'Name'
                ? 150
                : column == '#\nrounds\nwon' || column == 'Margins'
                ? 75
                : 55,
            numeric: column == 'Name' ? false : true,
            label: Text(column),
            onSort: (columnIndex, ascending) => onSort(index, ascending),
          );
        },
      )
      .toList();

  Widget avatarPic(Tipper tipper, int round) {
    return Hero(
      tag:
          '$round-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds
      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 15,
      ),
    );
  }
}
