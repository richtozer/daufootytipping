import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:watch_it/watch_it.dart';

// this class supports both creating and updating DAUComp records.
// it has 2 modes, then daucomp is null it is in new record mode,
// when it is not null it is in edit record mode
class DAUCompsEditPage extends StatelessWidget with WatchItMixin {
  final DAUComp?
      daucomp; //if this is an edit for a new comp, this will stay null
  //final DAUCompsViewModel dauCompViewModel;

  late final TextEditingController _daucompNameController;
  late final TextEditingController _daucompAflJsonURLController;
  late final TextEditingController _daucompNrlJsonURLController;

  bool disableBackButton = false;
  bool disableSaves = false;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  //constructor
  DAUCompsEditPage(this.daucomp, {super.key}) {
    _daucompNameController = TextEditingController(text: daucomp?.name);
    _daucompAflJsonURLController =
        TextEditingController(text: daucomp?.aflFixtureJsonURL.toString());
    _daucompNrlJsonURLController =
        TextEditingController(text: daucomp?.nrlFixtureJsonURL.toString());
  }

  void _saveDAUComp(
      DAUCompsViewModel dauCompsViewModel, BuildContext context) async {
    try {
      //check the URL's are active on the server,
      //if yes, save the record and show a green snackbar saying the record is saved
      //if no, reject the save and show a red snackbar saying the URL's are not active
      if (await isUriActive(_daucompAflJsonURLController.text, context) &&
          await isUriActive(_daucompNrlJsonURLController.text, context)) {
        //create a new temp daucomp record to hold changes

        if (daucomp == null) {
          // this is a new record
          DAUComp updatedDUAcomp = DAUComp(
            dbkey: daucomp?.dbkey,
            name: _daucompNameController.text,
            aflFixtureJsonURL: Uri.parse(_daucompAflJsonURLController.text),
            nrlFixtureJsonURL: Uri.parse(_daucompNrlJsonURLController.text),
          );

          await dauCompsViewModel.newDAUComp(updatedDUAcomp);
        } else {
          // this is an existing record
          await dauCompsViewModel.updateCompAttribute(
              daucomp, "name", _daucompNameController.text);
          await dauCompsViewModel.updateCompAttribute(
              daucomp, "aflFixtureJsonURL", _daucompAflJsonURLController.text);
          await dauCompsViewModel.updateCompAttribute(
              daucomp, "nrlFixtureJsonURL", _daucompNrlJsonURLController.text);
        }

        await dauCompsViewModel.saveBatchOfCompAttributes();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('DAUComp record saved'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('One or both of the URL\'s are not active'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on Exception {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            content: const Text('Failed to update the DAU Comp record'),
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

  Future<bool> isUriActive(String uri, BuildContext context) async {
    try {
      final response = await http.get(Uri.parse(uri));
      if (response.statusCode == 200) {
        return true;
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('URL not valid, status code: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        log('Error checking URL: $uri, status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('URL not valid, error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        log('Error checking URL: $uri, exception: $e');
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    DAUCompsViewModel dauCompsViewModel = watchIt<DAUCompsViewModel>();

    if (daucomp == null) {
      // this is a new record, so disable the save button until the user has entered some data
      disableSaves = true;
    }
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
                return IconButton(
                  icon: !disableSaves
                      ? const Icon(Icons.save)
                      : const SizedBox.shrink(),
                  onPressed: disableSaves
                      ? null
                      : () async {
                          // Validate will return true if the form is valid, or false if
                          // the form is invalid.
                          final isValid = _formKey.currentState!.validate();
                          if (isValid) {
                            // disable the save and back button while the save is in progress
                            disableSaves = true;
                            disableBackButton = true;

                            // save the record
                            _saveDAUComp(dauCompsViewModel, context);
                            // re-enable the save and back button

                            disableBackButton = false;
                            disableSaves = false;
                          }
                        },
                );
              },
            ),
          ],
          title: const Text('Edit DAU Comp'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // add a row with a sync button download fixture data from the URL's
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    buttonFixture(context, dauCompsViewModel),
                    buttonLegacy(context, dauCompsViewModel),
                    buttonScoring(context, dauCompsViewModel),
                  ],
                ),
                const Text('Name:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        enabled: !disableBackButton,
                        controller: _daucompNameController,
                        onChanged: (String value) {
                          if (daucomp?.name != value) {
                            //something has changed, allow saves

                            disableSaves = false;
                          } else {
                            disableSaves = true;
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: 'DAU Comp name',
                        ),
                        onFieldSubmitted: (_) {
                          // TODO move focus to next field?
                        },
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a DAU Comp name';
                          }
                          return null;
                        },
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 20.0),
                const Text('Fixture JSON URLs',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20.0),
                const Text('NRL:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        enabled: !disableBackButton,
                        decoration: const InputDecoration(
                          hintText: 'enter URL here',
                        ),
                        controller: _daucompNrlJsonURLController,
                        onChanged: (String value) {
                          if (daucomp?.nrlFixtureJsonURL.toString() != value) {
                            //something has changed, allow saves

                            disableSaves = false;
                          } else {
                            disableSaves = true;
                          }
                        },
                        onFieldSubmitted: (_) {
                          // TODO move focus to next field?
                        },
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a NRL fixture link';
                          }
                          return null;
                        },
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 20.0),
                const Text('AFL:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        enabled: !disableBackButton,
                        decoration: const InputDecoration(
                          hintText: 'enter URL here',
                        ),
                        controller: _daucompAflJsonURLController,
                        onChanged: (String value) {
                          if (daucomp?.aflFixtureJsonURL.toString() != value) {
                            //something has changed, allow saves

                            disableSaves = false;
                          } else {
                            disableSaves = true;
                          }
                        },
                        onFieldSubmitted: (_) {
                          // TODO move focus to next field?
                        },
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a AFL fixture link';
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
        ));
  }

  Widget buttonFixture(
      BuildContext context, DAUCompsViewModel dauCompsViewModel) {
    if (daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          if (dauCompsViewModel.isDownloading) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Fixture download already in progress')));
            return;
          }
          try {
            disableBackButton = true;
            disableSaves = true;

            await dauCompsViewModel.getNetworkFixtureData(daucomp!);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.red,
                  content:
                      Text('An error occurred during fixture download: $e'),
                  duration: const Duration(seconds: 10),
                ),
              );
            }
          } finally {
            disableBackButton = false;
            disableSaves = false;
          }
        },
        child: Text(
            !dauCompsViewModel.isDownloading ? 'Download' : 'Downloading...'),
      );
    }
  }

  Widget buttonLegacy(
      BuildContext context, DAUCompsViewModel dauCompsViewModel) {
    if (daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          //check if syncing already in progress...
          if (dauCompsViewModel.isLegacySyncing) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Legacy tip sync already in progress')));
            return;
          }
          // check if daucomp dbkey for this record matches the current daucomp dbkey
          // if not, show a snackbar and return without syncing
          if (daucomp?.dbkey != dauCompsViewModel.defaultDAUCompDbKey) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                duration: Duration(seconds: 15),
                content: Text(
                    'You can only sync to legacy if this record is the active comp in remote config. Change it here: https://console.firebase.google.com/project/dau-footy-tipping-f8a42/config')));
            return;
          }

          // ...if not, initiate the sync
          try {
            disableBackButton = true;
            disableSaves = true;

            String syncResult =
                await dauCompsViewModel.syncTipsWithLegacy(daucomp!);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text(syncResult),
                  duration: const Duration(seconds: 10),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.red,
                  content:
                      Text('An error occurred during the leagcy tip sync: $e'),
                  duration: const Duration(seconds: 10),
                ),
              );
            }
          } finally {
            disableBackButton = false;
            disableSaves = false;
          }
        },
        child: Text(!dauCompsViewModel.isLegacySyncing ? 'Sync' : 'Syncing...'),
      );
    }
  }

  Widget buttonScoring(
      BuildContext context, DAUCompsViewModel dauCompsViewModel) {
    if (daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          //check if syncing already in progress...
          if (dauCompsViewModel.isScoring) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Scoring already in progress')));
            return;
          }

          // ...if not, initiate the sync
          try {
            String syncResult =
                await dauCompsViewModel.updateScoring(daucomp!, null, null);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text(syncResult),
                  duration: const Duration(seconds: 10),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.red,
                  content:
                      Text('An error occurred during scoring calculation: $e'),
                  duration: const Duration(seconds: 10),
                ),
              );
            }
          }
        },
        child: Text(!dauCompsViewModel.isScoring ? 'Score' : 'Scoring...'),
      );
    }
  }
}
