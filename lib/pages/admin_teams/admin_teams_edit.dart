import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// this class only supports updating Team records. for referencial
// integrity reasons, we do not allow teams to be deleted

class TeamEditPage extends StatefulWidget {
  final TeamsViewModel teamsViewModel;
  final Team team;

  const TeamEditPage(this.team, this.teamsViewModel, {super.key});

  @override
  State<TeamEditPage> createState() => _TeamEditPageState();
}

class _TeamEditPageState extends State<TeamEditPage> {
  late Team team;

  late TextEditingController _teamNameController;
  late TextEditingController _teamLogoURIController;

  late bool disableBackButton = false;
  late bool disableSaves = true;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    team = widget.team;
    _teamNameController = TextEditingController(text: team.name);
    _teamLogoURIController = TextEditingController(text: team.logoURI);
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    super.dispose();
  }

  void _saveTeam(BuildContext context, Team oldTeam) async {
    try {
      //create a new temp team object to pass the changes to the viewmodel
      Team teamEdited = Team(
          name: _teamNameController.text,
          dbkey: oldTeam.dbkey,
          league: oldTeam.league,
          logoURI: _teamLogoURIController.text);

      widget.teamsViewModel.editTeam(teamEdited);

      // navigate to the previous page
      if (context.mounted) Navigator.of(context).pop(true);
      //}
    } on Exception {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            content: const Text('Failed to update the team record'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              )
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: disableBackButton
                  ? const ImageIcon(
                      null) // dont show anything clickable while saving is in progress
                  : const Icon(Icons.arrow_back),
              onPressed: disableBackButton
                  ? null
                  : () {
                      Navigator.maybePop(context);
                    },
            );
          },
        ),
        actions: <Widget>[
          Builder(
            builder: (BuildContext context) {
              return ChangeNotifierProvider<TeamsViewModel>(
                  //TODO this may not be used and can be removed
                  create: (context) => TeamsViewModel(),
                  builder: (context, child) {
                    return IconButton(
                      icon: disableSaves
                          ? const Icon(Icons.hourglass_bottom)
                          : const Icon(Icons.save),
                      onPressed: disableSaves
                          ? null
                          : () async {
                              // Validate will return true if the form is valid, or false if
                              // the form is invalid.
                              final isValid = _formKey.currentState!.validate();
                              if (isValid) {
                                setState(() {
                                  disableSaves = true;
                                });
                                disableBackButton = true;
                                _saveTeam(context, team);
                                setState(() {
                                  disableSaves = false;
                                });
                              }
                            },
                    );
                  });
            },
          ),
        ],
        title: const Text('Edit Team'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: [
                  const Text('Name:'),
                  Expanded(
                    child: TextFormField(
                      enabled: !disableBackButton,
                      controller: _teamNameController,
                      onChanged: (String value) {
                        if (team.name != value) {
                          //something has changed, allow saves
                          setState(() {
                            disableSaves = false;
                          });
                        } else {
                          setState(() {
                            disableSaves = true;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        hintText: 'Team name',
                      ),
                      onFieldSubmitted: (_) {
                        // TODO move focus to next field?
                      },
                      validator: (String? value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a team name';
                        }
                        return null;
                      },
                    ),
                  )
                ],
              ),
              Row(
                children: [
                  const Text('Logo:'),
                  Expanded(
                    child: TextFormField(
                      enabled: !disableBackButton,
                      controller: _teamLogoURIController,
                      onChanged: (String value) {
                        if (team.logoURI != value) {
                          //something has changed, allow saves
                          setState(() {
                            disableSaves = false;
                          });
                        } else {
                          setState(() {
                            disableSaves = true;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        hintText: 'Logo',
                      ),
                      onFieldSubmitted: (_) {
                        // TODO move focus to next field?
                      },
                      validator: (String? value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a team logo link';
                        }
                        return null;
                      },
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
