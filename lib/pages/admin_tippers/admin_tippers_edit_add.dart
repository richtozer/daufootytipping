import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tipper_merge.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class TipperAdminEditPage extends StatefulWidget {
  final TippersViewModel tippersViewModel;
  final Tipper tipper;

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
  late Tipper tipper;
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
    admin = (tipper.tipperRole == TipperRole.admin) ? true : false;
    _tipperNameController = TextEditingController(text: tipper.name);
    _tipperEmailController = TextEditingController(text: tipper.email);
    _tipperLogonController = TextEditingController(text: tipper.logon);
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
        if (context.mounted) {
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
        }
        // stay on this page
        return;
      }

      await tippersViewModel.updateTipperAttribute(
          tipper.dbkey!, "name", _tipperNameController.text);
      await tippersViewModel.updateTipperAttribute(
          tipper.dbkey!, "email", _tipperEmailController.text);
      await tippersViewModel.updateTipperAttribute(
          tipper.dbkey!, "logon", _tipperLogonController.text);
      await tippersViewModel.updateTipperAttribute(
          tipper.dbkey!,
          "tipperRole",
          admin == true
              ? TipperRole.admin.toString().split('.').last
              : TipperRole.tipper.toString().split('.').last);

      await tippersViewModel.updateTipperAttribute(
          tipper.dbkey!,
          "compsParticipatedIn",
          tipper.compsPaidFor.map((comp) => comp.dbkey).toList());

      await tippersViewModel.saveBatchOfTipperChangesToDb();

      // navigate to the previous page
      if (context.mounted) Navigator.of(context).pop(true);
      //}
    } on Exception {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            content: const Text('Failed to update Tipper record'),
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
                          CircularProgressIndicator(color: League.nrl.colour);

                          _saveTipper(context);

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
        title: const Text('Edit Tipper'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
                            if (tipper.name != value) {
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
                            if (tipper.email != value) {
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
                            if (tipper.logon != value) {
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
                      //mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('DAU\nAdmin:'),
                        Switch(
                          value: admin,
                          activeColor: Colors.orange,
                          onChanged: (value) {
                            setState(() {
                              admin = value;
                            });

                            if (tipper.tipperRole.index.isEven
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
                        // if selectedDAUComp is not null then offer god mode
                        if (di<DAUCompsViewModel>().selectedDAUComp != null)
                          Row(
                            children: [
                              const Text('God\nmode: '),
                              ChangeNotifierProvider<TippersViewModel>.value(
                                  value: di<TippersViewModel>(),
                                  child: Consumer<TippersViewModel>(
                                    builder: (context, tippersViewModelConsumer,
                                        child) {
                                      return Switch(
                                        value: (tippersViewModelConsumer
                                                .inGodMode &&
                                            tippersViewModelConsumer
                                                    .selectedTipper ==
                                                tipper),
                                        activeColor: Colors.red,
                                        onChanged: (value) {
                                          if (value == true) {
                                            // admins cannot god mode themselves - display snackbar if they try
                                            if (tippersViewModelConsumer
                                                    .authenticatedTipper ==
                                                tipper) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  backgroundColor: Colors.red,
                                                  content: const Text(
                                                      'For technical reasons, admins cannot god mode themselves.\n\nAsk another admin to do it for you.'),
                                                ),
                                              );
                                              return;
                                            }
                                            // if godmode is already turned on for another tipper
                                            // then continue with this change, but display a snackbar
                                            // saying we turned it off for tipper A, and turned it on here for tipper B
                                            if (tippersViewModelConsumer
                                                .inGodMode) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  backgroundColor: Colors.red,
                                                  content: Text(
                                                      'God mode changed from ${tippersViewModelConsumer.selectedTipper.name} to ${tipper.name}'),
                                                ),
                                              );
                                            }

                                            tippersViewModelConsumer
                                                .selectedTipper = tipper;
                                          } else {
                                            tippersViewModelConsumer
                                                    .selectedTipper =
                                                tippersViewModelConsumer
                                                    .authenticatedTipper!;
                                          }
                                          // reset the other view models in daucompsviewmodel to reflect
                                          // any changes in the selected tipper
                                          di<DAUCompsViewModel>()
                                              .selectedTipperChanged();
                                        },
                                      );
                                    },
                                  )),
                            ],
                          ),
                      ]),

                  // add a row for 'Paid Comps', display a list of all DAUComps
                  // if the tipper is a paid up member, then show a tick
                  // allow the admin to edit which comps this tipper has paid for
                  FutureBuilder<List<DAUComp>>(
                      future: di<DAUCompsViewModel>().getDAUcomps(),
                      builder: (BuildContext context,
                          AsyncSnapshot<List<DAUComp>> snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                              child: CircularProgressIndicator(
                                  color: League.nrl.colour));
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
                                  'Select the competitions this tipper has paid for:'),
                              DataTable(
                                sortColumnIndex: 1,
                                sortAscending: true,
                                columns: const [
                                  DataColumn(label: Text('Paid')),
                                  DataColumn(label: Text('Competition Name'))
                                ],
                                rows: comps
                                    .map((comp) => DataRow(
                                          cells: [
                                            DataCell(
                                              Checkbox(
                                                value: tipper.paidForComp(comp),
                                                onChanged: (bool? value) {
                                                  log('Checkbox changed to $value');
                                                  setState(() {
                                                    if (value == true) {
                                                      widget.tipper.compsPaidFor
                                                          .add(comp);
                                                    } else {
                                                      widget.tipper.compsPaidFor
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
                      }),
                ],
              ),
            ),
            Spacer(),
            ElevatedButton(
              onPressed: () {
                // Trigger edit functionality
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminTipperMergeEditPage(
                        widget.tippersViewModel, tipper),
                  ),
                );
              },
              child: const Text('Merge...'),
            ),
            Spacer(),
          ],
        ),
      ),
    );
  }
}
