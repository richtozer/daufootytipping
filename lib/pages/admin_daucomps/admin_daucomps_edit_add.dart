import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// this class supports both creating and updating DAUComp records.
// it has 2 modes, then daucomp is null it is in new record mode,
// when it is not null it is in edit record mode
class DAUCompsAdminEditPage extends StatefulWidget {
  static const String route = '/AdminDAUCompsEdit';

  final DAUComp?
      daucomp; //if this is an edit for a new comp, this will stay null

  const DAUCompsAdminEditPage(this.daucomp, {super.key});

  @override
  State<DAUCompsAdminEditPage> createState() => _FormEditDAUCompsState();
}

class _FormEditDAUCompsState extends State<DAUCompsAdminEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _daucompNameController;
  late TextEditingController _daucompAflJsonURLController;
  late TextEditingController _daucompNrlJsonURLController;
  late DAUComp? daucomp;
  late bool disableBackButton = false;

  //todo add the saving logic, icons to this add/edit page

  @override
  void initState() {
    super.initState();
    daucomp = widget.daucomp;
    _daucompNameController = TextEditingController(text: daucomp?.name);
    _daucompAflJsonURLController =
        TextEditingController(text: daucomp?.aflFixtureJsonURL.toString());
    _daucompNrlJsonURLController =
        TextEditingController(text: daucomp?.nrlFixtureJsonURL.toString());
  }

  @override
  void dispose() {
    _daucompNameController.dispose();
    super.dispose();
  }

  Future<void> _saveDAUComp(BuildContext context, DAUCompsViewModel model,
      TeamsViewModel teamsViewModel) async {
    try {
      //create a new temp DAUComp object to pass the changes to the viewmodel
      DAUComp daucompEdited = DAUComp(
        name: _daucompNameController.text,
        dbkey: daucomp?.dbkey,
        aflFixtureJsonURL: Uri.parse(_daucompAflJsonURLController.text),
        nrlFixtureJsonURL: Uri.parse(_daucompNrlJsonURLController.text),
      );

      if (daucomp != null) {
        await model.editDAUComp(daucompEdited, teamsViewModel);
      } else {
        await model.addDAUComp(daucompEdited, teamsViewModel);
      }

      // navigate to the previous page
      if (context.mounted) Navigator.of(context).pop(true);
      //}
    } on Exception {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            content: daucomp != null
                ? const Text('Failed to update the DAU Comp record')
                : const Text('Failed to create a new DAU Comp record'),
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
                  ? const Icon(Icons.hourglass_bottom)
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
              return IconButton(
                icon: disableBackButton
                    ? const Icon(Icons.hourglass_bottom)
                    : const Icon(Icons.save),
                onPressed: disableBackButton
                    ? null
                    : () async {
                        // Validate will return true if the form is valid, or false if
                        // the form is invalid.
                        final isValid = _formKey.currentState!.validate();
                        if (isValid) {
                          disableBackButton = true;
                          await _saveDAUComp(
                              context,
                              Provider.of<DAUCompsViewModel>(context,
                                  listen: false),
                              Provider.of<TeamsViewModel>(context,
                                  listen: false));
                          disableBackButton = false;
                        }
                      },
              );
            },
          ),
        ],
        title: daucomp == null
            ? const Text('New DAU Comp')
            : const Text('Edit DAU Comp'),
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
                      controller: _daucompNameController,
                      decoration: const InputDecoration(
                        hintText: 'DAU Comp name',
                      ),
                      onFieldSubmitted: (_) {
                        // TODO move focus to next field?
                      },
                      validator: (String? value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a DAUComp name';
                        }
                        return null;
                      },
                    ),
                  )
                ],
              ),
              Row(
                children: [
                  const Text('AFL Fixture JSON URL:'),
                  Expanded(
                    child: TextFormField(
                        enableInteractiveSelection: true,
                        controller: _daucompAflJsonURLController,
                        decoration: const InputDecoration(
                          hintText: 'enter URL here',
                        ),
                        onFieldSubmitted: (_) {
                          // TODO move focus to next field?
                        },
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a URL';
                          }

                          if (Uri.parse(value).isAbsolute) {
                            return null;
                          } else {
                            return 'Enter a valid URL';
                          }
                        }),
                  )
                ],
              ),
              Row(
                children: [
                  const Text('NRL Fixture JSON URL:'),
                  Expanded(
                    child: TextFormField(
                        enableInteractiveSelection: true,
                        controller: _daucompNrlJsonURLController,
                        decoration: const InputDecoration(
                          hintText: 'DAU Comp name',
                        ),
                        onFieldSubmitted: (_) {
                          // TODO move focus to next field?
                        },
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a URL';
                          }

                          if (Uri.parse(value).isAbsolute) {
                            return null;
                          } else {
                            return 'Enter a valid URL';
                          }
                        }),
                  )
                ],
              ),
              const Card(
                child: ListTile(
                    title: Text('Games'), trailing: Icon(Icons.arrow_forward)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
