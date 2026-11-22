import 'dart:async';

import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_edit.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:daufootytipping/widgets/team_logo.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// Every club in /Teams, for an admin to rename or give a logo.
///
/// Finals placeholders such as "1st" or "Winner of QF1" are teams too, as the
/// fixture lists finals before anyone qualifies. The list leaves out any team
/// that plays in no more than one round of every comp.
class TeamsListPage extends StatefulWidget {
  const TeamsListPage({super.key});

  @override
  State<TeamsListPage> createState() => _TeamsListPageState();
}

class _TeamsListPageState extends State<TeamsListPage> {
  static const _columns = [
    AppColumn.text('Team', sortable: true),
    AppColumn.text('League', sortable: true),
    AppColumn.navigation(),
  ];
  static const double _logoSize = 30;

  final TeamsViewModel _teamsViewModel = di<TeamsViewModel>();
  final TeamLogosViewModel _logos = di<TeamLogosViewModel>();

  /// Grouped by league, as the list always was, until a heading is tapped.
  int _sortColumn = 1;
  bool _ascending = true;
  final Set<League> _leagues = {League.nrl, League.afl};
  bool _noLogoOnly = false;

  /// Teams that play in two or more rounds of some comp. Empty until counted,
  /// and every team shows while it is.
  Set<String> _seasonTeamKeys = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_countSeasonTeams());
  }

  Future<void> _countSeasonTeams() async {
    final games = di<DAUCompsViewModel>().gamesViewModel;
    if (games == null) return;
    final keys = await games.teamKeysInSeveralRoundsOfAnyComp();
    if (mounted) setState(() => _seasonTeamKeys = keys);
  }

  Future<void> _editTeam(Team team) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamEditPage(team, _teamsViewModel),
      ),
    );
  }

  List<Team> _sorted(List<Team> teams) {
    int byName(Team a, Team b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    final sorted = [...teams]
      ..sort((a, b) {
        final primary = _sortColumn == 1
            ? a.league.name.compareTo(b.league.name)
            : byName(a, b);
        final ordered = primary != 0 ? primary : byName(a, b);
        return _ascending ? ordered : -ordered;
      });
    return sorted;
  }

  List<AppRow> _rows(List<Team> teams) => [
    for (final team in _sorted(teams))
      AppRow(
        key: ValueKey(team.dbkey),
        onTap: () => _editTeam(team),
        cells: [
          AppCell.text(
            team.name,
            leadingSize: const Size.square(_logoSize),
            leading: TeamLogo(
              teamDbKey: team.dbkey,
              teamName: team.name,
              size: _logoSize,
            ),
          ),
          AppCell.text(team.league.name.toUpperCase()),
          AppCell.navigation(),
        ],
      ),
  ];

  void _onSort(int column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _ascending = ascending;
    });
  }

  /// The toggles above the table, with how many teams they let through.
  Widget _filterRow({required int shown, required int total}) {
    FilterChip chip(String label, bool selected, ValueChanged<bool> onTap) =>
        FilterChip(label: Text(label), selected: selected, onSelected: onTap);
    void toggleLeague(League league, bool on) =>
        setState(() => on ? _leagues.add(league) : _leagues.remove(league));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final league in [League.nrl, League.afl])
                  chip(
                    league.name.toUpperCase(),
                    _leagues.contains(league),
                    (on) => toggleLeague(league, on),
                  ),
                chip(
                  'No logo',
                  _noLogoOnly,
                  (on) => setState(() => _noLogoOnly = on),
                ),
              ],
            ),
          ),
          Text('$shown of $total'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppAdminPage(
      title: 'Admin Teams',
      scrollsUnderControls: true,
      body: Padding(
        padding: appAdminBodyPadding(context),
        child: ListenableBuilder(
          listenable: Listenable.merge([_teamsViewModel, _logos]),
          builder: (context, _) {
            final seasonTeams = [
              for (final team in _teamsViewModel.teams)
                if (_seasonTeamKeys.isEmpty ||
                    _seasonTeamKeys.contains(team.dbkey))
                  team,
            ];
            final shown = [
              for (final team in seasonTeams)
                if (_leagues.contains(team.league) &&
                    (!_noLogoOnly || _logos.svgFor(team.dbkey) == null))
                  team,
            ];
            return Column(
              children: [
                _filterRow(shown: shown.length, total: seasonTeams.length),
                Expanded(
                  child: AppTable(
                    columns: _columns,
                    rows: _rows(shown),
                    sort: AppSort(column: _sortColumn, ascending: _ascending),
                    onSort: _onSort,
                    empty: const Center(child: Text('No teams')),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
