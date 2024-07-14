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
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class DAUCompsEditPage extends StatefulWidget {
  final DAUComp? daucomp;

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
  bool disableSaves = true;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    initTextControllersListeners();
    updateSaveButtonState();
  }

  void initTextControllersListeners() {
    widget._daucompNameController.addListener(updateSaveButtonState);
    widget._daucompAflJsonURLController.addListener(updateSaveButtonState);
    widget._daucompNrlJsonURLController.addListener(updateSaveButtonState);
  }

  void updateSaveButtonState() {
    bool shouldEnableSave;
    if (widget.daucomp == null) {
      shouldEnableSave = widget._daucompNameController.text.isNotEmpty &&
          widget._daucompAflJsonURLController.text.isNotEmpty &&
          widget._daucompNrlJsonURLController.text.isNotEmpty;
    } else {
      shouldEnableSave =
          widget._daucompNameController.text != widget.daucomp!.name ||
              widget._daucompAflJsonURLController.text !=
                  widget.daucomp!.aflFixtureJsonURL.toString() ||
              widget._daucompNrlJsonURLController.text !=
                  widget.daucomp!.nrlFixtureJsonURL.toString();
    }

    if (disableSaves != !shouldEnableSave) {
      setState(() {
        disableSaves = !shouldEnableSave;
      });
    }
  }

  @override
  void dispose() {
    widget._daucompNameController.removeListener(updateSaveButtonState);
    widget._daucompAflJsonURLController.removeListener(updateSaveButtonState);
    widget._daucompNrlJsonURLController.removeListener(updateSaveButtonState);
    super.dispose();
  }

  Future<void> _saveDAUComp(
      DAUCompsViewModel dauCompsViewModel, BuildContext context) async {
    try {
      bool aflURLActive =
          await isUriActive(widget._daucompAflJsonURLController.text);
      bool nrlURLActive =
          await isUriActive(widget._daucompNrlJsonURLController.text);
      log('aflURLActive = $aflURLActive');
      log('nrlURLActive = $nrlURLActive');

      if (aflURLActive && nrlURLActive) {
        if (widget.daucomp == null) {
          DAUComp newDAUComp = DAUComp(
            name: widget._daucompNameController.text,
            aflFixtureJsonURL:
                Uri.parse(widget._daucompAflJsonURLController.text),
            nrlFixtureJsonURL:
                Uri.parse(widget._daucompNrlJsonURLController.text),
            daurounds: [],
          );

          await dauCompsViewModel.newDAUComp(newDAUComp);
          await dauCompsViewModel.saveBatchOfCompAttributes();

          GamesViewModel newCompGamesViewModel = GamesViewModel(newDAUComp);
          String res = await dauCompsViewModel.getNetworkFixtureData(
              newDAUComp, newCompGamesViewModel);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: League.nrl.colour,
              content: Text(res),
              duration: const Duration(seconds: 4),
            ),
          );

          Navigator.of(context).pop();
        } else {
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

    return ChangeNotifierProvider<DAUCompsViewModel>.value(
        value: dauCompsViewModel,
        builder: (context, snapshot) {
          return Scaffold(
              appBar: AppBar(
                leading: Builder(
                  builder: (BuildContext context) {
                    return IconButton(
                      icon: disableBackButton
                          ? const ImageIcon(null)
                          : const Icon(Icons.arrow_back),
                      onPressed: disableBackButton
                          ? null
                          : () {
                              if (disableSaves) {
                                Navigator.maybePop(context);
                              } else {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    content: const Text(
                                        'You have unsaved changes. Do you really want to discard them?'),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context)
                                              .pop(); // Close the dialog
                                          Navigator.of(context)
                                              .pop(); // Go back
                                        },
                                        child: const Text('Discard'),
                                      )
                                    ],
                                  ),
                                );
                              }
                            },
                    );
                  },
                ),
                actions: <Widget>[
                  Builder(
                    builder: (BuildContext context) {
                      return IconButton(
                        color: Colors.white,
                        icon: const Icon(Icons.save, color: Colors.white),
                        onPressed: disableSaves
                            ? null
                            : () async {
                                final isValid =
                                    _formKey.currentState!.validate();
                                if (isValid) {
                                  setState(() {
                                    disableSaves = true;
                                    disableBackButton = true;
                                  });

                                  await _saveDAUComp(
                                      dauCompsViewModel, context);

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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            buttonFixture(context, dauCompsViewModel),
                            if (widget.daucomp ==
                                dauCompsViewModel.activeDAUComp)
                              buttonLegacy(context, dauCompsViewModel),
                            if (widget.daucomp ==
                                dauCompsViewModel.activeDAUComp)
                              buttonScoring(context, scoresViewModel),
                          ],
                        ),
                        Row(
                          children: [
                            const Text('Active Comp:'),
                            Consumer<DAUCompsViewModel>(
                                builder: (context, model, child) {
                              return Switch(
                                value: widget.daucomp == model.activeDAUComp,
                                onChanged: (bool value) async {
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
                                    RemoteConfigService remoteConfigService =
                                        RemoteConfigService();
                                    remoteConfigService.setConfigCurrentDAUComp(
                                        widget.daucomp!.dbkey!);
                                    await dauCompsViewModel
                                        .changeSelectedDAUComp(
                                            widget.daucomp!.dbkey!, true);
                                    log('Active comp changed to: ${widget.daucomp!.name}');
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                            'You cannot turn off the active comp. Instead edit another comp to be active.'),
                                        backgroundColor: League.afl.colour,
                                      ),
                                    );
                                  }
                                },
                              );
                            }),
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
                                decoration: const InputDecoration(
                                  hintText: 'DAU Comp name',
                                ),
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
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  TableCell(
                                    verticalAlignment:
                                        TableCellVerticalAlignment.bottom,
                                    child: Center(
                                      child: Text('Last Game',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  TableCell(
                                    verticalAlignment:
                                        TableCellVerticalAlignment.bottom,
                                    child: Text('# NRL',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  TableCell(
                                    verticalAlignment:
                                        TableCellVerticalAlignment.bottom,
                                    child: Text('# AFL',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              for (var round in widget.daucomp!.daurounds)
                                if (round.games.isNotEmpty)
                                  TableRow(
                                    children: [
                                      TableCell(
                                        verticalAlignment:
                                            TableCellVerticalAlignment.middle,
                                        child: Text(
                                            round.dAUroundNumber.toString()),
                                      ),
                                      TableCell(
                                        child: TextFormField(
                                          style: const TextStyle(fontSize: 14),
                                          enabled: !disableBackButton,
                                          initialValue:
                                              '${DateFormat('E d/M').format(round.roundStartDate.toLocal())} ${DateFormat('h:mm a').format(round.roundStartDate.toLocal()).replaceAll(" AM", "a").replaceAll(" PM", "p")}',
                                          onTap: () async {
                                            FocusScope.of(context)
                                                .requestFocus(FocusNode());
                                            DateTime? date =
                                                await showDatePicker(
                                              context: context,
                                              initialDate: round.roundStartDate,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100),
                                            );
                                            TimeOfDay? time =
                                                await showTimePicker(
                                              context: context,
                                              initialTime:
                                                  TimeOfDay.fromDateTime(
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
                                            FocusScope.of(context)
                                                .requestFocus(FocusNode());
                                            DateTime? date =
                                                await showDatePicker(
                                              context: context,
                                              initialDate: round.roundEndDate,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100),
                                            );
                                            TimeOfDay? time =
                                                await showTimePicker(
                                              context: context,
                                              initialTime:
                                                  TimeOfDay.fromDateTime(
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
                                            .where((game) =>
                                                game.league == League.nrl)
                                            .length
                                            .toString()),
                                      ),
                                      TableCell(
                                        verticalAlignment:
                                            TableCellVerticalAlignment.middle,
                                        child: Text(round.games
                                            .where((game) =>
                                                game.league == League.afl)
                                            .length
                                            .toString()),
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
        });
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
          if (dauCompsViewModel.isLegacySyncing) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Legacy sync already in progress')));
            return;
          }

          if (widget.daucomp?.dbkey !=
              dauCompsViewModel.selectedDAUComp!.dbkey) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                duration: Duration(seconds: 15),
                content: Text(
                    'You can only sync to legacy if this record is the active comp in remote config. Change it here: https://console.firebase.google.com/project/dau-footy-tipping-f8a42/config')));
            return;
          }

          try {
            setState(() {
              disableBackButton = true;
              disableSaves = true;
            });

            String syncResult = await dauCompsViewModel.syncTipsWithLegacy(
                widget.daucomp!, di<GamesViewModel>(), null);

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text(syncResult),
                  duration: const Duration(seconds: 4),
                ),
              );
            }

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
          if (scoresViewModel.isScoring) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Scoring already in progress')));
            return;
          }

          try {
            setState(() {
              disableBackButton = true;
              disableSaves = true;
            });
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
