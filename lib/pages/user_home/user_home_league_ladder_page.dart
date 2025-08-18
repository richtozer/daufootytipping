import 'dart:developer';
import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_team_games_history_page.dart';

class LeagueLadderPage extends StatefulWidget {
  final League league;
  final List<String>? teamDbKeysToDisplay; // Added optional parameter
  final String? customTitle; // Added optional parameter

  const LeagueLadderPage({
    super.key,
    required this.league,
    this.teamDbKeysToDisplay, // Added to constructor
    this.customTitle, // Added to constructor
  });

  @override
  State<LeagueLadderPage> createState() => _LeagueLadderPageState();
}

class _LeagueLadderPageState extends State<LeagueLadderPage> {
  LeagueLadder? _leagueLadder;
  bool _isLoading = true;
  String? _error;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  // Historical matchups state
  List<HistoricalMatchupUIData>? _historicalMatchups;
  bool _isLoadingHistoricalData = false;
  String? _historicalDataError;
  int? _historicalSortColumnIndex;
  bool _historicalSortAscending = false; // Default to newest first

  @override
  void initState() {
    super.initState();
    _fetchLadderData();

    // Fetch historical data if in comparison mode
    if (widget.teamDbKeysToDisplay != null &&
        widget.teamDbKeysToDisplay!.length == 2) {
      _fetchHistoricalMatchups();
    }
  }

  Future<void> _fetchLadderData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dauCompsViewModel = di<DAUCompsViewModel>();
      // Check if selectedDAUComp is null, getOrCalculateLeagueLadder also handles this.
      if (dauCompsViewModel.selectedDAUComp == null) {
        // This check can be more specific or rely on getOrCalculateLeagueLadder's internal handling
        // For now, let's keep it similar to the proposed structure.
        throw Exception("No competition selected. Cannot calculate ladder.");
      }

      LeagueLadder? calculatedLadder = await dauCompsViewModel
          .getOrCalculateLeagueLadder(widget.league);

      // Create a new LeagueLadder instance if filtering is needed to avoid modifying the cached version.
      if (calculatedLadder != null &&
          widget.teamDbKeysToDisplay != null &&
          widget.teamDbKeysToDisplay!.isNotEmpty) {
        // Make a deep copy of the teams list to avoid modifying the cached ladder directly
        List<LadderTeam> filteredTeams = List<LadderTeam>.from(
          calculatedLadder.teams,
        );
        filteredTeams.retainWhere(
          (team) => widget.teamDbKeysToDisplay!.contains(team.dbkey),
        );

        // Create a new LeagueLadder instance with the filtered teams
        // This ensures that the original cached ladder (with all teams and originalRanks) is not modified.
        _leagueLadder = LeagueLadder(
          league: calculatedLadder.league,
          teams: filteredTeams,
        );
      } else {
        _leagueLadder =
            calculatedLadder; // Use the ladder as is (either full or already null)
      }

      // Important: Check if mounted again before setState after async gap
      if (mounted) {
        setState(() {
          // _leagueLadder is already set above
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchHistoricalMatchups() async {
    if (!mounted) return;

    setState(() {
      _isLoadingHistoricalData = true;
      _historicalDataError = null;
    });

    try {
      if (widget.teamDbKeysToDisplay == null ||
          widget.teamDbKeysToDisplay!.length != 2) {
        throw Exception('Two teams required for historical matchups');
      }

      final dauCompsViewModel = di<DAUCompsViewModel>();
      if (dauCompsViewModel.selectedDAUComp == null) {
        throw Exception('No competition selected');
      }

      // Get the games view model to access team data
      final gamesViewModel = dauCompsViewModel.gamesViewModel;
      if (gamesViewModel == null) {
        throw Exception('Games view model not available');
      }

      await gamesViewModel.initialLoadComplete;
      await gamesViewModel.teamsViewModel.initialLoadComplete;

      // Find the two teams
      final team1 = gamesViewModel.teamsViewModel.findTeam(
        widget.teamDbKeysToDisplay![0],
      );
      final team2 = gamesViewModel.teamsViewModel.findTeam(
        widget.teamDbKeysToDisplay![1],
      );

      if (team1 == null || team2 == null) {
        throw Exception('Could not find teams for comparison');
      }

      // Get the historical games directly from GamesViewModel
      final historicalGames = await gamesViewModel.getCompleteMatchupHistory(
        team1,
        team2,
        widget.league,
      );

      // Convert games to display format
      final List<HistoricalMatchupUIData> displayData = [];
      for (final game in historicalGames) {
        final gameYear = game.startTimeUTC.year.toString();
        final gameMonth = _getMonthAbbreviation(game.startTimeUTC.month);
        final isCurrentYear = game.startTimeUTC.year == DateTime.now().year;

        String winningTeamName;
        String winType;

        if (game.scoring?.homeTeamScore != null &&
            game.scoring?.awayTeamScore != null) {
          final homeScore = game.scoring!.homeTeamScore!;
          final awayScore = game.scoring!.awayTeamScore!;

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

        // Get user's tip for this historical game
        String userTipTeamName = '';
        if (dauCompsViewModel.selectedTipperTipsViewModel != null) {
          try {
            final tippersViewModel = di<TippersViewModel>();
            final allTips = dauCompsViewModel.selectedTipperTipsViewModel;
            await allTips!.initialLoadCompleted;
            final tip = await allTips.findTip(
              game,
              tippersViewModel.selectedTipper,
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
            // If tip lookup fails, leave empty
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
    const months = [
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
          case 0: // Date
            compareResult = a.pastGame.startTimeUTC.compareTo(
              b.pastGame.startTimeUTC,
            );
            break;
          case 1: // Your Tip
            compareResult = a.userTipTeamName.compareTo(b.userTipTeamName);
            break;
          case 2: // Winner
            compareResult = a.winningTeamName.compareTo(b.winningTeamName);
            break;
          case 3: // Score - compare by total points
            final aTotal =
                (a.pastGame.scoring?.homeTeamScore ?? 0) +
                (a.pastGame.scoring?.awayTeamScore ?? 0);
            final bTotal =
                (b.pastGame.scoring?.homeTeamScore ?? 0) +
                (b.pastGame.scoring?.awayTeamScore ?? 0);
            compareResult = aTotal.compareTo(bTotal);
            break;
        }
        return ascending ? compareResult : -compareResult;
      });
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    if (_leagueLadder == null || _leagueLadder!.teams.isEmpty) return;

    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;

      _leagueLadder!.teams.sort((a, b) {
        int compareResult = 0;
        switch (columnIndex) {
          case 0: // '#' - Position (index-based for now)
            // This case needs special handling as we are sorting based on the original index.
            // However, DataTable expects a stable sort. If we sort by current index, it's tricky.
            // Let's assume for now that the initial list is by rank and sorting by '#'
            // would effectively mean sorting by the 'original' rank.
            // A better way would be to store original rank if it's not just the index.
            // For this implementation, sorting by '#' will revert to the order provided by
            // LadderCalculationService if it pre-sorts, or simply be a no-op if not handled.
            // Let's make it sort by the list's current index to reflect DataTable's behavior.
            // This might not be a "true" sort by position if other columns have been sorted.
            // A more robust solution would involve storing original ranks in LeagueLadderTeam.
            // For now, we'll sort by points as a proxy for rank, as '#' typically reflects that.
            compareResult = a.points.compareTo(b.points);
            if (compareResult == 0) {
              compareResult = a.percentage.compareTo(b.percentage);
            }
            // Since '#' column sorting usually means highest points/percentage first,
            // and DataColumn sort is ascending by default for the first click,
            // we might need to invert the logic for this specific column if 'ascending' means 'rank 1, 2, 3...'.
            // Let's stick to standard comparison and user can click again to invert.
            break;
          case 1: // 'Team'
            compareResult = a.teamName.compareTo(b.teamName);
            break;
          case 2: // 'Gms'
            compareResult = a.played.compareTo(b.played);
            break;
          case 3: // 'Pts'
            compareResult = a.points.compareTo(b.points);
            break;
          case 4: // 'W'
            compareResult = a.won.compareTo(b.won);
            break;
          case 5: // 'L'
            compareResult = a.lost.compareTo(b.lost);
            break;
          case 6: // 'D'
            compareResult = a.drawn.compareTo(b.drawn);
            break;
          case 7: // 'For'
            compareResult = a.pointsFor.compareTo(b.pointsFor);
            break;
          case 8: // 'Agst'
            compareResult = a.pointsAgainst.compareTo(b.pointsAgainst);
            break;
          case 9: // '%'
            compareResult = a.percentage.compareTo(b.percentage);
            break;
        }
        return ascending ? compareResult : -compareResult;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(
      context,
    ).orientation; // Get orientation

    return Scaffold(
      // appBar: AppBar(...) removed
      body: SingleChildScrollView(
        child: Column(
          // Existing body wrapped in Column
          children: [
            // Step 1: Add HeaderWidget conditionally with improved styling for comparison mode
            orientation == Orientation.portrait
                ? (widget.teamDbKeysToDisplay != null &&
                          widget.teamDbKeysToDisplay!.length == 2)
                      ? SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              16.0,
                              16.0,
                              16.0,
                              8.0,
                            ),
                            child: Row(
                              children: [
                                Hero(
                                  tag:
                                      "${widget.league.name.toLowerCase()}_league_logo_hero",
                                  child: SvgPicture.asset(
                                    widget.league == League.nrl
                                        ? 'assets/teams/nrl.svg'
                                        : 'assets/teams/afl.svg',
                                    width: 40,
                                    height: 40,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'League Leaderboard Comparison ${DateTime.now().year}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : HeaderWidget(
                          leadingIconAvatar: Hero(
                            tag:
                                "${widget.league.name.toLowerCase()}_league_logo_hero",
                            child: SvgPicture.asset(
                              widget.league == League.nrl
                                  ? 'assets/teams/nrl.svg'
                                  : 'assets/teams/afl.svg',
                              width: 35,
                              height: 35,
                            ),
                          ),
                          text:
                              "${widget.league.name.toUpperCase()} Premiership Ladder",
                        )
                : Container(), // Empty container if not in portrait
            // Add Explanatory Text (conditionally based on filtered vs full view)
            orientation == Orientation.portrait
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 8.0),
                    child: Text(
                      (widget.teamDbKeysToDisplay != null &&
                              widget.teamDbKeysToDisplay!.isNotEmpty)
                          ? "Compare the stats of the teams in this match. Tap column headers to sort. Tap an individual team to see stats on all their match ups."
                          : "This is the current ${widget.league.name.toUpperCase()} premiership ladder. Tap column headers to sort. Tap a row to see the team's game history. Colour shading indicates the top 8 teams.",
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                  )
                : Container(),

            // The existing body content (DataTable section) - allow natural height
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : _leagueLadder == null || _leagueLadder!.teams.isEmpty
                ? const Center(child: Text('No ladder data available.'))
                : SingleChildScrollView(
                    // Horizontal scroll only
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: DataTable(
                        border: TableBorder.all(
                          width: 1.0,
                          color: Colors.grey.shade300,
                        ),
                        columnSpacing: 10.0,
                        horizontalMargin: 8.0,
                        headingRowHeight: 36.0,
                        sortColumnIndex: _sortColumnIndex,
                        sortAscending: _sortAscending,
                        columns: <DataColumn>[
                          DataColumn(
                            label: const Text(
                              '#',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              'Team',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              'Gms',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              'Pts',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              'W',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              'L',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              'D',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              'For',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              'Agst',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                          DataColumn(
                            label: const Text(
                              '%',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (int columnIndex, bool ascending) =>
                                _onSort(columnIndex, ascending),
                          ),
                        ],
                        rows: List<DataRow>.generate(_leagueLadder!.teams.length, (
                          index,
                        ) {
                          final ladderTeam = _leagueLadder!
                              .teams[index]; // This is a LadderTeam object
                          // final isTop8 = index < 8; // Old logic for Top 8 teams
                          final bool isTop8 =
                              (ladderTeam.originalRank != null &&
                              ladderTeam.originalRank! <=
                                  8); // New logic for Top 8 teams

                          // Create a Team object for navigation
                          final Team teamForHistory = Team(
                            dbkey: ladderTeam.dbkey,
                            name: ladderTeam.teamName,
                            logoURI: ladderTeam.logoURI,
                            league: widget
                                .league, // widget.league is the League object of the current ladder page
                          );

                          void navigateToHistory() {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TeamGamesHistoryPage(
                                  team: teamForHistory,
                                  league: widget.league,
                                ),
                              ),
                            );
                          }

                          return DataRow(
                            color: WidgetStateProperty.resolveWith<Color?>((
                              Set<WidgetState> states,
                            ) {
                              if (isTop8) {
                                // Check if we're in dark mode
                                final bool isDarkMode =
                                    Theme.of(context).brightness ==
                                    Brightness.dark;

                                if (widget.league == League.afl) {
                                  return isDarkMode
                                      ? League.afl.colour.darken(10)
                                      // Dark mode: darker, more transparent
                                      : League.afl.colour.brighten(
                                          20,
                                        ); // Light mode: brighter
                                }
                                if (widget.league == League.nrl) {
                                  return isDarkMode
                                      ? League.nrl.colour.darken(
                                          10,
                                        ) // Dark mode: darker, more transparent
                                      : League.nrl.colour.brighten(
                                          20,
                                        ); // Light mode: brighter
                                }
                              }
                              return null; // Default row color
                            }),
                            cells: <DataCell>[
                              DataCell(
                                Row(
                                  children: [
                                    // add a arrow icon to indicate navigation to another page
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    Text(
                                      ladderTeam.originalRank?.toString() ??
                                          '-',
                                    ),
                                  ],
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 6.0,
                                      ),
                                      child: Hero(
                                        tag: "team_icon_${ladderTeam.dbkey}",
                                        child: SvgPicture.asset(
                                          ladderTeam.logoURI ??
                                              'assets/images/default_logo.svg',
                                          width: 28,
                                          height: 28,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        ladderTeam.teamName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Text(
                                  ladderTeam.played.toString(),
                                  textAlign: TextAlign.right,
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Text(
                                  ladderTeam.points.toString(),
                                  textAlign: TextAlign.right,
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Text(
                                  ladderTeam.won.toString(),
                                  textAlign: TextAlign.right,
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Text(
                                  ladderTeam.lost.toString(),
                                  textAlign: TextAlign.right,
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Text(
                                  ladderTeam.drawn.toString(),
                                  textAlign: TextAlign.right,
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Text(
                                  ladderTeam.pointsFor.toString(),
                                  textAlign: TextAlign.right,
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Text(
                                  ladderTeam.pointsAgainst.toString(),
                                  textAlign: TextAlign.right,
                                ),
                                onTap: navigateToHistory,
                              ),
                              DataCell(
                                Text(
                                  ladderTeam.percentage.toStringAsFixed(2),
                                  textAlign: TextAlign.right,
                                ),
                                onTap: navigateToHistory,
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),

            // Historical Matchups Section - only show in comparison mode
            if (widget.teamDbKeysToDisplay != null &&
                widget.teamDbKeysToDisplay!.length == 2)
              Column(
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
                            Icon(
                              Icons.history,
                              size: 24,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Historical Matchups',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (orientation == Orientation.portrait)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Recent Head-to-head history between these teams. Includes your tipping history (where available).',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          ),
                        const SizedBox(height: 8),
                        _buildHistoricalMatchupsSection(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pop(context),
        backgroundColor: Colors.lightGreen[200],
        foregroundColor: Colors.white70,
        child: const Icon(Icons.arrow_back),
      ),
    );
  }

  Widget _buildHistoricalMatchupsSection() {
    if (_isLoadingHistoricalData) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_historicalDataError != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            children: [
              Text(
                'Error loading historical data: $_historicalDataError',
                style: TextStyle(color: Colors.red),
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
      );
    }

    if (_historicalMatchups == null || _historicalMatchups!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(
          child: Text(
            'No historical matchups found between these teams.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return SizedBox(
      height: 400, // Fixed height for the historical section
      child: DataTable2(
        border: TableBorder.all(width: 1.0, color: Colors.grey.shade300),
        columnSpacing: 0,
        horizontalMargin: 0,
        minWidth: 600,
        fixedTopRows: 1,
        fixedLeftColumns:
            MediaQuery.of(context).orientation == Orientation.portrait ? 1 : 0,
        showCheckboxColumn: false,
        isHorizontalScrollBarVisible: true,
        isVerticalScrollBarVisible: true,
        sortColumnIndex: _historicalSortColumnIndex,
        sortAscending: _historicalSortAscending,
        dataRowHeight: 48.0, // Tighten row height from default (~56)
        headingRowHeight: 40.0, // Also tighten header height
        columns: [
          DataColumn2(
            fixedWidth: 80,
            label: const Text('Date'),
            onSort: (columnIndex, ascending) =>
                _onHistoricalSort(columnIndex, ascending),
          ),
          DataColumn2(
            fixedWidth: 100,
            label: const Text('Your Tip'),
            onSort: (columnIndex, ascending) =>
                _onHistoricalSort(columnIndex, ascending),
          ),
          DataColumn2(
            fixedWidth: 120,
            label: const Text('Winner'),
            onSort: (columnIndex, ascending) =>
                _onHistoricalSort(columnIndex, ascending),
          ),
          DataColumn2(
            fixedWidth: 100,
            label: const Text('Score'),
            onSort: (columnIndex, ascending) =>
                _onHistoricalSort(columnIndex, ascending),
          ),
        ],
        rows: _historicalMatchups!.map((matchup) {
          final game = matchup.pastGame;
          final homeScore = game.scoring?.homeTeamScore?.toString() ?? '-';
          final awayScore = game.scoring?.awayTeamScore?.toString() ?? '-';

          // Note: Home/Away labels show the perspective of the winning team

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
                                : Colors.purple.withValues(alpha: 0.3),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          matchup.winType == 'Home' ? 'Home' : 'Away',
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
                Text('$homeScore - $awayScore', textAlign: TextAlign.center),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTipOutcomeCell(HistoricalMatchupUIData matchup) {
    if (matchup.userTipTeamName.isEmpty) {
      return const Text(
        'N/A',
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }

    // Determine if the tip was correct
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
}
