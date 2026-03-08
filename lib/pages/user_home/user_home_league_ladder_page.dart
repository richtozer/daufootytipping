import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_historical.dart';
import 'package:daufootytipping/pages/user_home/user_home_team_games_history_page.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';

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
  String? _emptyMessage;
  int? _sortColumnIndex;
  bool _sortAscending = true;
  String? _comparisonTeamNamesText;

  bool get _isComparisonMode =>
      widget.teamDbKeysToDisplay != null &&
      widget.teamDbKeysToDisplay!.length == 2;

  @override
  void initState() {
    super.initState();
    _fetchLadderData();
    _loadComparisonTeamNames();
  }

  Future<void> _fetchLadderData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _emptyMessage = null;
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
      final ladderAvailability = dauCompsViewModel.getLeagueLadderAvailability(
        widget.league,
      );

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
          if (_leagueLadder == null &&
              ladderAvailability == LeagueLadderAvailability.insufficientData) {
            _emptyMessage =
                'Ladder will be available after Round 1 ends.';
          } else {
            _emptyMessage = 'No ladder data available.';
          }
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

  Future<void> _loadComparisonTeamNames() async {
    if (!_isComparisonMode) {
      return;
    }

    try {
      final DAUCompsViewModel dauCompsViewModel = di<DAUCompsViewModel>();
      final gamesViewModel = dauCompsViewModel.gamesViewModel;
      if (gamesViewModel == null) {
        return;
      }

      await gamesViewModel.initialLoadComplete;
      await gamesViewModel.teamsViewModel.initialLoadComplete;

      final List<String> teamNames = <String>[];
      for (final String teamDbKey in widget.teamDbKeysToDisplay!) {
        final team = gamesViewModel.teamsViewModel.findTeam(teamDbKey);
        if (team != null) {
          teamNames.add(team.name);
        }
      }

      if (!mounted || teamNames.length != 2) {
        return;
      }

      setState(() {
        _comparisonTeamNamesText = '${teamNames[0]} vs ${teamNames[1]}';
      });
    } catch (_) {
      // Fall back to ladder-derived names if team lookup is unavailable.
    }
  }

  String? _comparisonTeamNamesFromLadder() {
    if (!_isComparisonMode || _leagueLadder == null) {
      return null;
    }

    final List<String> teamNames = <String>[];
    for (final String teamDbKey in widget.teamDbKeysToDisplay!) {
      LadderTeam? matchingTeam;
      for (final LadderTeam team in _leagueLadder!.teams) {
        if (team.dbkey == teamDbKey) {
          matchingTeam = team;
          break;
        }
      }
      if (matchingTeam != null) {
        teamNames.add(matchingTeam.teamName);
      }
    }

    if (teamNames.length == 2) {
      return '${teamNames[0]} vs ${teamNames[1]}';
    }

    if (_leagueLadder!.teams.length == 2) {
      return '${_leagueLadder!.teams[0].teamName} vs ${_leagueLadder!.teams[1].teamName}';
    }

    return null;
  }

  String? _comparisonTeamNames() {
    return _comparisonTeamNamesText ?? _comparisonTeamNamesFromLadder();
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
          case 7: // 'Byes'
            compareResult = a.byes.compareTo(b.byes);
            break;
          case 8: // 'For'
            compareResult = a.pointsFor.compareTo(b.pointsFor);
            break;
          case 9: // 'Agst'
            compareResult = a.pointsAgainst.compareTo(b.pointsAgainst);
            break;
          case 10: // '%'
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
    final String? comparisonTeamNames = _comparisonTeamNames();

    return Scaffold(
      // appBar: AppBar(...) removed
      body: SingleChildScrollView(
        child: Column(
          // Existing body wrapped in Column
          children: [
            // Step 1: Add HeaderWidget conditionally with improved styling for comparison mode
            orientation == Orientation.portrait
                ? _isComparisonMode
                      ? SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              16.0,
                              16.0,
                              16.0,
                              0.0,
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
                                      if (comparisonTeamNames != null)
                                        Text(
                                          comparisonTeamNames,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.grey[700],
                                                height: 1.0,
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
                          : "This is the current ${widget.league.name.toUpperCase()} premiership ladder for the regular season. Tap column headers to sort. Tap a row to see the team's game history. Colour shading indicates the top 8 teams.",
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
                ? _buildEmptyStateCard(context)
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
                              'Byes',
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
                                        child: _buildTeamLogo(ladderTeam),
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
                                  ladderTeam.byes.toString(),
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
              LeagueLadderHistoricalMatchups(
                league: widget.league,
                teamDbKeys: widget.teamDbKeysToDisplay!,
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

  Widget _buildEmptyStateCard(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: SizedBox(
          width: 320,
          child: Card(
            color: Colors.black38,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                _emptyMessage ?? 'No ladder data available.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamLogo(LadderTeam ladderTeam) {
    if (ladderTeam.logoURI != null &&
        ladderTeam.logoURI!.isNotEmpty &&
        !ladderTeam.logoURI!.contains('default_logo')) {
      return SvgPicture.asset(
        ladderTeam.logoURI!,
        width: 28,
        height: 28,
        placeholderBuilder: (BuildContext context) => Container(
          padding: const EdgeInsets.all(4.0),
          child: const CircularProgressIndicator(),
        ),
      );
    } else {
      // Return a placeholder widget
      return const Icon(Icons.shield, size: 28, color: Colors.grey);
    }
  }
}
