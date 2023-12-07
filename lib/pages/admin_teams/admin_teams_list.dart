import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_edit.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TeamsListPage extends StatelessWidget {
  static const String route = '/AdminTeams';

  const TeamsListPage({super.key});

  Future<void> _editTeam(Team team, BuildContext context) async {
    await Navigator.of(context).pushNamed(TeamEditPage.route, arguments: team);
  }

  @override
  Widget build(BuildContext context) {
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
        body: ChangeNotifierProvider<TeamsViewModel>(
            create: (context) => TeamsViewModel(),
            child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Consumer<TeamsViewModel>(
                    builder: (context, teamsViewModel, child) {
                  return ListView.builder(
                    itemCount: teamsViewModel.groupedTeams.length,
                    itemBuilder: (BuildContext context, int index) {
                      String league =
                          teamsViewModel.groupedTeams.keys.elementAt(index);
                      List itemsInCategory =
                          teamsViewModel.groupedTeams[league]!;

                      // Return a widget representing the category and its items
                      return Column(
                        children: [
                          Text(league.toUpperCase(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: itemsInCategory.length,
                            itemBuilder: (BuildContext context, int index) {
                              Team team = itemsInCategory[index];
                              // Return a widget representing the item
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.ballot),
                                trailing: const Icon(Icons.edit),
                                title: Text(team.name),
                                onTap: () async {
                                  // Trigger edit functionality
                                  await _editTeam(team, context);
                                },
                              );
                            },
                          ),
                        ],
                      );
                    },
                  );
                }))));
  }
}
