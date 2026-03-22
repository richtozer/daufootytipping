import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class RoundMissingTipsStats extends StatefulWidget {
  //constructor
  const RoundMissingTipsStats(this.roundNumberToDisplay, {super.key});

  final int roundNumberToDisplay;

  @override
  State<RoundMissingTipsStats> createState() => _RoundMissingTipsStatsState();
}

class _RoundMissingTipsStatsState extends State<RoundMissingTipsStats> {
  late StatsViewModel statsViewModel;
  Map<Tipper, RoundStats> roundLeaderboard = {};

  bool isAscending = false; // Default to descending
  int? sortColumnIndex = 1;

  final List<String> columns = ['Name', 'Tips\nNeeded', 'NRL', 'AFL'];

  @override
  void initState() {
    super.initState();

    statsViewModel = di<StatsViewModel>();
    sortColumnIndex = 1;
    isAscending = false;
    statsViewModel.addListener(_handleStatsChanged);
    _refreshLeaderboard();
  }

  @override
  void didUpdateWidget(covariant RoundMissingTipsStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundNumberToDisplay != widget.roundNumberToDisplay) {
      _refreshLeaderboard();
    }
  }

  @override
  void dispose() {
    statsViewModel.removeListener(_handleStatsChanged);
    super.dispose();
  }

  void _handleStatsChanged() {
    if (!mounted) return;
    setState(_refreshLeaderboard);
  }

  void _refreshLeaderboard() {
    roundLeaderboard = statsViewModel.getRoundLeaderBoard(
      widget.roundNumberToDisplay,
    );
    _sortLeaderboard(sortColumnIndex!, isAscending);
  }

  @override
  Widget build(BuildContext context) {
    return buildScaffold(
      context,
      'Round ${widget.roundNumberToDisplay} - missing tips',
      Colors.blue,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                          tag: 'magnifyingGlass',
                          child: Icon(Icons.search, size: 50),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (orientation == Orientation.portrait)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
                child: Text(
                  'Total of ${roundLeaderboard.values.fold<int>(0, (previousValue, element) => previousValue + element.nrlTipsOutstanding + element.aflTipsOutstanding)} tips outstanding across all tippers.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ),

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
                  rows: roundLeaderboard.entries
                      .where(
                        (entry) =>
                            entry.value.nrlTipsOutstanding +
                                entry.value.aflTipsOutstanding >
                            0,
                      )
                      .map((MapEntry<Tipper, RoundStats> entry) {
                        return DataRow(
                          color:
                              entry.key == di<TippersViewModel>().selectedTipper
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
                                  avatarPic(
                                    entry.key,
                                    widget.roundNumberToDisplay,
                                  ),
                                  Expanded(
                                    child: Text(
                                      softWrap: false,
                                      entry.key.name,
                                      overflow: TextOverflow.fade,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Text(
                                (entry.value.nrlTipsOutstanding +
                                        entry.value.aflTipsOutstanding)
                                    .toString(),
                              ),
                            ),
                            DataCell(
                              Text(entry.value.nrlTipsOutstanding.toString()),
                            ),
                            DataCell(
                              Text(entry.value.aflTipsOutstanding.toString()),
                            ),
                          ],
                        );
                      })
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sortLeaderboard(int columnIndex, bool ascending) {
    if (columnIndex == 0) {
      if (ascending) {
        // Sort by tipper.name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) =>
                a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase()),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by tipper.name
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) =>
                b.key.name.toLowerCase().compareTo(a.key.name.toLowerCase()),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 1) {
      if (ascending) {
        // Sort by total tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => (a.value.nrlTipsOutstanding + a.value.aflTipsOutstanding)
                .compareTo(
                  b.value.nrlTipsOutstanding + b.value.aflTipsOutstanding,
                ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by total tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => (b.value.nrlTipsOutstanding + b.value.aflTipsOutstanding)
                .compareTo(
                  a.value.nrlTipsOutstanding + a.value.aflTipsOutstanding,
                ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 2) {
      if (ascending) {
        // Sort by nrl tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => a.value.nrlTipsOutstanding.compareTo(
              b.value.nrlTipsOutstanding,
            ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by nrl tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => b.value.nrlTipsOutstanding.compareTo(
              a.value.nrlTipsOutstanding,
            ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
    if (columnIndex == 3) {
      if (ascending) {
        // Sort by afl tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => a.value.aflTipsOutstanding.compareTo(
              b.value.aflTipsOutstanding,
            ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      } else {
        // Sort by afl tips outstanding
        var sortedEntries = roundLeaderboard.entries.toList()
          ..sort(
            (a, b) => b.value.aflTipsOutstanding.compareTo(
              a.value.aflTipsOutstanding,
            ),
          );

        roundLeaderboard = Map.fromEntries(sortedEntries);
      }
    }
  }

  void onSort(int columnIndex, bool ascending) {
    _sortLeaderboard(columnIndex, ascending);
    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
  }

  List<DataColumn> getColumns(List<String> columns) =>
      columns.asMap().entries.map((entry) {
        int index = entry.key;
        String column = entry.value;
        return DataColumn2(
          fixedWidth: column == 'Name' ? 175 : 70,
          numeric: column == 'Name' ? false : true,
          label: Text(softWrap: false, overflow: TextOverflow.fade, column),
          onSort: (columnIndex, ascending) => onSort(index, ascending),
        );
      }).toList();

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
