import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/team_logo_validator.dart';
import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/team_logo.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

// this class only supports updating Team records. for referential
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

  late bool disableBackButton = false;
  late bool disableSaves = true;
  late bool isSaving = false;
  bool _isUploadingLogo = false;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    team = widget.team;
    _teamNameController = TextEditingController(text: team.name);
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    super.dispose();
  }

  void _saveTeam(BuildContext context, Team oldTeam) async {
    setState(() {
      isSaving = true;
      disableBackButton = true;
    });

    try {
      //create a new temp team object to pass the changes to the viewmodel
      Team teamEdited = Team(
        name: _teamNameController.text,
        dbkey: oldTeam.dbkey,
        league: oldTeam.league,
      );

      await widget.teamsViewModel.editTeam(teamEdited);

      // navigate to the previous page
      if (context.mounted) Navigator.of(context).pop(true);
    } on Exception {
      setState(() {
        isSaving = false;
        disableBackButton = false;
      });

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
              ),
            ],
          ),
        );
      }
    }
  }

  /// Picks an SVG, checks it and stores it as this team's logo. The logo
  /// preview updates when the `/TeamLogos` listener receives the change.
  Future<void> _uploadLogo() async {
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: 'Choose the ${team.name} logo',
      type: FileType.custom,
      allowedExtensions: const ['svg'],
    );
    if (file == null || !mounted) return;

    setState(() => _isUploadingLogo = true);
    String message;
    try {
      final String svg = await validateTeamLogo(await file.readAsBytes());
      await di<TeamLogosViewModel>().saveLogo(teamDbKey: team.dbkey, svg: svg);
      message = 'Logo updated for ${team.name}.';
    } on TeamLogoRejected catch (rejection) {
      message = rejection.message;
    } on Exception {
      message = 'The logo could not be saved.';
    }
    if (!mounted) return;
    setState(() => _isUploadingLogo = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Back is the floating control's maybePop, so a save in progress holds the
    // page here the same way it held the old back button.
    return PopScope(
      canPop: !disableBackButton,
      child: AppAdminPage(
        title: 'Edit Team',
        actions: [
          AppGlassAction(
            icon: isSaving
                ? Icons.hourglass_bottom
                : disableSaves
                ? Icons.save_outlined
                : Icons.save,
            label: 'Save',
            onPressed: (disableSaves || isSaving)
                ? null
                : () async {
                    // Validate will return true if the form is valid, or false
                    // if the form is invalid.
                    final isValid = _formKey.currentState!.validate();
                    if (isValid) {
                      _saveTeam(context, team);
                    }
                  },
          ),
        ],
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
                          FocusScope.of(context).nextFocus();
                        },
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a team name';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      const Text('Logo:'),
                      const SizedBox(width: 12),
                      TeamLogo(
                        teamDbKey: team.dbkey,
                        teamName: team.name,
                        size: 48,
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: (_isUploadingLogo || disableBackButton)
                            ? null
                            : _uploadLogo,
                        icon: _isUploadingLogo
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file),
                        label: const Text('Upload logo'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
