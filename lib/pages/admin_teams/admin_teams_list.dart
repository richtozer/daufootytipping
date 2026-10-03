import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_edit.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_bottom_aligned_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

class TeamsListPage extends StatelessWidget {
  final TeamsViewModel teamsViewModel;

  const TeamsListPage({super.key, required this.teamsViewModel});

  Future<void> _editTeam(
    Team team,
    TeamsViewModel teamsViewModel,
    BuildContext context,
  ) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamEditPage(team, teamsViewModel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: teamsViewModel,
      child: Consumer<TeamsViewModel>(
        builder: (context, teamsViewModelConsumer, child) {
          final groupedTeams = teamsViewModelConsumer.groupedTeams;
          return AppAdminPage(
            title: 'Admin Teams',
            body: Padding(
              padding: const EdgeInsets.all(8.0),
              // Rows sit at the bottom, within thumb reach.
              child: AppBottomAlignedScroll(
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      for (final entry in groupedTeams.entries) ...[
                        Text(
                          entry.key.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        for (final team in entry.value as List<Team>)
                          ListTile(
                            dense: true,
                            leading: team.logoURI != null
                                ? SvgPicture.asset(
                                    team.logoURI!,
                                    width: 30,
                                    height: 30,
                                  )
                                : null,
                            trailing: const Icon(Icons.edit),
                            title: Text(team.name),
                            onTap: () async {
                              // Trigger edit functionality
                              await _editTeam(team, teamsViewModel, context);
                            },
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
