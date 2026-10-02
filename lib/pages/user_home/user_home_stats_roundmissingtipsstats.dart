import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
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

  static const columns = [
    AppColumn.text('Name', sortable: true),
    AppColumn.numeric('Tips needed', sortable: true),
    AppColumn.numeric('NRL', sortable: true),
    AppColumn.numeric('AFL', sortable: true),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(BuildContext context) {
    final selected = di<TippersViewModel>().selectedTipper;
    final highlight = Theme.of(context).highlightColor;
    final entries = roundLeaderboard.entries.where((entry) =>
      entry.value.nrlTipsOutstanding + entry.value.aflTipsOutstanding > 0).toList();
    final values = <Object?>[
      selected, highlight, widget.roundNumberToDisplay,
      for (final entry in entries) ...[
        entry.key, entry.key.name, entry.key.photoURL,
        entry.value.nrlTipsOutstanding, entry.value.aflTipsOutstanding,
      ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    _rows = [
      for (final entry in entries) AppRow(
        key: ValueKey(entry.key.dbkey),
        colour: entry.key == selected ? highlight : Colors.transparent,
        cells: [
          AppCell.text(entry.key.name,
            leading: avatarPic(entry.key, widget.roundNumberToDisplay),
            leadingSize: const Size(30, 30)),
          AppCell.text((entry.value.nrlTipsOutstanding + entry.value.aflTipsOutstanding).toString()),
          AppCell.text(entry.value.nrlTipsOutstanding.toString()),
          AppCell.text(entry.value.aflTipsOutstanding.toString()),
        ],
      ),
    ];
    return _rows;
  }

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
    return SelectedCompBanner(
      child: buildScaffold(
        context,
        'Round ${widget.roundNumberToDisplay} - missing tips',
        Colors.blue,
      ),
    );
  }

  Widget buildScaffold(BuildContext context, String name, Color color) {
    final isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final fabBackgroundColor = isDarkMode
        ? const Color(0xFF4E7A36)
        : Colors.lightGreen[200];
    final fabForegroundColor = isDarkMode ? Colors.white : Colors.black87;
    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: fabBackgroundColor,
        foregroundColor: fabForegroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.arrow_back),
      ),
      body: SafeArea(
        child: AppTableFrame(
          columns: columns,
          rows: _tableRows(context),
          frozenLeading: 1,
          heading: AppTableHeading(
            leading: const Hero(
              tag: 'magnifyingGlass',
              child: Icon(Icons.search, size: 50),
            ),
            title: name,
            description:
                'Total of ${roundLeaderboard.values.fold<int>(0, (previousValue, element) => previousValue + element.nrlTipsOutstanding + element.aflTipsOutstanding)} tips outstanding across all tippers.',
          ),
          table: Padding(
            padding: const EdgeInsets.all(5.0),
            child: AppTable(
              columns: columns,
              rows: _tableRows(context),
              frozenLeading: 1,
              sort: AppSort(column: sortColumnIndex ?? 1, ascending: isAscending),
              onSort: onSort,
            ),
          ),
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

  Widget avatarPic(Tipper tipper, int round) {
    return Hero(
      tag: '$round-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds
      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 15,
      ),
    );
  }
}
