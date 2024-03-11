import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class TipperAdminEditPage extends StatefulWidget {
  final TippersViewModel tippersViewModel;
  final Tipper? tipper;

  //constructor
  const TipperAdminEditPage(this.tippersViewModel, this.tipper, {super.key});
  //const TipperAdminEditPage(this.tipper, {super.key});

  @override
  State<TipperAdminEditPage> createState() => _FormEditTipperState();
}

class _FormEditTipperState extends State<TipperAdminEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _tipperNameController;
  late TextEditingController _tipperEmailController;
  final FocusNode _emailFocusNode = FocusNode();
  late Tipper? tipper;
  late bool admin;
  late TippersViewModel tippersViewModel;

  late bool disableBackButton = false;
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
      await tippersViewModel.updateTipperAttribute(
          tipper!.dbkey!, "name", _tipperNameController.text);
      await tippersViewModel.updateTipperAttribute(
          tipper!.dbkey!, "email", _tipperEmailController.text);
      await tippersViewModel.updateTipperAttribute(
          tipper!.dbkey!,
          "tipperRole",
          admin == true
              ? TipperRole.admin.toString().toString().split('.').last
              : TipperRole.tipper.toString().toString().split('.').last);

      //String compsParticipatedInJson = jsonEncode(
      //    tipper!.compsParticipatedIn.map((comp) => comp.dbkey).toList());

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
                          disableBackButton = true;
                          const CircularProgressIndicator();
                          _saveTipper(
                              context); //save the tipper and pop the page
                          setState(() {
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
                      enabled: !disableBackButton,
                      controller: _tipperEmailController,
                      decoration: const InputDecoration(
                        hintText: 'Tipper email',
                      ),
                      validator: (String? value) {
                        if (value == null || !EmailValidator.validate(value)) {
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
                        builder: (context, tippersViewModelConsumer, child) {
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
                                  ScaffoldMessenger.of(context).showSnackBar(
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
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text('No Records');
                    } else {
                      comps = snapshot.data!;
                      // sort the comps by name descending
                      comps.sort((a, b) => b.name.compareTo(a.name));
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
      ),
    );
  }
}
