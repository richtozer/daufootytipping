import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/fixture.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class DAUCompsEditPage extends StatefulWidget {
  final DAUComp? daucomp;

  late final TextEditingController _daucompNameController;

  DAUCompsEditPage(this.daucomp, {super.key}) {
    _daucompNameController = TextEditingController(text: daucomp?.name);
  }

  @override
  State<DAUCompsEditPage> createState() => _DAUCompsEditPageState();
}

class _DAUCompsEditPageState extends State<DAUCompsEditPage> {
  bool disableSaves = true;
  bool disableBack = false;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  List<Fixture> fixtures = [];

  @override
  void initState() {
    super.initState();
    initTextControllersListeners();
    updateSaveButtonState();
    if (widget.daucomp != null) {
      fixtures = List.from(widget.daucomp!.fixtures);
    }
  }

  @override
  void dispose() {
    super.dispose();
    widget._daucompNameController.removeListener(updateSaveButtonState);
  }

  void initTextControllersListeners() {
    widget._daucompNameController.addListener(updateSaveButtonState);
  }

  void updateSaveButtonState() {
    bool shouldEnableSave;
    if (widget.daucomp == null) {
      shouldEnableSave =
          widget._daucompNameController.text.isNotEmpty && fixtures.isNotEmpty;
    } else {
      shouldEnableSave =
          widget._daucompNameController.text != widget.daucomp!.name ||
              !listEquals(fixtures, widget.daucomp!.fixtures);
    }

    if (disableSaves != !shouldEnableSave) {
      setState(() {
        disableSaves = !shouldEnableSave;
      });
    }
  }

  Future<void> _saveDAUComp(
      DAUCompsViewModel dauCompsViewModel, BuildContext context) async {
    try {
      bool allURLsActive = await Future.wait(fixtures
              .map((fixture) => isUriActive(fixture.fixtureJsonURL.toString())))
          .then((results) => results.every((result) => result));

      log('allURLsActive = $allURLsActive');

      if (allURLsActive) {
        if (widget.daucomp == null) {
          DAUComp newDAUComp = DAUComp(
            name: widget._daucompNameController.text,
            fixtures: fixtures,
            daurounds: [],
          );

          await dauCompsViewModel.newDAUComp(newDAUComp);
          await dauCompsViewModel.saveBatchOfCompAttributes();

          String res =
              await dauCompsViewModel.getNetworkFixtureData(newDAUComp);
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
              "fixtures", fixtures.map((fixture) => fixture.toJson()).toList());

          await dauCompsViewModel.saveBatchOfCompAttributes();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('DAUComp record saved'),
                backgroundColor: Colors.green,
              ),
            );
          }

          setState(() {
            disableSaves = true;
          });
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('One or more of the URLs are not active'),
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

    return ChangeNotifierProvider<DAUCompsViewModel>.value(
        value: dauCompsViewModel,
        builder: (context, snapshot) {
          return Scaffold(
              appBar: AppBar(
                leading: Builder(
                  builder: (BuildContext context) {
                    return IconButton(
                      icon: disableBack
                          ? const ImageIcon(null)
                          : const Icon(Icons.arrow_back),
                      onPressed: () {
                        if (!disableBack) {
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
                                    Navigator.of(context).pop(); // Go back
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
                        icon: disableSaves
                            ? const ImageIcon(null)
                            : const Icon(Icons.save, color: Colors.white),
                        onPressed: disableSaves
                            ? null
                            : () async {
                                final isValid =
                                    _formKey.currentState!.validate();
                                if (isValid) {
                                  setState(() {
                                    disableSaves = true;
                                  });

                                  await _saveDAUComp(
                                      dauCompsViewModel, context);

                                  setState(() {
                                    disableSaves = true;
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
                        if (widget.daucomp != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              buttonFixture(context, dauCompsViewModel),
                              buttonScoring(context),
                            ],
                          ),
                        if (widget.daucomp != null)
                          Row(
                            children: [
                              const Text('Active Comp:'),
                              Consumer<DAUCompsViewModel>(
                                  builder: (context, model, child) {
                                return Switch(
                                  value: widget.daucomp != null &&
                                      model.activeDAUComp != null &&
                                      widget.daucomp!.dbkey ==
                                          model.activeDAUComp!.dbkey,
                                  onChanged: (bool value) async {
                                    if (widget.daucomp == null) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                                      remoteConfigService
                                          .setConfigCurrentDAUComp(
                                              widget.daucomp!.dbkey!);
                                      await dauCompsViewModel
                                          .changeSelectedDAUComp(
                                              widget.daucomp!.dbkey!, true);
                                      log('Active comp changed to: ${widget.daucomp!.name}');
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                        const Text('Fixtures',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20.0),
                        ListView.builder(
                          shrinkWrap: true,
                          itemCount: fixtures.length,
                          itemBuilder: (context, index) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Fixture ${index + 1}:',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        style: const TextStyle(fontSize: 14),
                                        decoration: const InputDecoration(
                                          hintText: 'Enter URL here',
                                        ),
                                        initialValue: fixtures[index]
                                            .fixtureJsonURL
                                            .toString(),
                                        onChanged: (value) {
                                          setState(() {
                                            fixtures[index].fixtureJsonURL =
                                                Uri.parse(value);
                                            updateSaveButtonState();
                                          });
                                        },
                                        validator: (String? value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter a fixture link';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    DropdownButton<League>(
                                      value: fixtures[index].league,
                                      onChanged: (League? newValue) {
                                        setState(() {
                                          fixtures[index].league = newValue!;
                                          updateSaveButtonState();
                                        });
                                      },
                                      items: League.values
                                          .map<DropdownMenuItem<League>>(
                                              (League value) {
                                        return DropdownMenuItem<League>(
                                          value: value,
                                          child: Text(value.name),
                                        );
                                      }).toList(),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () {
                                        setState(() {
                                          fixtures.removeAt(index);
                                          updateSaveButtonState();
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20.0),
                              ],
                            );
                          },
                        ),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              fixtures.add(Fixture(
                                  fixtureJsonURL: Uri.parse(''),
                                  league: League.afl));
                              updateSaveButtonState();
                            });
                          },
                          child: const Text('Add Fixture'),
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
              disableBack = true;
            });

            String result =
                await dauCompsViewModel.getNetworkFixtureData(widget.daucomp!);
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
              disableBack = false;
            });
          }
        },
        child: Text(
            !dauCompsViewModel.isDownloading ? 'Download' : 'Downloading...'),
      );
    }
  }

  Widget buttonScoring(BuildContext context) {
    if (widget.daucomp == null) {
      return const SizedBox.shrink();
    } else {
      StatsViewModel scoresViewModel = StatsViewModel(widget.daucomp!);
      return OutlinedButton(
        onPressed: () async {
          if (scoresViewModel.isCalculating) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Scoring already in progress')));
            return;
          }

          try {
            setState(() {
              disableBack = true;
            });
            await Future.delayed(const Duration(milliseconds: 100));
            String syncResult =
                await scoresViewModel.updateStats(widget.daucomp!, null);
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
            if (context.mounted) {
              setState(() {
                disableBack = false;
              });
            }
          }
        },
        child: Text(!scoresViewModel.isCalculating ? 'Rescore' : 'Scoring...'),
      );
    }
  }
}
