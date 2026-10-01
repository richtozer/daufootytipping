import 'dart:developer';

import 'dart:math' as math;
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:watch_it/watch_it.dart';

class LeagueLadderHistoricalMatchups extends StatefulWidget {
  final League league;
  final List<String> teamDbKeys;

  const LeagueLadderHistoricalMatchups({
    super.key,
    required this.league,
    required this.teamDbKeys,
  });

  @override
  State<LeagueLadderHistoricalMatchups> createState() =>
      _LeagueLadderHistoricalMatchupsState();
}

class _LeagueLadderHistoricalMatchupsState
    extends State<LeagueLadderHistoricalMatchups> {
  List<HistoricalMatchupUIData>? _historicalMatchups;
  bool _isLoadingHistoricalData = false;
  String? _historicalDataError;
  int? _historicalSortColumnIndex;
  bool _historicalSortAscending = false;

  static const columns = [
    AppColumn.text('Date', sortable: true),
    AppColumn.text('Your Tip', sortable: true),
    AppColumn.text('Winner', grow: true, sortable: true),
    AppColumn.numeric('Score', sortable: true),
  ];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  List<AppRow> _tableRows(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final matchups = _historicalMatchups ?? <HistoricalMatchupUIData>[];
    final values = <Object?>[
      body, scaler, direction,
      for (final matchup in matchups) ...[
        matchup.month, matchup.year, matchup.isCurrentYear, matchup.winType,
        matchup.userTipTeamName, matchup.winningTeamName,
        matchup.pastGame.scoring?.homeTeamScore, matchup.pastGame.scoring?.awayTeamScore,
        matchup.pastGame.homeTeam.logoURI, matchup.pastGame.awayTeam.logoURI,
      ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    _rows = [
      for (final matchup in matchups) AppRow(cells: [
        AppCell.text(matchup.isCurrentYear ? matchup.month : '${matchup.month} ${matchup.year}'),
        _tipCell(matchup),
        _winnerCell(context, matchup, body, scaler, direction),
        AppCell.text('${matchup.pastGame.scoring?.homeTeamScore ?? '-'} - '
          '${matchup.pastGame.scoring?.awayTeamScore ?? '-'}'),
      ]),
    ];
    return _rows;
  }

  AppCell _tipCell(HistoricalMatchupUIData matchup) {
    if (matchup.userTipTeamName.isEmpty) {
      return const AppCell.text('N/A',
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
    }
    final correct = matchup.userTipTeamName == matchup.winningTeamName;
    final colour = correct ? Colors.green : Colors.red;
    return AppCell.text(matchup.userTipTeamName,
      style: TextStyle(color: colour, fontWeight: FontWeight.w500),
      leading: Icon(correct ? Icons.check_circle : Icons.cancel, size: 14, color: colour),
      leadingSize: const Size(14, 14),
      semanticLabel: '${matchup.userTipTeamName}, ${correct ? 'correct' : 'incorrect'} tip');
  }

  AppCell _winnerCell(BuildContext context, HistoricalMatchupUIData matchup,
      TextStyle body, TextScaler scaler, TextDirection direction) {
    final home = matchup.winType == 'Home';
    final hasWinner = home || matchup.winType == 'Away';
    final label = home ? 'Home' : 'Away';
    final badgeStyle = body.copyWith(fontSize: 10, fontWeight: FontWeight.w500,
      color: home ? Colors.blue[700] : Colors.purple[700]);
    final painter = TextPainter(text: TextSpan(text: label, style: badgeStyle),
      textScaler: scaler, textDirection: direction)..layout();
    final leadingSize = Size(painter.width + 10 + 6 + 20,
      math.max(painter.height + 4, 20));
    painter.dispose();
    return AppCell.text(matchup.winningTeamName,
      style: TextStyle(fontWeight: matchup.winType == 'Draw'
          ? FontWeight.normal : FontWeight.w500),
      semanticLabel: hasWinner ? '$label, ${matchup.winningTeamName}' : matchup.winningTeamName,
      leadingSize: hasWinner ? leadingSize : Size.zero,
      leading: hasWinner ? Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: (home ? Colors.blue : Colors.purple).withValues(alpha: 0.1),
            border: Border.all(color: (home ? Colors.blue : Colors.purple).withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(3)),
          child: Text(label, style: badgeStyle)),
        const SizedBox(width: 6),
        _buildTeamLogo(home ? matchup.pastGame.homeTeam.logoURI : matchup.pastGame.awayTeam.logoURI),
      ]) : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchHistoricalMatchups();
  }

  Future<void> _fetchHistoricalMatchups() async {
    if (!mounted) return;

    setState(() {
      _isLoadingHistoricalData = true;
      _historicalDataError = null;
    });

    try {
      if (widget.teamDbKeys.length != 2) {
        throw Exception('Two teams required for historical matchups');
      }

      final DAUCompsViewModel dauCompsViewModel = di<DAUCompsViewModel>();
      if (dauCompsViewModel.selectedDAUComp == null) {
        throw Exception('No competition selected');
      }

      final gamesViewModel = dauCompsViewModel.gamesViewModel;
      if (gamesViewModel == null) {
        throw Exception('Games view model not available');
      }

      await gamesViewModel.initialLoadComplete;
      await gamesViewModel.teamsViewModel.initialLoadComplete;

      final team1 = gamesViewModel.teamsViewModel.findTeam(
        widget.teamDbKeys[0],
      );
      final team2 = gamesViewModel.teamsViewModel.findTeam(
        widget.teamDbKeys[1],
      );

      if (team1 == null || team2 == null) {
        throw Exception('Could not find teams for comparison');
      }

      final historicalGames = await gamesViewModel.getCompleteMatchupHistory(
        team1,
        team2,
        widget.league,
      );

      final List<HistoricalMatchupUIData> displayData =
          <HistoricalMatchupUIData>[];
      for (final game in historicalGames) {
        final String gameYear = game.startTimeUTC.year.toString();
        final String gameMonth = _getMonthAbbreviation(game.startTimeUTC.month);
        final bool isCurrentYear =
            game.startTimeUTC.year == DateTime.now().year;

        String winningTeamName;
        String winType;

        if (game.scoring?.homeTeamScore != null &&
            game.scoring?.awayTeamScore != null) {
          final int homeScore = game.scoring!.homeTeamScore!;
          final int awayScore = game.scoring!.awayTeamScore!;

          if (homeScore > awayScore) {
            winningTeamName = game.homeTeam.name;
            winType = 'Home';
          } else if (awayScore > homeScore) {
            winningTeamName = game.awayTeam.name;
            winType = 'Away';
          } else {
            winningTeamName = 'Draw';
            winType = 'Draw';
          }
        } else {
          winningTeamName = 'Unknown';
          winType = 'Unknown';
        }

        String userTipTeamName = '';
        if (dauCompsViewModel.selectedTipperTipsViewModel != null) {
          try {
            final TippersViewModel tippersViewModel = di<TippersViewModel>();
            final allTips = dauCompsViewModel.selectedTipperTipsViewModel;
            await allTips!.initialLoadCompleted;
            final tip = await allTips.findTipAcrossCompetitions(
              game,
              tippersViewModel.selectedTipper,
              dauCompsViewModel.daucomps,
            );

            if (tip != null && !tip.isDefaultTip()) {
              if (tip.tip == GameResult.a || tip.tip == GameResult.b) {
                userTipTeamName = game.homeTeam.name;
              } else if (tip.tip == GameResult.d || tip.tip == GameResult.e) {
                userTipTeamName = game.awayTeam.name;
              } else if (tip.tip == GameResult.c) {
                userTipTeamName = 'Draw';
              }
            }
          } catch (e) {
            log('Failed to get tip for game ${game.dbkey}: $e');
          }
        }

        displayData.add(
          HistoricalMatchupUIData(
            year: gameYear,
            month: gameMonth,
            winningTeamName: winningTeamName,
            winType: winType,
            userTipTeamName: userTipTeamName,
            isCurrentYear: isCurrentYear,
            pastGame: game,
            location: game.location,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _historicalMatchups = displayData;
          _isLoadingHistoricalData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _historicalDataError = e.toString();
          _isLoadingHistoricalData = false;
        });
      }
    }
  }

  String _getMonthAbbreviation(int month) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  void _onHistoricalSort(int columnIndex, bool ascending) {
    if (_historicalMatchups == null || _historicalMatchups!.isEmpty) return;

    setState(() {
      _historicalSortColumnIndex = columnIndex;
      _historicalSortAscending = ascending;

      _historicalMatchups!.sort((a, b) {
        int compareResult = 0;
        switch (columnIndex) {
          case 0:
            compareResult = a.pastGame.startTimeUTC.compareTo(
              b.pastGame.startTimeUTC,
            );
            break;
          case 1:
            compareResult = a.userTipTeamName.compareTo(b.userTipTeamName);
            break;
          case 2:
            compareResult = a.winningTeamName.compareTo(b.winningTeamName);
            break;
          case 3:
            final int aTotal =
                (a.pastGame.scoring?.homeTeamScore ?? 0) +
                (a.pastGame.scoring?.awayTeamScore ?? 0);
            final int bTotal =
                (b.pastGame.scoring?.homeTeamScore ?? 0) +
                (b.pastGame.scoring?.awayTeamScore ?? 0);
            compareResult = aTotal.compareTo(bTotal);
            break;
        }
        return ascending ? compareResult : -compareResult;
      });
    });
  }

  Widget _buildTeamLogo(String? logoURI) {
    if (logoURI != null && logoURI.isNotEmpty) {
      return SvgPicture.asset(
        logoURI,
        width: 20,
        height: 20,
        placeholderBuilder: (context) =>
            const Icon(Icons.shield, size: 20, color: Colors.grey),
      );
    }
    return const Icon(Icons.shield, size: 20, color: Colors.grey);
  }

  @override
  Widget build(BuildContext context) {
    final Orientation orientation = MediaQuery.of(context).orientation;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Historical Matchups',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.history, size: 50),
                ],
              ),
              if (orientation == Orientation.portrait)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Recent head-to-head history between these teams. Includes your tipping history (where available). Tap column headings to sort.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                ),
              const SizedBox(height: 8),
              if (_isLoadingHistoricalData)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_historicalDataError != null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          'Error loading historical data: $_historicalDataError',
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _fetchHistoricalMatchups,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_historicalMatchups == null ||
                  _historicalMatchups!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(
                    child: Text(
                      'No historical matchups found between these teams.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 400,
                  child: AppTable(
                    columns: columns,
                    rows: _tableRows(context),
                    frozenLeading: 1,
                    sort: _historicalSortColumnIndex == null ? null
                        : AppSort(column: _historicalSortColumnIndex!, ascending: _historicalSortAscending),
                    onSort: _onHistoricalSort,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
