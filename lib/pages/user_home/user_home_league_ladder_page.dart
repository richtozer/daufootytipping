import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/services/ladder_calculation_service.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';

class LeagueLadderPage extends StatefulWidget {
  final League league;

  const LeagueLadderPage({
    super.key,
    required this.league,
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

  @override
  void initState() {
    super.initState();
    _fetchLadderData();
  }

  Future<void> _fetchLadderData() async {
    try {
      final dauCompsViewModel = di<DAUCompsViewModel>();
      if (dauCompsViewModel.selectedDAUComp == null) {
        setState(() {
          _error = "No competition selected. Cannot fetch games.";
          _isLoading = false;
        });
        return;
      }

      final gamesViewModel = di<DAUCompsViewModel>().gamesViewModel;
      await gamesViewModel!.initialLoadComplete;

      final teamsViewModel = gamesViewModel.teamsViewModel;
      await teamsViewModel.initialLoadComplete;

      final ladderService = LadderCalculationService();

      List<Game> allGames = await gamesViewModel.getGames();
      List<Team> leagueTeams = teamsViewModel
              .groupedTeams[widget.league.name.toLowerCase()]
              ?.cast<Team>() ??
          [];

      final calculatedLadder = ladderService.calculateLadder(
        allGames: allGames,
        leagueTeams: leagueTeams,
        league: widget.league,
      );

      setState(() {
        _leagueLadder = calculatedLadder;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to load ladder: ${e.toString()}";
        _isLoading = false;
      });
    }
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
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.league.name.toUpperCase()} Premiership Ladder'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _leagueLadder == null || _leagueLadder!.teams.isEmpty
                  ? const Center(child: Text('No ladder data available.'))
                  : SingleChildScrollView( // Outer, Vertical scroll
                    child: SingleChildScrollView( // Inner, Horizontal scroll
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: DataTable(
                        border: TableBorder.all(width: 1.0, color: Colors.grey.shade300),
                        columnSpacing: 10.0,
                        horizontalMargin: 8.0,
                        headingRowHeight: 36.0,
                        sortColumnIndex: _sortColumnIndex,
                        sortAscending: _sortAscending,
                        columns: <DataColumn>[
                          DataColumn(
                              label: const Text('#',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('Team',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('Gms',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('Pts',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('W',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('L',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('D',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('For',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('Agst',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                          DataColumn(
                              label: const Text('%',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              onSort: (int columnIndex, bool ascending) => _onSort(columnIndex, ascending)),
                        ],
                        rows: List<DataRow>.generate(
                          _leagueLadder!.teams.length,
                          (index) {
                            final team = _leagueLadder!.teams[index];
                            final isTop8 = index < 8; // Top 8 teams

                            return DataRow(
                              color: MaterialStateProperty.resolveWith<Color?>(
                                (Set<MaterialState> states) {
                                  if (isTop8 && widget.league == League.afl) {
                                    return League.afl.colour.brighten(
                                        75); // Highlight color for top 8
                                  }
                                  if (isTop8 && widget.league == League.nrl) {
                                    return League.nrl.colour.brighten(
                                        75); // Highlight color for top 8
                                  }
                                  return null; // Default row color
                                },
                              ),
                              cells: <DataCell>[
                                DataCell(Text(LeagueLadder.ordinal(index + 1))),
                                DataCell(Row(
                                  children: [
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 6.0),
                                      child: SvgPicture.asset(
                                        team.logoURI ??
                                            'assets/images/default_logo.svg',
                                        width: 28,
                                        height: 28,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        team.teamName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )),
                                DataCell(Text(team.played.toString(), textAlign: TextAlign.right)),
                                DataCell(Text(team.points.toString(), textAlign: TextAlign.right)),
                                DataCell(Text(team.won.toString(), textAlign: TextAlign.right)),
                                DataCell(Text(team.lost.toString(), textAlign: TextAlign.right)),
                                DataCell(Text(team.drawn.toString(), textAlign: TextAlign.right)),
                                DataCell(Text(team.pointsFor.toString(), textAlign: TextAlign.right)),
                                DataCell(Text(team.pointsAgainst.toString(), textAlign: TextAlign.right)),
                                DataCell(
                                    Text(team.percentage.toStringAsFixed(2), textAlign: TextAlign.right)),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
    );
  }
}
