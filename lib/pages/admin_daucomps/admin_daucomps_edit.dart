import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:watch_it/watch_it.dart';

// this class supports both creating and updating DAUComp records.
// it has 2 modes, then daucomp is null it is in new record mode,
// when it is not null it is in edit record mode
class DAUCompsEditPage extends StatefulWidget {
  final DAUComp?
      daucomp; //if this is an edit for a new comp, this will stay null
  //final DAUCompsViewModel dauCompViewModel;

  late final TextEditingController _daucompNameController;
  late final TextEditingController _daucompAflJsonURLController;
  late final TextEditingController _daucompNrlJsonURLController;

  DAUCompsEditPage(this.daucomp, {super.key}) {
    _daucompNameController = TextEditingController(text: daucomp?.name);
    _daucompAflJsonURLController =
        TextEditingController(text: daucomp?.aflFixtureJsonURL.toString());
    _daucompNrlJsonURLController =
        TextEditingController(text: daucomp?.nrlFixtureJsonURL.toString());
  }

  @override
  State<DAUCompsEditPage> createState() => _DAUCompsEditPageState();
}

class _DAUCompsEditPageState extends State<DAUCompsEditPage> {
  bool disableBackButton = false;

  bool disableSaves = false;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  void _saveDAUComp(
      DAUCompsViewModel dauCompsViewModel, BuildContext context) async {
    try {
      //check the URL's are active on the server,
      //if yes, save the record and show a green snackbar saying the record is saved
      //if no, reject the save and show a red snackbar saying the URL's are not active

      bool aflURLActive =
          await isUriActive(widget._daucompAflJsonURLController.text);
      bool nrlURLActive =
          await isUriActive(widget._daucompNrlJsonURLController.text);
      log('aflURLActive = $aflURLActive');
      log('nrlURLActive = $nrlURLActive');

      if (aflURLActive && nrlURLActive) {
        if (widget.daucomp == null) {
          // this is a new record
          DAUComp updatedDUAcomp = DAUComp(
            dbkey: widget.daucomp?.dbkey,
            name: widget._daucompNameController.text,
            aflFixtureJsonURL:
                Uri.parse(widget._daucompAflJsonURLController.text),
            nrlFixtureJsonURL:
                Uri.parse(widget._daucompNrlJsonURLController.text),
            daurounds: [],
          );

          await dauCompsViewModel.newDAUComp(updatedDUAcomp);

          await dauCompsViewModel.saveBatchOfCompAttributes();

          if (widget.daucomp == null) {
            // as this is a new daucomp record, download the fixture data and process
            // the games in rounds and save them to the database
            String res = await dauCompsViewModel.getNetworkFixtureData(
                updatedDUAcomp, null);
            // snackbar to show the result of the fixture download
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: League.afl.colour,
                content: Text(res),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } else {
          // this is an existing record
          dauCompsViewModel.updateCompAttribute(widget.daucomp!.dbkey!, "name",
              widget._daucompNameController.text);
          dauCompsViewModel.updateCompAttribute(widget.daucomp!.dbkey!,
              "aflFixtureJsonURL", widget._daucompAflJsonURLController.text);
          dauCompsViewModel.updateCompAttribute(widget.daucomp!.dbkey!,
              "nrlFixtureJsonURL", widget._daucompNrlJsonURLController.text);

          await dauCompsViewModel.saveBatchOfCompAttributes();
        }

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

  Future<bool> isUriActive(String uri) async {
    try {
      final response = await http.get(Uri.parse(uri));
      if (response.statusCode == 200) {
        return true;
      } else {
        log('Error checking URL: $uri, status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    DAUCompsViewModel dauCompsViewModel = di<DAUCompsViewModel>();
    ScoresViewModel scoresViewModel = di<ScoresViewModel>();

    if (widget.daucomp == null) {
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
                  color: Colors.white,
                  icon: !disableSaves
                      ? const Icon(Icons.save, color: Colors.white)
                      : const SizedBox.shrink(),
                  onPressed: disableSaves
                      ? null
                      : () async {
                          // Validate will return true if the form is valid, or false if
                          // the form is invalid.
                          final isValid = _formKey.currentState!.validate();
                          if (isValid) {
                            // disable the save and back button while the save is in progress
                            setState(() {
                              disableSaves = true;
                              disableBackButton = true;
                            });

                            // save the record
                            _saveDAUComp(dauCompsViewModel, context);
                            // re-enable the save and back button

                            setState(() {
                              disableSaves = false;
                              disableBackButton = false;
                            });
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
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // add a row with a sync button download fixture data from the URL's
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      buttonFixture(context, dauCompsViewModel),
                      // only show the scoring and legacy sync buttons if this record daucomp dbkey
                      // is the selected daucomp dbkey
                      if (widget.daucomp?.dbkey ==
                          dauCompsViewModel.defaultDAUCompDbKey)
                        buttonLegacy(context, dauCompsViewModel),

                      if (widget.daucomp?.dbkey ==
                          dauCompsViewModel.defaultDAUCompDbKey)
                        buttonScoring(context, scoresViewModel),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Active Comp:'),
                      Switch(
                        value: widget.daucomp?.dbkey ==
                            dauCompsViewModel.defaultDAUCompDbKey,
                        onChanged: (bool value) {
                          // if this is a new record, dont allow the user to change the active comp
                          if (widget.daucomp == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                    'You cannot set the active comp for a new record. Save the record first.'),
                                backgroundColor: League.afl.colour,
                              ),
                            );
                            return;
                          }
                          if (value) {
                            dauCompsViewModel
                                .changeCurrentDAUComp(widget.daucomp!.dbkey!);
                            // write the change to /AppConfig
                            RemoteConfigService remoteConfigService =
                                RemoteConfigService();
                            remoteConfigService.setConfigCurrentDAUComp(
                                widget.daucomp!.dbkey!);
                            // also make change to model
                            dauCompsViewModel
                                .changeCurrentDAUComp(widget.daucomp!.dbkey!);
                          } else {
                            // if the user is trying to turn off the active comp, show a snackbar
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                    'You cannot turn off the active comp. Instead edit another comp to be active.'),
                                backgroundColor: League.afl.colour,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const Text('Name:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          enabled: !disableBackButton,
                          controller: widget._daucompNameController,
                          onChanged: (String value) {
                            if (widget.daucomp?.name != value) {
                              //something has changed, allow saves

                              setState(() {
                                disableSaves = false;
                              });
                              log('name changed to: $value');
                            } else {
                              setState(() {
                                disableSaves = true;
                              });
                              log('name has not changed');
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
                          style: const TextStyle(fontSize: 14),
                          enabled: !disableBackButton,
                          decoration: const InputDecoration(
                            hintText: 'enter URL here',
                          ),
                          controller: widget._daucompNrlJsonURLController,
                          onChanged: (String value) {
                            if (widget.daucomp?.nrlFixtureJsonURL.toString() !=
                                value) {
                              //something has changed, allow saves

                              setState(() {
                                disableSaves = false;
                              });
                              log('nrlFixtureJsonURL changed to: $value');
                            } else {
                              setState(() {
                                disableSaves = true;
                              });
                              log('nrlFixtureJsonURL has not changed');
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
                          style: const TextStyle(fontSize: 14),
                          enabled: !disableBackButton,
                          decoration: const InputDecoration(
                            hintText: 'enter URL here',
                          ),
                          controller: widget._daucompAflJsonURLController,
                          onChanged: (String value) {
                            if (widget.daucomp?.aflFixtureJsonURL.toString() !=
                                value) {
                              //something has changed, allow saves
                              setState(() {
                                disableSaves = false;
                              });

                              log('aflFixtureJsonURL changed to: $value');
                            } else {
                              setState(() {
                                disableSaves = true;
                              });
                              log('aflFixtureJsonURL has not changed');
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
                  const SizedBox(height: 20.0),
                  if (widget.daucomp != null)
                    const Text('Round details:',
                        style: TextStyle(fontWeight: FontWeight.bold)),

                  // add a table with the round data laid out in rows. column 1 is the round number
                  // column 2 is the start date, column 3 is the end date
                  // the dates are edititable, with changes to the dates enabling the save button
                  // column 4 is the number of nrl games in the round
                  // column 5 is the number of afl games in the round

                  // only show the table if the daucomp is not null
                  if (widget.daucomp != null)
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(0.40),
                        1: FlexColumnWidth(2),
                        2: FlexColumnWidth(2),
                        3: FlexColumnWidth(0.5),
                        4: FlexColumnWidth(0.5),
                      },
                      children: [
                        const TableRow(
                          children: [
                            TableCell(
                              verticalAlignment:
                                  TableCellVerticalAlignment.bottom,
                              child: Text('#'),
                            ),
                            TableCell(
                              verticalAlignment:
                                  TableCellVerticalAlignment.bottom,
                              child: Center(
                                child: Text('First Game',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            TableCell(
                              verticalAlignment:
                                  TableCellVerticalAlignment.bottom,
                              child: Center(
                                child: Text('Last Game',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            TableCell(
                              verticalAlignment:
                                  TableCellVerticalAlignment.bottom,
                              child: Text('# NRL',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            TableCell(
                              verticalAlignment:
                                  TableCellVerticalAlignment.bottom,
                              child: Text('# AFL',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        for (var round in widget.daucomp!.daurounds)
                          // only show the round if it has games
                          if (round.games.isNotEmpty)
                            TableRow(
                              children: [
                                TableCell(
                                  verticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  child: Text(round.dAUroundNumber.toString()),
                                ),
                                TableCell(
                                  child: TextFormField(
                                    style: const TextStyle(fontSize: 14),
                                    enabled: !disableBackButton,
                                    initialValue:
                                        '${DateFormat('E d/M').format(round.roundStartDate.toLocal())} ${DateFormat('h:mm a').format(round.roundStartDate.toLocal()).replaceAll(" AM", "a").replaceAll(" PM", "p")}',
                                    onTap: () async {
                                      FocusScope.of(context).requestFocus(
                                          FocusNode()); // to prevent opening of the keyboard
                                      DateTime? date = await showDatePicker(
                                        context: context,
                                        initialDate: round.roundStartDate,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      TimeOfDay? time = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.fromDateTime(
                                            round.roundStartDate),
                                      );
                                      if (time != null) {
                                        round.adminOverrideRoundStartDate =
                                            DateTime(
                                                date!.year,
                                                date.month,
                                                date.day,
                                                time.hour,
                                                time.minute);
                                        // Enable the save button
                                        setState(() {
                                          disableSaves = false;
                                        });
                                      }
                                    },
                                  ),
                                ),
                                TableCell(
                                  child: TextFormField(
                                    style: const TextStyle(fontSize: 14),
                                    enabled: !disableBackButton,
                                    initialValue:
                                        '${DateFormat('E d/M').format(round.roundEndDate.toLocal())} ${DateFormat('h:mm a').format(round.roundEndDate.toLocal()).replaceAll(" AM", "a").replaceAll(" PM", "p")}',
                                    onTap: () async {
                                      FocusScope.of(context).requestFocus(
                                          FocusNode()); // to prevent opening of the keyboard
                                      DateTime? date = await showDatePicker(
                                        context: context,
                                        initialDate: round.roundEndDate,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      TimeOfDay? time = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.fromDateTime(
                                            round.roundEndDate),
                                      );
                                      if (time != null) {
                                        round.adminOverrideRoundEndDate =
                                            DateTime(
                                                date!.year,
                                                date.month,
                                                date.day,
                                                time.hour,
                                                time.minute);
                                        // Enable the save button
                                        setState(() {
                                          disableSaves = false;
                                        });
                                      }
                                    },
                                  ),
                                ),
                                TableCell(
                                  verticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  child: Text(round.games
                                      .where(
                                          (game) => game.league == League.nrl)
                                      .length
                                      .toString()),
                                ),
                                TableCell(
                                  verticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  child: Text(round.games
                                      .where(
                                          (game) => game.league == League.afl)
                                      .length
                                      .toString()),
                                ),
                              ],
                            ),
                        // if games is empty, show a message
                        if (widget.daucomp!.daurounds.isEmpty)
                          const TableRow(
                            children: [
                              TableCell(
                                child: Text(
                                    'Make this the active comp to see round details'),
                              ),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ));
  }

  Widget buttonFixture(
      BuildContext context, DAUCompsViewModel dauCompsViewModel) {
    if (widget.daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          if (dauCompsViewModel.isDownloading) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: League.afl.colour,
                content: const Text('Fixture download already in progress')));
            return;
          }
          try {
            setState(() {
              disableBackButton = true;
              disableSaves = true;
            });

            String result = await dauCompsViewModel.getNetworkFixtureData(
                widget.daucomp!, di<GamesViewModel>());
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: League.nrl.colour,
                  content: Text(result),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: League.afl.colour,
                  content:
                      Text('An error occurred during fixture download: $e'),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } finally {
            setState(() {
              disableBackButton = false;
              disableSaves = false;
            });
          }
        },
        child: Text(
            !dauCompsViewModel.isDownloading ? 'Download' : 'Downloading...'),
      );
    }
  }

  Widget buttonLegacy(
      BuildContext context, DAUCompsViewModel dauCompsViewModel) {
    if (widget.daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          //check if syncing already in progress...
          if (dauCompsViewModel.isLegacySyncing) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Legacy sync already in progress')));
            return;
          }
          // check if daucomp dbkey for this record matches the current daucomp dbkey
          // if not, show a snackbar and return without syncing
          if (widget.daucomp?.dbkey != dauCompsViewModel.defaultDAUCompDbKey) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                duration: Duration(seconds: 15),
                content: Text(
                    'You can only sync to legacy if this record is the active comp in remote config. Change it here: https://console.firebase.google.com/project/dau-footy-tipping-f8a42/config')));
            return;
          }

          // ...if not, initiate the sync
          try {
            setState(() {
              disableBackButton = true;
              disableSaves = true;
            });

            String syncResult = await dauCompsViewModel.syncTipsWithLegacy(
                widget.daucomp!, di<GamesViewModel>(), null);

            // show a snackbar with the result of the sync

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text(syncResult),
                  duration: const Duration(seconds: 4),
                ),
              );
            }

            // sync scores to legacy

            di<LegacyTippingService>().syncRoundScoresToLegacy();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text(syncResult),
                  duration: const Duration(seconds: 4),
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
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } finally {
            setState(() {
              disableBackButton = false;
              disableSaves = false;
            });
          }
        },
        child: Text(!dauCompsViewModel.isLegacySyncing ? 'Sync' : 'Syncing...'),
      );
    }
  }

  Widget buttonScoring(BuildContext context, ScoresViewModel scoresViewModel) {
    if (widget.daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          //check if syncing already in progress...
          if (scoresViewModel.isScoring) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Scoring already in progress')));
            return;
          }

          // ...if not, initiate the sync
          try {
            setState(() {
              disableBackButton = true;
              disableSaves = true;
            });
            //yield so UI updates
            await Future.delayed(const Duration(milliseconds: 100));
            String syncResult = await scoresViewModel.updateScoring(
                widget.daucomp!, null, null);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text(syncResult),
                  duration: const Duration(seconds: 4),
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
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } finally {
            setState(() {
              disableBackButton = false;
              disableSaves = false;
            });
          }
        },
        child: Text(!scoresViewModel.isScoring ? 'Score' : 'Scoring...'),
      );
    }
  }
}
