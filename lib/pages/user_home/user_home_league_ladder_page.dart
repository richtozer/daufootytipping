import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_historical.dart';
import 'package:daufootytipping/pages/user_home/user_home_team_games_history_page.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/ladder_empty_state_card.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';

class LeagueLadderPage extends StatefulWidget {
  final League league;
  final List<String>? teamDbKeysToDisplay; // Added optional parameter
  final String? customTitle; // Added optional parameter

  /// Hero tags to use for the given teams' logos, keyed by team dbkey. Set by
  /// a caller whose own logos are tagged differently -- a tips card tags its
  /// pair per game -- so the flight still pairs up. Teams not named here keep
  /// the ladder's own tag.
  final Map<String, String>? heroTags;

  const LeagueLadderPage({
    super.key,
    required this.league,
    this.teamDbKeysToDisplay, // Added to constructor
    this.customTitle, // Added to constructor
    this.heroTags,
  });

  @override
  State<LeagueLadderPage> createState() => _LeagueLadderPageState();
}

class _LeagueLadderPageState extends State<LeagueLadderPage> {
  LeagueLadder? _leagueLadder;
  bool _isLoading = true;
  String? _error;
  String? _emptyMessage;
  // The ladder arrives in rank order, so that is the sort the heading shows
  // from the start rather than leaving every column looking unsorted.
  int? _sortColumnIndex = 0;
  bool _sortAscending = true;
  String? _comparisonTeamNamesText;
  late final ValueListenable<int> _leagueLadderRevision;

  /// Rank and team name stay put: together they are the row's identity, and
  /// nine columns of numbers mean nothing without them.
  static const int _frozenLeading = 2;

  /// Spelled out: a narrow pane turns these on their side, where a single
  /// letter says nothing and "Agst" reads as a typo.
  ///
  /// '%' stays as it is. It is the one heading that needs no expanding, and
  /// "Percentage" is long enough on its own to rotate every other heading
  /// with it -- at tablet width it took the header from 48 to 113.
  static const _columns = [
    AppColumn.numeric('Rank', sortable: true, descendingFirst: false),
    AppColumn.text('Team', sortable: true),
    AppColumn.numeric('Games', sortable: true),
    AppColumn.numeric('Points', sortable: true),
    AppColumn.numeric('Won', sortable: true),
    AppColumn.numeric('Lost', sortable: true),
    AppColumn.numeric('Drawn', sortable: true),
    AppColumn.numeric('Byes', sortable: true),
    AppColumn.numeric('For', sortable: true),
    AppColumn.numeric('Against', sortable: true),
    AppColumn.numeric('%', sortable: true),
  ];

  /// The display order. Sorting used to reorder the ladder's own list, which
  /// for the unfiltered view is the one held in the cache.
  List<LadderTeam> _sortedTeams = const [];
  List<Object?> _renderedValues = const [];
  List<AppRow> _rows = const [];

  bool get _isComparisonMode =>
      widget.teamDbKeysToDisplay != null &&
      widget.teamDbKeysToDisplay!.length == 2;

  @override
  void initState() {
    super.initState();
    _leagueLadderRevision = di<DAUCompsViewModel>().leagueLadderRevision;
    _leagueLadderRevision.addListener(_leagueLadderUpdated);
    _fetchLadderData();
    _loadComparisonTeamNames();
  }

  void _leagueLadderUpdated() {
    _fetchLadderData();
  }

  @override
  void dispose() {
    _leagueLadderRevision.removeListener(_leagueLadderUpdated);
    super.dispose();
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
        _leagueLadder = calculatedLadder; // Use the ladder as is (either full or already null)
      }

      // Important: Check if mounted again before setState after async gap
      if (mounted) {
        setState(() {
          // _leagueLadder is already set above
          if (_leagueLadder == null &&
              ladderAvailability == LeagueLadderAvailability.insufficientData) {
            _emptyMessage = 'Standings will appear once Round 1 is complete.';
          } else {
            _emptyMessage = 'No ladder data available.';
          }
          _isLoading = false;
          _applySort();
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
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _applySort();
    });
  }

  /// Rebuilds the display order from the ladder, leaving the ladder alone.
  void _applySort() {
    final List<LadderTeam> teams = List<LadderTeam>.from(
      _leagueLadder?.teams ?? const <LadderTeam>[],
    );
    final int? column = _sortColumnIndex;
    if (column != null) {
      teams.sort((a, b) {
        final int comparison = _compareTeams(column, a, b);
        return ascendingOrder(comparison);
      });
    }
    _sortedTeams = teams;
  }

  int ascendingOrder(int comparison) =>
      _sortAscending ? comparison : -comparison;

  int _compareTeams(int columnIndex, LadderTeam a, LadderTeam b) {
    switch (columnIndex) {
      case 0:
        // The ladder's own position, which the row has carried since
        // originalRank was added. This used to sort by points and fall back
        // to percentage, reconstructing the rank from the figures behind it.
        const int unranked = 1 << 30;
        return (a.originalRank ?? unranked).compareTo(
          b.originalRank ?? unranked,
        );
      case 1:
        return a.teamName.compareTo(b.teamName);
      case 2:
        return a.played.compareTo(b.played);
      case 3:
        return a.points.compareTo(b.points);
      case 4:
        return a.won.compareTo(b.won);
      case 5:
        return a.lost.compareTo(b.lost);
      case 6:
        return a.drawn.compareTo(b.drawn);
      case 7:
        return a.byes.compareTo(b.byes);
      case 8:
        return a.pointsFor.compareTo(b.pointsFor);
      case 9:
        return a.pointsAgainst.compareTo(b.pointsAgainst);
      case 10:
        return a.percentage.compareTo(b.percentage);
      default:
        return 0;
    }
  }

  /// Preserves list identity through resize and rebuild so AppTable reuses
  /// its measurements.
  List<AppRow> _tableRows(
    BuildContext context,
    LeagueLadder ladder,
    int? seasonYear,
  ) {
    final values = <Object?>[
      seasonYear,
      Theme.of(context).brightness,
      for (final team in _sortedTeams) ...[
        team.dbkey,
        team.teamName,
        team.logoURI,
        team.originalRank,
        team.played,
        team.points,
        team.won,
        team.lost,
        team.drawn,
        team.byes,
        team.pointsFor,
        team.pointsAgainst,
        team.percentage,
      ],
    ];
    if (listEquals(_renderedValues, values)) return _rows;
    _renderedValues = values;
    _rows = [
      for (final team in _sortedTeams)
        _teamRow(context, ladder, team, seasonYear),
    ];
    return _rows;
  }

  AppRow _teamRow(
    BuildContext context,
    LeagueLadder ladder,
    LadderTeam ladderTeam,
    int? seasonYear,
  ) {
    final int? originalRank = ladderTeam.originalRank;
    final LeagueLadderHighlightBand highlightBand = originalRank == null
        ? LeagueLadderHighlightBand.none
        : ladder.highlightBandForRank(originalRank, seasonYear: seasonYear);
    final Team teamForHistory = Team(
      dbkey: ladderTeam.dbkey,
      name: ladderTeam.teamName,
      logoURI: ladderTeam.logoURI,
      league: widget.league,
    );
    final String heroTag =
        widget.heroTags?[ladderTeam.dbkey] ?? teamHeroTag(ladderTeam.dbkey);

    return AppRow(
      key: ValueKey(ladderTeam.dbkey),
      colour: _rowHighlightColor(context, highlightBand) ?? Colors.transparent,
      onTap: () => Navigator.push(
        context,
        appPageRoute(
          (context) => TeamGamesHistoryPage(
            team: teamForHistory,
            league: widget.league,
            // Whatever this row flew in as, it flies out as.
            heroTag: heroTag,
          ),
        ),
      ),
      cells: [
        AppCell.text(
          originalRank?.toString() ?? '-',
          leading: const Icon(
            Icons.arrow_forward,
            size: 16,
            color: Colors.grey,
          ),
          leadingSize: const Size(16, 16),
        ),
        AppCell.text(
          ladderTeam.teamName,
          leading: Hero(tag: heroTag, child: _buildTeamLogo(ladderTeam)),
          leadingSize: const Size(28, 28),
        ),
        AppCell.text(ladderTeam.played.toString()),
        AppCell.text(ladderTeam.points.toString()),
        AppCell.text(ladderTeam.won.toString()),
        AppCell.text(ladderTeam.lost.toString()),
        AppCell.text(ladderTeam.drawn.toString()),
        AppCell.text(ladderTeam.byes.toString()),
        AppCell.text(ladderTeam.pointsFor.toString()),
        AppCell.text(ladderTeam.pointsAgainst.toString()),
        AppCell.text(ladderTeam.percentage.toStringAsFixed(2)),
      ],
    );
  }

  int? _configuredSeasonYear() =>
      di<DAUCompsViewModel>().selectedDAUComp?.configuredSeasonYear();

  String _ladderColourExplanation(int? seasonYear) {
    if (widget.league == League.afl &&
        seasonYear != null &&
        seasonYear >= 2026) {
      return "Tap column headers to sort. Tap a row to see the team's game history. Colour shading indicates the Top 6 and wild card positions 7-10.";
    }
    return "Tap column headers to sort. Tap a row to see the team's game history. Colour shading indicates the top 8 teams.";
  }

  Color? _rowHighlightColor(
    BuildContext context,
    LeagueLadderHighlightBand highlightBand,
  ) {
    if (highlightBand == LeagueLadderHighlightBand.none) {
      return null;
    }

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (widget.league == League.nrl) {
      return isDarkMode ? Colors.lightGreen[900] : Colors.lightGreen[200];
    }

    if (widget.league == League.afl) {
      switch (highlightBand) {
        case LeagueLadderHighlightBand.finals:
          return isDarkMode ? const Color(0xFF5C1A1A) : Colors.red[100];
        case LeagueLadderHighlightBand.wildcard:
          return isDarkMode ? const Color(0xFF452626) : Colors.red[50];
        case LeagueLadderHighlightBand.none:
          return null;
      }
    }

    return null;
  }

  Widget _leagueLogo() => Hero(
    tag: "${widget.league.name.toLowerCase()}_league_logo_hero",
    child: SvgPicture.asset(
      widget.league == League.nrl ? 'assets/nrl.svg' : 'assets/afl.svg',
      width: 50,
      height: 50,
    ),
  );

  AppTableHeading _header(
    BuildContext context,
    String? comparisonTeamNames,
    int? seasonYear,
  ) {
    final bool filtered = widget.teamDbKeysToDisplay?.isNotEmpty ?? false;
    return AppTableHeading(
      leading: _leagueLogo(),
      // Short enough to sit beside two rows without hanging below them. The
      // teams are named underneath and the competition is named on the
      // banner, so the title had been saying both again.
      title: _isComparisonMode
          ? 'Ladder Comparison'
          : "${widget.league.name.toUpperCase()} Premiership Ladder",
      subtitle: _isComparisonMode ? comparisonTeamNames : null,
      description: filtered
          ? 'Tap a team for its full game history. Tap headings to sort.'
          : _ladderColourExplanation(seasonYear),
    );
  }

  /// The table, or whichever of loading, error and empty is standing in for it.
  Widget _ladderTable(BuildContext context, int? seasonYear) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? error = _error;
    if (error != null) {
      return Center(child: Text('Error: $error'));
    }
    final LeagueLadder? ladder = _leagueLadder;
    if (ladder == null || ladder.teams.isEmpty) {
      return _buildEmptyStateCard(context);
    }
    final int? sortColumn = _sortColumnIndex;
    return AppTable(
      columns: _columns,
      rows: _tableRows(context, ladder, seasonYear),
      frozenLeading: _frozenLeading,
      sort: sortColumn == null
          ? null
          : AppSort(column: sortColumn, ascending: _sortAscending),
      onSort: _onSort,
    );
  }

  /// Bounds a table to the height its own rows need.
  ///
  /// The comparison view stacks the ladder above the historical matchups, so
  /// the page scrolls and the table has no viewport of its own to fill --
  /// but AppTable needs a bounded height either way. Measuring is what gives
  /// an exact fit at any text scale; the two teams it holds make it cheap.
  Widget _sizedToRows(List<AppRow> rows, Widget table) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final TextStyle body =
            Theme.of(context).textTheme.bodyMedium ??
            const TextStyle(fontSize: 14);
        final AppTableLayout layout = AppTableLayout.measure(
          columns: _columns,
          rows: rows,
          width: constraints.maxWidth,
          textScaler: MediaQuery.textScalerOf(context),
          headingStyle: body.copyWith(fontWeight: FontWeight.w600),
          cellStyle: body,
          direction: Directionality.of(context),
          frozenLeading: _frozenLeading,
        );
        return SizedBox(
          height:
              layout.headerHeight +
              layout.rowHeight * rows.length +
              (layout.scrollsHorizontally ? AppTableLayout.scrollbarLane : 0),
          child: table,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? comparisonTeamNames = _comparisonTeamNames();
    final int? seasonYear = _configuredSeasonYear();
    final List<String> comparedTeams =
        widget.teamDbKeysToDisplay ?? const <String>[];
    final Widget table = _ladderTable(context, seasonYear);

    return SelectedCompBanner(
      child: Scaffold(
        body: SafeArea(
          child: _isComparisonMode
              // Two sections, each with its heading beside its own table
              // rather than one heading at the top speaking for both.
              ? SingleChildScrollView(
                  child: Column(
                    children: [
                      AppTableFrame(
                        fill: false,
                        columns: _columns,
                        rows: _rows,
                        frozenLeading: _frozenLeading,
                        heading: _header(
                          context,
                          comparisonTeamNames,
                          seasonYear,
                        ),
                        table: Padding(
                          padding: const EdgeInsets.all(5.0),
                          child: _rows.isEmpty
                              ? table
                              : _sizedToRows(_rows, table),
                        ),
                      ),
                      const Divider(
                        height: 24,
                        thickness: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      LeagueLadderHistoricalMatchups(
                        league: widget.league,
                        teamDbKeys: comparedTeams,
                      ),
                    ],
                  ),
                )
              // The whole ladder: one table, filling the page, as every other
              // table page does.
              : AppTableFrame(
                  columns: _columns,
                  rows: _rows,
                  frozenLeading: _frozenLeading,
                  heading: _header(context, comparisonTeamNames, seasonYear),
                  table: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: table,
                  ),
                ),
        ),
        floatingActionButton: FloatingActionButton.small(
          onPressed: () => Navigator.pop(context),
          backgroundColor: Colors.lightGreen[200],
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: const Icon(Icons.arrow_back),
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard(BuildContext context) {
    return LadderEmptyStateCard(
      message: _emptyMessage ?? 'No ladder data is available yet.',
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
