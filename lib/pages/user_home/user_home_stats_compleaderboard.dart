import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundscoresfortipper.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class StatCompLeaderboard extends StatefulWidget {
  //constructor
  const StatCompLeaderboard({super.key});

  @override
  State<StatCompLeaderboard> createState() => _StatCompLeaderboardState();
}

class _StatCompLeaderboardState extends State<StatCompLeaderboard> {
  late StatsViewModel scoresViewModel;
  List<LeaderboardEntry> sortedLeaderboard = [];
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
    scoresViewModel.addListener(_handleLeaderboardChanged);
    _refreshLeaderboard();
  }

  @override
  void dispose() {
    scoresViewModel.removeListener(_handleLeaderboardChanged);
    super.dispose();
  }

  void _handleLeaderboardChanged() {
    if (!mounted) return;
    setState(_refreshLeaderboard);
  }

  void _refreshLeaderboard() {
    sortedLeaderboard = List<LeaderboardEntry>.from(
      scoresViewModel.compLeaderboard,
    );
    _sortLeaderboard(sortColumnIndex!, isAscending);
  }

  void _sortLeaderboard(int columnIndex, bool ascending) {
    switch (columnIndex) {
      case 0:
        sortedLeaderboard.sort(
          (a, b) => ascending
              ? a.tipper.name.toLowerCase().compareTo(
                  b.tipper.name.toLowerCase(),
                )
              : b.tipper.name.toLowerCase().compareTo(
                  a.tipper.name.toLowerCase(),
                ),
        );
        break;
      case 1:
        sortedLeaderboard.sort(
          (a, b) =>
              ascending ? a.rank.compareTo(b.rank) : b.rank.compareTo(a.rank),
        );
        break;
      case 2:
        sortedLeaderboard.sort(
          (a, b) => ascending
              ? (a.rankChange ?? 0).compareTo(b.rankChange ?? 0)
              : (b.rankChange ?? 0).compareTo(a.rankChange ?? 0),
        );
        break;
      case 3:
        sortedLeaderboard.sort(
          (a, b) => ascending
              ? a.total.compareTo(b.total)
              : b.total.compareTo(a.total),
        );
        break;
      case 4:
        sortedLeaderboard.sort(
          (a, b) => ascending ? a.nRL.compareTo(b.nRL) : b.nRL.compareTo(a.nRL),
        );
        break;
      case 5:
        sortedLeaderboard.sort(
          (a, b) => ascending ? a.aFL.compareTo(b.aFL) : b.aFL.compareTo(a.aFL),
        );
        break;
      case 6:
        sortedLeaderboard.sort(
          (a, b) => ascending
              ? a.numRoundsWon.compareTo(b.numRoundsWon)
              : b.numRoundsWon.compareTo(a.numRoundsWon),
        );
        break;
      case 7:
        sortedLeaderboard.sort(
          (a, b) => ascending
              ? (a.aflMargins + a.nrlMargins).compareTo(
                  b.aflMargins + b.nrlMargins,
                )
              : (b.aflMargins + b.nrlMargins).compareTo(
                  a.aflMargins + a.nrlMargins,
                ),
        );
        break;
      case 8:
        sortedLeaderboard.sort(
          (a, b) => ascending
              ? (a.aflUPS + a.nrlUPS).compareTo(b.aflUPS + b.nrlUPS)
              : (b.aflUPS + b.nrlUPS).compareTo(a.aflUPS + a.nrlUPS),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildScaffold(
      context,
      di<TippersViewModel>().selectedTipper.dbkey ?? '',
      Theme.of(context).highlightColor,
    );
  }

  Widget buildScaffold(BuildContext context, String dbkey, Color color) {
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
                        Expanded(
                          child: Text(
                            'Comp Leaderboard',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Hero(
                          tag: 'trophy',
                          child: Icon(Icons.emoji_events, size: 50),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Competition leaderboard up to round ${di<DAUCompsViewModel>().selectedDAUComp!.latestRoundWithGamesCompletedOrUnderway() == 0 ? '1' : di<DAUCompsViewModel>().selectedDAUComp!.latestRoundWithGamesCompletedOrUnderway()}. Tap a row to see round scores. Tap column headings to sort.',
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
                  rows: List<DataRow>.generate(
                    sortedLeaderboard.length,
                    (index) => DataRow(
                      color: sortedLeaderboard[index].tipper.dbkey == dbkey
                          ? WidgetStateProperty.resolveWith((states) => color)
                          : WidgetStateProperty.resolveWith(
                              (states) => Colors.transparent,
                            ),
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              const Icon(Icons.arrow_forward, size: 15),
                              avatarPic(sortedLeaderboard[index].tipper),
                              Expanded(
                                child: Text(
                                  softWrap: false,
                                  sortedLeaderboard[index].tipper.name,
                                  overflow: TextOverflow.fade,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => onTipperTapped(context, index),
                        ),
                        DataCell(
                          Text(sortedLeaderboard[index].rank.toString()),
                          onTap: () => onTipperTapped(context, index),
                        ),
                        DataCell(
                          _buildRankChangeCell(sortedLeaderboard[index]),
                          onTap: () => onTipperTapped(context, index),
                        ),
                        DataCell(
                          Text(sortedLeaderboard[index].total.toString()),
                          onTap: () => onTipperTapped(context, index),
                        ),
                        DataCell(
                          Text(sortedLeaderboard[index].nRL.toString()),
                          onTap: () => onTipperTapped(context, index),
                        ),
                        DataCell(
                          Text(sortedLeaderboard[index].aFL.toString()),
                          onTap: () => onTipperTapped(context, index),
                        ),
                        DataCell(
                          Text(
                            sortedLeaderboard[index].numRoundsWon.toString(),
                          ),
                          onTap: () => onTipperTapped(context, index),
                        ),
                        DataCell(
                          Text(
                            (sortedLeaderboard[index].aflMargins +
                                    sortedLeaderboard[index].nrlMargins)
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(context, index),
                        ),
                        DataCell(
                          Text(
                            (sortedLeaderboard[index].aflUPS +
                                    sortedLeaderboard[index].nrlUPS)
                                .toString(),
                          ),
                          onTap: () => onTipperTapped(context, index),
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
      ),
    );
  }

  void onTipperTapped(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            StatRoundScoresForTipper(sortedLeaderboard[index].tipper),
      ),
    );
  }

  void onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortLeaderboard(columnIndex, ascending);
      sortColumnIndex = columnIndex;
      // For the Cng column (index 2), invert the ascending indicator to match the inverted sort
      isAscending = columnIndex == 2 ? !ascending : ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns) =>
      columns.asMap().entries.map((entry) {
        int index = entry.key;
        String column = entry.value;
        if (column == 'Name') {
          return DataColumn2(
            fixedWidth: 140,
            numeric: false,
            label: Text(column),
            onSort: (columnIndex, ascending) => onSort(index, ascending),
          );
        } else if (column == 'Cng') {
          return DataColumn2(
            fixedWidth: 45,
            numeric: true,
            label: Text(column),
            onSort: (columnIndex, ascending) => onSort(index, !ascending),
          );
        } else if (column == 'Rank') {
          return DataColumn2(
            fixedWidth: 50,
            numeric: true,
            label: Text(column),
            onSort: (columnIndex, ascending) => onSort(index, ascending),
          );
        } else {
          return DataColumn2(
            fixedWidth: 50,
            numeric: true,
            label: Text(column),
            onSort: (columnIndex, ascending) => onSort(index, ascending),
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
