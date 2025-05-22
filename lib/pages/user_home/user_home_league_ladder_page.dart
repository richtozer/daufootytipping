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
                  : SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 10.0,
                        horizontalMargin: 8.0,
                        headingRowHeight: 36.0,
                        columns: const <DataColumn>[
                          DataColumn(
                              label: Text('#',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Team',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Gms',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Pts',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('W',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('L',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('D',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('For',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Agst',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('%',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
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
                                DataCell(Text(team.played.toString())),
                                DataCell(Text(team.points.toString())),
                                DataCell(Text(team.won.toString())),
                                DataCell(Text(team.lost.toString())),
                                DataCell(Text(team.drawn.toString())),
                                DataCell(Text(team.pointsFor.toString())),
                                DataCell(Text(team.pointsAgainst.toString())),
                                DataCell(
                                    Text(team.percentage.toStringAsFixed(2))),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
    );
  }
}
