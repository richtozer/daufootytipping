import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
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

  Future<void> _saveDAUComp(
      BuildContext context, DAUCompsViewModel model) async {
    try {
      //create a new temp DAUComp object to pass the changes to the viewmodel
      DAUComp daucompEdited = DAUComp(
        name: _daucompNameController.text,
        dbkey: daucomp?.dbkey,
        aflFixtureJsonURL: Uri.parse(_daucompAflJsonURLController
            .text), //TODO  https://fixturedownload.com/feed/json/afl-2023
        nrlFixtureJsonURL: Uri.parse(_daucompNrlJsonURLController
            .text), // TODO 'https://fixturedownload.com/feed/json/nrl-2023')
      );

      if (daucomp != null) {
        await model.editDAUComp(daucompEdited);
      } else {
        await model.addDAUComp(daucompEdited);
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
              Consumer<DAUCompsViewModel>(
                  builder: (context, daucompViewModel, child) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: ElevatedButton(
                        onPressed:
                            // swallow any double presses of Save button
                            // if the saving flag is set
                            daucompViewModel.savingDAUComp
                                ? null
                                : () async {
                                    // Validate will return true if the form is valid, or false if
                                    // the form is invalid.
                                    final isValid =
                                        _formKey.currentState!.validate();
                                    if (isValid) {
                                      disableBackButton = true;
                                      await _saveDAUComp(
                                          context, daucompViewModel);
                                      disableBackButton = false;
                                    }
                                  },
                        child: daucomp == null
                            ? const Text('Add')
                            : const Text('Save'),
                      ),
                    ),
                    if (daucompViewModel.savingDAUComp) ...const <Widget>[
                      SizedBox(height: 32),
                      CircularProgressIndicator(),
                    ]
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
