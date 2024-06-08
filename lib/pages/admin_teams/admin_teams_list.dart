import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_edit.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';

class TeamsListPage extends StatelessWidget with WatchItMixin {
  const TeamsListPage({super.key});

  Future<void> _editTeam(
      Team team, TeamsViewModel teamsViewModel, BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamEditPage(team, teamsViewModel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TeamsViewModel teamsViewModel = watchIt<TeamsViewModel>();
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: const Text('Admin Teams'),
        ),
        body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ListView.builder(
              itemCount: teamsViewModel.groupedTeams.length,
              itemBuilder: (BuildContext context, int index) {
                String league =
                    teamsViewModel.groupedTeams.keys.elementAt(index);
                List itemsInCategory = teamsViewModel.groupedTeams[league]!;

                // Return a widget representing the category and its items
                return Column(
                  children: [
                    Text(league.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: itemsInCategory.length,
                      itemBuilder: (BuildContext context, int index) {
                        Team team = itemsInCategory[index];
                        // Return a widget representing the item
                        return ListTile(
                          dense: true,
                          leading: team.logoURI != null
                              ? SvgPicture.asset(team.logoURI!,
                                  width: 30, height: 30)
                              : null,
                          trailing: const Icon(Icons.edit),
                          title: Text(team.name),
                          onTap: () async {
                            // Trigger edit functionality
                            await _editTeam(team, teamsViewModel, context);
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            )));
  }
}
