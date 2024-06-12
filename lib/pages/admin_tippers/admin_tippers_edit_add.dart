import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class TipperAdminEditPage extends StatefulWidget {
  final TippersViewModel tippersViewModel;
  final Tipper? tipper;

  //constructor
  const TipperAdminEditPage(this.tippersViewModel, this.tipper, {super.key});

  @override
  State<TipperAdminEditPage> createState() => _FormEditTipperState();
}

class _FormEditTipperState extends State<TipperAdminEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _tipperNameController;
  late TextEditingController _tipperEmailController;
  late TextEditingController _tipperLogonController;

  final FocusNode _emailFocusNode = FocusNode();
  late Tipper? tipper;
  late bool admin;
  late TippersViewModel tippersViewModel;

  late bool changesNeedSaving = false;
  late bool disableSaves = true;
  late int changes = 0;
  List<DAUComp> comps = [];

  @override
  void initState() {
    super.initState();
    tipper = widget.tipper;
    tippersViewModel = widget.tippersViewModel;
    //active = tipper?.active == null ? true : tipper!.active;
    admin = (tipper?.tipperRole == TipperRole.admin) ? true : false;
    _tipperNameController = TextEditingController(text: tipper?.name);
    _tipperEmailController = TextEditingController(text: tipper?.email);
    _tipperLogonController = TextEditingController(text: tipper?.logon);
  }

  @override
  void dispose() {
    _tipperNameController.dispose();
    _tipperEmailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  void _saveTipper(BuildContext context) async {
    try {
      // make sure the email and logon are not assigned to another tipper
      Tipper? tipperWithDupEmail =
          await tippersViewModel.isEmailOrLogonAlreadyAssigned(
              _tipperEmailController.text, _tipperLogonController.text, tipper);
      if (tipperWithDupEmail != null) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            content: Text(
                'The email ${tipperWithDupEmail.email} or logon ${tipperWithDupEmail.logon} is already assigned to tipper ${tipperWithDupEmail.name}'),
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
        // stay on this page
        return;
      }

      await tippersViewModel.updateTipperAttribute(
          tipper!.dbkey!, "name", _tipperNameController.text);
      await tippersViewModel.updateTipperAttribute(
          tipper!.dbkey!, "email", _tipperEmailController.text);
      await tippersViewModel.updateTipperAttribute(
          tipper!.dbkey!, "logon", _tipperLogonController.text);
      await tippersViewModel.updateTipperAttribute(
          tipper!.dbkey!,
          "tipperRole",
          admin == true
              ? TipperRole.admin.toString().toString().split('.').last
              : TipperRole.tipper.toString().toString().split('.').last);

      await tippersViewModel.updateTipperAttribute(
          tipper!.dbkey!,
          "compsParticipatedIn",
          tipper!.compsParticipatedIn.map((comp) => comp.dbkey).toList());

      await tippersViewModel.saveBatchOfTipperAttributes();

      // navigate to the previous page
      if (context.mounted) Navigator.of(context).pop(true);
      //}
    } on Exception {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            content: tipper != null
                ? const Text('Failed to update the Tipper record')
                : const Text('Failed to create a new Tipper record'),
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

  Widget buttonLegacy(
      BuildContext context, DAUCompsViewModel dauCompsViewModel) {
    if (di<DAUCompsViewModel>().selectedDAUComp == null) {
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

          // ...if not, initiate the sync
          try {
            disableSaves = true;

            String syncResult = await dauCompsViewModel.syncTipsWithLegacy(
                di<DAUCompsViewModel>().selectedDAUComp!,
                di<GamesViewModel>(),
                widget.tipper);
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
            disableSaves = false;
          }
        },
        child: Text(
            !dauCompsViewModel.isLegacySyncing ? 'Sync Tips' : 'Syncing...'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: changesNeedSaving
                  ? const ImageIcon(
                      null) // dont show anything clickable while saving is in progress
                  : const Icon(Icons.arrow_back),
              onPressed: changesNeedSaving
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
                icon: disableSaves
                    ? const ImageIcon(null) //show nothing if they cant save
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
                          changesNeedSaving = true;
                          CircularProgressIndicator(color: League.afl.colour);
                          _saveTipper(
                              context); //save the tipper and pop the page
                          setState(() {
                            changesNeedSaving = false;
                            disableSaves = false;
                          });
                        }
                      },
              );
            },
          ),
        ],
        title: tipper == null
            ? const Text('New Tipper')
            : const Text('Edit Tipper'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                buttonLegacy(context, di<DAUCompsViewModel>()),
              ],
            ),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: [
                      const Text('Name:'),
                      Expanded(
                        child: TextFormField(
                          enabled: !changesNeedSaving,
                          controller: _tipperNameController,
                          decoration: const InputDecoration(
                            hintText: 'Tipper name',
                          ),
                          onFieldSubmitted: (_) {
                            // move focus to next field
                            _emailFocusNode.requestFocus();
                          },
                          validator: (String? value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a tipper name';
                            }
                            return null;
                          },
                          onChanged: (String value) {
                            if (tipper?.name != value) {
                              //something has changed, maybe allow saves
                              setState(() {
                                changes++; //increment the number of changes
                                if (changes == 0) {
                                  disableSaves = true;
                                } else {
                                  disableSaves = false;
                                }
                              });
                            } else {
                              setState(() {
                                changes--; //decrement the number of changes, maybe stop saves
                                if (changes == 0) {
                                  disableSaves = true;
                                } else {
                                  disableSaves = false;
                                }
                              });
                            }
                          },
                        ),
                      )
                    ],
                  ),

                  Row(
                    children: [
                      const Text('Email:'),
                      Expanded(
                        child: TextFormField(
                          enabled: !changesNeedSaving,
                          controller: _tipperEmailController,
                          decoration: const InputDecoration(
                            hintText: 'Email for communications',
                          ),
                          validator: (String? value) {
                            if (value == null ||
                                !EmailValidator.validate(value)) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                          onChanged: (String value) {
                            if (tipper?.email != value) {
                              //something has changed, maybe allow saves
                              setState(() {
                                changes++; //increment the number of changes
                                if (changes == 0) {
                                  disableSaves = true;
                                } else {
                                  disableSaves = false;
                                }
                              });
                            } else {
                              setState(() {
                                changes--; //decrement the number of changes, maybe stop saves
                                if (changes == 0) {
                                  disableSaves = true;
                                } else {
                                  disableSaves = false;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Logon:'),
                      Expanded(
                        child: TextFormField(
                          enabled: !changesNeedSaving,
                          controller: _tipperLogonController,
                          decoration: const InputDecoration(
                            hintText: 'Email for logon',
                          ),
                          validator: (String? value) {
                            if (value == null ||
                                !EmailValidator.validate(value)) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                          onChanged: (String value) {
                            if (tipper?.logon != value) {
                              //something has changed, maybe allow saves
                              setState(() {
                                changes++; //increment the number of changes
                                if (changes == 0) {
                                  disableSaves = true;
                                } else {
                                  disableSaves = false;
                                }
                              });
                            } else {
                              setState(() {
                                changes--; //decrement the number of changes, maybe stop saves
                                if (changes == 0) {
                                  disableSaves = true;
                                } else {
                                  disableSaves = false;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('DAU Admin:'),
                      Switch(
                        value: admin,
                        activeColor: Colors.yellow,
                        onChanged: (value) {
                          setState(() {
                            admin = value;
                          });

                          if (tipper!.tipperRole.index.isEven
                              ? false
                              : true == value) {
                            //something has changed, maybe allow saves
                            setState(() {
                              changes++; //increment the number of changes
                              if (changes == 0) {
                                disableSaves = true;
                              } else {
                                disableSaves = false;
                              }
                            });
                          } else {
                            setState(() {
                              changes--; //decrement the number of changes, maybe stop saves
                              if (changes == 0) {
                                disableSaves = true;
                              } else {
                                disableSaves = false;
                              }
                            });
                          }
                        },
                      ),
                      const Text(' God mode: '),
                      ChangeNotifierProvider<TippersViewModel>.value(
                          value: di<TippersViewModel>(),
                          child: Consumer<TippersViewModel>(
                            builder:
                                (context, tippersViewModelConsumer, child) {
                              // if the tipper being editing was not a participant for that year then display a msg that god mode is not available
                              if (!tipper!.compsParticipatedIn.any((element) =>
                                  element.dbkey ==
                                  di<DAUCompsViewModel>()
                                      .selectedDAUComp!
                                      .dbkey)) {
                                return const Text(
                                    'God mode is\nnot available\nfor this tipper.\nThey did not\ntip for the\nselected year');
                              }

                              return Switch(
                                value: (tippersViewModelConsumer.inGodMode &&
                                    tippersViewModelConsumer.selectedTipper ==
                                        tipper),
                                activeColor: Colors.yellow,
                                onChanged: (value) {
                                  if (value == true) {
                                    // if godmode is already turned on for another tipper
                                    // then continue with this change, but display a snackbar
                                    // saying we turned it off for tipper a, and turned it on here for this tipper
                                    if (tippersViewModelConsumer.inGodMode) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          backgroundColor: Colors.green,
                                          content: Text(
                                              'God mode changed from ${tippersViewModelConsumer.selectedTipper!.name} to ${tipper!.name}'),
                                        ),
                                      );
                                    }
                                    tippersViewModelConsumer.selectedTipper =
                                        tipper;
                                  } else {
                                    tippersViewModelConsumer.selectedTipper =
                                        tippersViewModelConsumer
                                            .authenticatedTipper;
                                  }
                                },
                              );
                            },
                          )),
                    ],
                  ),
                  // add a row for 'Active Comps', display a list of all DAUComps
                  // if the tippers is active in the comp, then show a tick
                  // allow the admin to edit which comps this tipper is active in
                  // save changes to the tipper's active comps
                  FutureBuilder<List<DAUComp>>(
                      future: di<DAUCompsViewModel>().getDAUcomps(),
                      builder: (BuildContext context,
                          AsyncSnapshot<List<DAUComp>> snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                              child: CircularProgressIndicator(
                                  color: League.afl.colour));
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Text('No Records');
                        } else {
                          comps = snapshot.data!;
                          // sort the comps by name descending
                          comps.sort((a, b) => b.name
                              .toLowerCase()
                              .compareTo(a.name.toLowerCase()));
                          return Column(
                            children: [
                              const Text(
                                  'Select the competitions this tipper is active in:'),
                              DataTable(
                                sortColumnIndex: 1,
                                sortAscending: true,
                                columns: const [
                                  DataColumn(label: Text('Active')),
                                  DataColumn(label: Text('Competition Name'))
                                ],
                                rows: comps
                                    .map((comp) => DataRow(
                                          cells: [
                                            DataCell(
                                              Checkbox(
                                                value: tipper!
                                                    .activeInComp(comp.dbkey!),
                                                onChanged: (bool? value) {
                                                  log('Checkbox changed to $value');
                                                  setState(() {
                                                    if (value == true) {
                                                      widget.tipper!
                                                          .compsParticipatedIn
                                                          .add(comp);
                                                    } else {
                                                      widget.tipper!
                                                          .compsParticipatedIn
                                                          .remove(comp);
                                                    }
                                                    changes++; //increment the number of changes
                                                    if (changes == 0) {
                                                      disableSaves = true;
                                                    } else {
                                                      disableSaves = false;
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                            DataCell(Text(comp.name)),
                                          ],
                                        ))
                                    .toList(),
                              ),
                            ],
                          );
                        }
                      })
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
