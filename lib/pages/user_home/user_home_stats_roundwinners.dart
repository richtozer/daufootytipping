import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundleaderboard.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_under_controls_area.dart';
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

  static const columns = [
    AppColumn.numeric('Round', sortable: true),
    AppColumn.text('Winner', sortable: true),
    AppColumn.numeric('Total', sortable: true),
    AppColumn.numeric('NRL', sortable: true),
    AppColumn.numeric('AFL', sortable: true),
    AppColumn.numeric('Margins', sortable: true),
    AppColumn.numeric('UPS', sortable: true),
    AppColumn.navigation(),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(BuildContext context) {
    final theme = Theme.of(context);
    final selected = di<TippersViewModel>().selectedTipper;
    final winners = statsViewModel.roundWinners.values
        .expand((group) => group)
        .toList();
    final values = <Object?>[
      theme.brightness,
      theme.highlightColor,
      selected,
      for (final winner in winners) ...[
        winner.roundNumber,
        winner.tipper,
        winner.tipper.name,
        winner.tipper.photoURL,
        winner.total,
        winner.nRL,
        winner.aFL,
        winner.aflMargins,
        winner.nrlMargins,
        winner.aflUPS,
        winner.nrlUPS,
      ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    int? lastRound;
    var alternate = false;
    _rows = [
      for (final winner in winners)
        (() {
          if (lastRound != winner.roundNumber) alternate = !alternate;
          lastRound = winner.roundNumber;
          final groupColour = theme.brightness == Brightness.dark
              ? (alternate ? Colors.grey.shade800 : Colors.grey.shade600)
              : (alternate ? Colors.grey.shade200 : Colors.grey.shade400);
          return AppRow(
            key: ValueKey((winner.roundNumber, winner.tipper.dbkey)),
            colour: winner.tipper == selected
                ? theme.highlightColor
                : groupColour,
            onTap: () => onRowTapped(context, winner),
            cells: [
              AppCell.text(winner.roundNumber.toString()),
              AppCell.text(
                winner.tipper.name,
                leading: avatarPic(winner.tipper, winner.roundNumber),
                leadingSize: const Size(30, 30),
              ),
              AppCell.text(winner.total.toString()),
              AppCell.text(winner.nRL.toString()),
              AppCell.text(winner.aFL.toString()),
              AppCell.text((winner.aflMargins + winner.nrlMargins).toString()),
              AppCell.text((winner.aflUPS + winner.nrlUPS).toString()),
              AppCell.navigation(),
            ],
          );
        })(),
    ];
    return _rows;
  }

  @override
  void initState() {
    super.initState();
    statsViewModel = di<StatsViewModel>();
    onSort(0, false);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StatsViewModel>.value(
      value: statsViewModel,
      child: Consumer<StatsViewModel>(
        builder: (context, statsViewModelConsumer, child) {
          return SelectedCompBanner(
            child: Scaffold(
              body: AppUnderControlsArea(
                child: AppTableFrame(
                  columns: columns,
                  rows: _tableRows(context),
                  frozenLeading: 2,
                  banner: LiveScoresWarningCard(),
                  heading: const AppTableHeading(
                    leading: Hero(
                      tag: 'person',
                      child: Icon(Icons.person, size: 50),
                    ),
                    title: 'Round Winners',
                    description: 'Round winners grouped by round. Tap a row to see the full round leaderboard.',
                  ),
                  table: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: AppTable(
                      columns: columns,
                      rows: _tableRows(context),
                      frozenLeading: 2,
                      sort: AppSort(
                        column: sortColumnIndex ?? 0,
                        ascending: isAscending,
                      ),
                      onSort: onSort,
                    ),
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
      appPageRoute((context) => StatRoundLeaderboard(winner.roundNumber)),
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

  Widget avatarPic(Tipper tipper, int roundNumber) {
    return Hero(
      tag: '$roundNumber-${tipper.dbkey!}', // disambiguate the tag when tipper has won multiple rounds
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
