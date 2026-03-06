import 'dart:developer';

import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
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

      final team1 = gamesViewModel.teamsViewModel.findTeam(widget.teamDbKeys[0]);
      final team2 = gamesViewModel.teamsViewModel.findTeam(widget.teamDbKeys[1]);

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

  Widget _buildTipOutcomeCell(HistoricalMatchupUIData matchup) {
    if (matchup.userTipTeamName.isEmpty) {
      return const Text(
        'N/A',
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }

    bool tipWasCorrect = false;
    Color textColor = Colors.red;
    Icon? icon;

    if (matchup.winningTeamName == 'Draw' &&
        matchup.userTipTeamName == 'Draw') {
      tipWasCorrect = true;
    } else if (matchup.winningTeamName != 'Draw' &&
        matchup.userTipTeamName == matchup.winningTeamName) {
      tipWasCorrect = true;
    }

    if (tipWasCorrect) {
      textColor = Colors.green;
      icon = const Icon(Icons.check_circle, size: 14, color: Colors.green);
    } else {
      textColor = Colors.red;
      icon = const Icon(Icons.cancel, size: 14, color: Colors.red);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            matchup.userTipTeamName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Orientation orientation = MediaQuery.of(context).orientation;

    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(thickness: 1, height: 16),
              Row(
                children: [
                  Icon(Icons.history, size: 24, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Historical Matchups',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (orientation == Orientation.portrait)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Recent Head-to-head history between these teams. Includes your tipping history (where available).',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
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
                  child: DataTable2(
                    border: TableBorder.all(
                      width: 1.0,
                      color: Colors.grey.shade300,
                    ),
                    columnSpacing: 0,
                    horizontalMargin: 0,
                    minWidth: 600,
                    fixedTopRows: 1,
                    fixedLeftColumns:
                        orientation == Orientation.portrait ? 1 : 0,
                    showCheckboxColumn: false,
                    isHorizontalScrollBarVisible: true,
                    isVerticalScrollBarVisible: true,
                    sortColumnIndex: _historicalSortColumnIndex,
                    sortAscending: _historicalSortAscending,
                    dataRowHeight: 48.0,
                    headingRowHeight: 40.0,
                    columns: [
                      DataColumn2(
                        fixedWidth: 80,
                        label: const Text('Date'),
                        onSort: _onHistoricalSort,
                      ),
                      DataColumn2(
                        fixedWidth: 100,
                        label: const Text('Your Tip'),
                        onSort: _onHistoricalSort,
                      ),
                      DataColumn2(
                        fixedWidth: 120,
                        label: const Text('Winner'),
                        onSort: _onHistoricalSort,
                      ),
                      DataColumn2(
                        fixedWidth: 100,
                        label: const Text('Score'),
                        onSort: _onHistoricalSort,
                      ),
                    ],
                    rows: _historicalMatchups!.map((matchup) {
                      final game = matchup.pastGame;
                      final String homeScore =
                          game.scoring?.homeTeamScore?.toString() ?? '-';
                      final String awayScore =
                          game.scoring?.awayTeamScore?.toString() ?? '-';

                      return DataRow2(
                        cells: [
                          DataCell(
                            Text(
                              matchup.isCurrentYear
                                  ? matchup.month
                                  : '${matchup.month} ${matchup.year}',
                            ),
                          ),
                          DataCell(_buildTipOutcomeCell(matchup)),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (matchup.winType != 'Draw' &&
                                    matchup.winType != 'Unknown')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (matchup.winType == 'Home')
                                          ? Colors.blue.withValues(alpha: 0.1)
                                          : Colors.purple.withValues(alpha: 0.1),
                                      border: Border.all(
                                        color: (matchup.winType == 'Home')
                                            ? Colors.blue.withValues(alpha: 0.3)
                                            : Colors.purple.withValues(
                                                alpha: 0.3,
                                              ),
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      matchup.winType == 'Home'
                                          ? 'Home'
                                          : 'Away',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: (matchup.winType == 'Home')
                                            ? Colors.blue[700]
                                            : Colors.purple[700],
                                      ),
                                    ),
                                  ),
                                if (matchup.winType != 'Draw' &&
                                    matchup.winType != 'Unknown')
                                  const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    matchup.winningTeamName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: matchup.winType == 'Draw'
                                          ? FontWeight.normal
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              '$homeScore - $awayScore',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
