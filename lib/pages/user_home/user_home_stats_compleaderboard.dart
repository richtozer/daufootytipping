import 'dart:math' as math;

import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundpointsfortipper.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class StatCompLeaderboard extends StatefulWidget {
  //constructor
  const StatCompLeaderboard({super.key});

  @override
  State<StatCompLeaderboard> createState() => _StatCompLeaderboardState();
}

class _StatCompLeaderboardState extends State<StatCompLeaderboard> {
  late StatsViewModel statsViewModel;
  List<LeaderboardEntry> sortedLeaderboard = [];
  bool isAscending = true;
  int? sortColumnIndex = 1;

  static const columns = [
    AppColumn.text('Name', sortable: true),
    AppColumn.numeric('Rank', sortable: true, descendingFirst: false),
    AppColumn.numeric('Change', sortable: true),
    AppColumn.numeric('Total', sortable: true),
    AppColumn.numeric('NRL', sortable: true),
    AppColumn.numeric('AFL', sortable: true),
    AppColumn.numeric('Wins', sortable: true),
    AppColumn.numeric('Margins', sortable: true),
    AppColumn.numeric('UPS', sortable: true),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(BuildContext context, String dbkey, Color colour) {
    final style =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Snapshot primitives rather than mutable entries. Unchanged notifications
    // and resizing retain the row list and AppTable's measured content.
    final values = <Object?>[
      dbkey,
      colour,
      style,
      scaler,
      direction,
      for (final entry in sortedLeaderboard) ...[
        entry.tipper,
        entry.tipper.name,
        entry.tipper.photoURL,
        entry.rank,
        entry.previousRank,
        entry.rankChange,
        entry.total,
        entry.nRL,
        entry.aFL,
        entry.numRoundsWon,
        entry.aflMargins,
        entry.nrlMargins,
        entry.aflUPS,
        entry.nrlUPS,
      ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    _rows = [
      for (final entry in sortedLeaderboard)
        AppRow(
          key: ValueKey(entry.tipper.dbkey),
          colour: entry.tipper.dbkey == dbkey ? colour : Colors.transparent,
          onTap: () => onTipperTapped(context, entry.tipper),
          cells: [
            AppCell.text(
              entry.tipper.name,
              leadingSize: const Size(45, 30),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_forward, size: 15),
                  avatarPic(entry.tipper),
                ],
              ),
            ),
            AppCell.text(entry.rank.toString()),
            _rankChangeCell(entry, style, scaler, direction),
            AppCell.text(entry.total.toString()),
            AppCell.text(entry.nRL.toString()),
            AppCell.text(entry.aFL.toString()),
            AppCell.text(entry.numRoundsWon.toString()),
            AppCell.text((entry.aflMargins + entry.nrlMargins).toString()),
            AppCell.text((entry.aflUPS + entry.nrlUPS).toString()),
          ],
        ),
    ];
    return _rows;
  }

  AppCell _rankChangeCell(
    LeaderboardEntry entry,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final change = entry.rankChange;
    if (entry.previousRank == null || change == null) {
      return const AppCell.text('-');
    }
    final value = change.abs().toString();
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    final iconSize = scaler.scale(16);
    final size = Size(
      painter.width + iconSize,
      math.max(painter.height, iconSize),
    );
    painter.dispose();
    return AppCell.widget(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            change > 0
                ? Icons.arrow_upward
                : change < 0
                ? Icons.arrow_downward
                : Icons.sync_alt,
            color: change < 0 ? Colors.red : Colors.green,
            size: iconSize,
          ),
          Text(value, style: style),
        ],
      ),
      intrinsicSize: size,
      semanticLabel: change == 0
          ? 'No rank change'
          : '${change > 0 ? 'Up' : 'Down'} $value ${change.abs() == 1 ? 'place' : 'places'}',
    );
  }

  @override
  void initState() {
    super.initState();
    statsViewModel = di<StatsViewModel>();
    statsViewModel.addListener(_handleLeaderboardChanged);
    _refreshLeaderboard();
  }

  @override
  void dispose() {
    statsViewModel.removeListener(_handleLeaderboardChanged);
    super.dispose();
  }

  void _handleLeaderboardChanged() {
    if (!mounted) return;
    setState(_refreshLeaderboard);
  }

  void _refreshLeaderboard() {
    sortedLeaderboard = List<LeaderboardEntry>.from(
      statsViewModel.compLeaderboard,
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
        // Plain. The first Change tap still shows the biggest gains first,
        // but the column now asks for that by starting descending rather
        // than by sorting backwards -- which left the arrow pointing up
        // over a descending list.
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
    return SelectedCompBanner(
      child: buildScaffold(
        context,
        di<TippersViewModel>().selectedTipper.dbkey ?? '',
        Theme.of(context).highlightColor,
      ),
    );
  }

  Widget buildScaffold(BuildContext context, String dbkey, Color color) {
    return Scaffold(
      body: SafeArea(
        child: AppTableFrame(
          columns: columns,
          rows: _tableRows(context, dbkey, color),
          frozenLeading: 1,
          banner: LiveScoresWarningCard(),
          heading: AppTableHeading(
            leading: const Hero(
              tag: 'trophy',
              child: Icon(Icons.emoji_events, size: 50),
            ),
            title: 'Comp Leaderboard',
            description:
                'Competition leaderboard up to round ${di<DAUCompsViewModel>().selectedDAUComp!.latestRoundWithGamesCompletedOrUnderway() == 0 ? '1' : di<DAUCompsViewModel>().selectedDAUComp!.latestRoundWithGamesCompletedOrUnderway()}. Tap a row to see round points. Tap column headings to sort.',
          ),
          table: Padding(
            padding: const EdgeInsets.all(5.0),
            child: AppTable(
              columns: columns,
              rows: _tableRows(context, dbkey, color),
              frozenLeading: 1,
              sort: AppSort(
                column: sortColumnIndex ?? 1,
                ascending: isAscending,
              ),
              onSort: onSort,
            ),
          ),
        ),
      ),
    );
  }

  void onTipperTapped(BuildContext context, Tipper tipper) {
    Navigator.push(
      context,
      appPageRoute((context) => StatRoundPointsForTipper(tipper)),
    );
  }

  void onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortLeaderboard(columnIndex, ascending);
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
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
