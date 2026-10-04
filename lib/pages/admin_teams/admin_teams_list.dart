import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_edit.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

class TeamsListPage extends StatefulWidget {
  final TeamsViewModel teamsViewModel;

  const TeamsListPage({super.key, required this.teamsViewModel});

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

  /// Grouped by league, as the list always was, until a heading is tapped.
  int _sortColumn = 1;
  bool _ascending = true;

  Future<void> _editTeam(Team team) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamEditPage(team, widget.teamsViewModel),
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
            leading: team.logoURI != null
                ? SvgPicture.asset(
                    team.logoURI!,
                    width: _logoSize,
                    height: _logoSize,
                  )
                : const SizedBox.square(dimension: _logoSize),
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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.teamsViewModel,
      child: Consumer<TeamsViewModel>(
        builder: (context, teamsViewModelConsumer, child) {
          return AppAdminPage(
            title: 'Admin Teams',
            scrollsUnderControls: true,
            body: Padding(
              padding: const EdgeInsets.all(8.0),
              child: AppTable(
                columns: _columns,
                rows: _rows(teamsViewModelConsumer.teams),
                sort: AppSort(column: _sortColumn, ascending: _ascending),
                onSort: _onSort,
                empty: const Center(child: Text('No teams')),
              ),
            ),
          );
        },
      ),
    );
  }
}
