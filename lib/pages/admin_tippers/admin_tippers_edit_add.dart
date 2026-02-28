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

  late String _originalName;
  late String _originalEmail;
  late String _originalLogon;
  late bool _originalAdmin;

  bool _hasDraftChanges = false;
  bool _manualSaveInProgress = false;
  bool _paidForAutoSaveInProgress = false;
  bool _allowPop = false;

  bool get _isBusy => _manualSaveInProgress || _paidForAutoSaveInProgress;
  bool get _canSave => _hasDraftChanges && !_isBusy;

  @override
  void initState() {
    super.initState();
    tipper = widget.tipper;

    tippersViewModel = widget.tippersViewModel;
    admin = tipper.tipperRole == TipperRole.admin;
    _tipperNameController = TextEditingController(text: tipper.name);
    _tipperEmailController = TextEditingController(text: tipper.email ?? '');
    _tipperLogonController = TextEditingController(text: tipper.logon ?? '');

    _originalName = tipper.name;
    _originalEmail = tipper.email ?? '';
    _originalLogon = tipper.logon ?? '';
    _originalAdmin = admin;
  }

  @override
  void dispose() {
    _tipperNameController.dispose();
    _tipperEmailController.dispose();
    _tipperLogonController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  void _refreshDraftState() {
    final bool hasChanges =
        _tipperNameController.text != _originalName ||
        _tipperEmailController.text != _originalEmail ||
        _tipperLogonController.text != _originalLogon ||
        admin != _originalAdmin;

    if (_hasDraftChanges == hasChanges) return;
    setState(() {
      _hasDraftChanges = hasChanges;
    });
  }

  Future<bool> _confirmDiscardDraftChanges(BuildContext context) async {
    if (!_hasDraftChanges) return true;
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: const Text(
          'You have unsaved changes. Do you really want to discard them?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  void _setCompPaidForState(DAUComp comp, bool isPaid) {
    final bool isAlreadyPaid = tipper.compsPaidFor.any(
      (paidComp) => paidComp.dbkey == comp.dbkey,
    );

    if (isPaid && !isAlreadyPaid) {
      tipper.compsPaidFor.add(comp);
    }

    if (!isPaid && isAlreadyPaid) {
      tipper.compsPaidFor.removeWhere((paidComp) => paidComp.dbkey == comp.dbkey);
    }
  }

  Future<void> _savePaidCompSelection(DAUComp comp, bool isPaid) async {
    if (_isBusy || tipper.dbkey == null) return;

    final bool previousValue = tipper.paidForComp(comp);
    if (previousValue == isPaid) return;

    setState(() {
      _setCompPaidForState(comp, isPaid);
      _paidForAutoSaveInProgress = true;
    });

    bool saveFailed = false;
    try {
      await tippersViewModel.updateTipperAttribute(
        tipper.dbkey!,
        "compsParticipatedIn",
        tipper.compsPaidFor.map((paidComp) => paidComp.dbkey).toList(),
      );
      await tippersViewModel.saveBatchOfTipperChangesToDb();
    } on Exception catch (e) {
      log('Failed to auto-save paid competitions change for ${tipper.dbkey}: $e');
      saveFailed = true;
    }

    if (!mounted) return;

    setState(() {
      if (saveFailed) {
        _setCompPaidForState(comp, previousValue);
      }
      _paidForAutoSaveInProgress = false;
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: saveFailed ? Colors.red : Colors.green,
        content: Text(
          saveFailed
              ? 'Could not save paid status change. Please try again.'
              : 'Paid status saved.',
        ),
      ),
    );
  }

  Future<bool> _saveTipper(BuildContext context) async {
    try {
      // make sure the email and logon are not assigned to another tipper
      Tipper? tipperWithDupEmail = await tippersViewModel
          .isEmailOrLogonAlreadyAssigned(
            _tipperEmailController.text,
            _tipperLogonController.text,
            tipper,
          );
      if (tipperWithDupEmail != null) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              content: Text(
                'The email ${tipperWithDupEmail.email} or logon ${tipperWithDupEmail.logon} is already assigned to tipper ${tipperWithDupEmail.name}',
              ),
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
        return false;
      }

      if (tipper.dbkey == null) {
        return false;
      }

      await tippersViewModel.updateTipperAttribute(
        tipper.dbkey!,
        "name",
        _tipperNameController.text,
      );
      await tippersViewModel.updateTipperAttribute(
        tipper.dbkey!,
        "email",
        _tipperEmailController.text,
      );
      await tippersViewModel.updateTipperAttribute(
        tipper.dbkey!,
        "logon",
        _tipperLogonController.text,
      );
      await tippersViewModel.updateTipperAttribute(
        tipper.dbkey!,
        "tipperRole",
        admin == true
            ? TipperRole.admin.toString().split('.').last
            : TipperRole.tipper.toString().split('.').last,
      );

      await tippersViewModel.updateTipperAttribute(
        tipper.dbkey!,
        "compsParticipatedIn",
        tipper.compsPaidFor.map((comp) => comp.dbkey).toList(),
      );

      await tippersViewModel.saveBatchOfTipperChangesToDb();

      return true;
    } on Exception catch (e) {
      log('Failed to update tipper ${tipper.dbkey}: $e');
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            content: const Text('Failed to update Tipper record'),
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
      return false;
    }
  }

  Future<void> _onSavePressed(BuildContext context) async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() {
      _manualSaveInProgress = true;
    });

    final bool didSave = await _saveTipper(context);
    if (!mounted) return;

    setState(() {
      _manualSaveInProgress = false;
    });

    if (didSave && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBusy && (_allowPop || !_hasDraftChanges),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !mounted || _isBusy) return;
        final navigator = Navigator.of(context);
        final bool shouldPop = await _confirmDiscardDraftChanges(context);
        if (!shouldPop || !mounted) return;
        setState(() {
          _allowPop = true;
        });
        navigator.pop(result);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (BuildContext context) {
              return IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _isBusy
                    ? null
                    : () {
                        Navigator.maybePop(context);
                      },
              );
            },
          ),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _canSave ? () => _onSavePressed(context) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                icon: _manualSaveInProgress
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: League.nrl.colour,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _manualSaveInProgress ? 'Saving...' : 'Save',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
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
                          enabled: !_isBusy,
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
                          onChanged: (_) => _refreshDraftState(),
                        ),
                      ),
                    ],
                  ),

                  Row(
                    children: [
                      const Text('Email:'),
                      Expanded(
                        child: TextFormField(
                          enabled: !_isBusy,
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
                          onChanged: (_) => _refreshDraftState(),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Logon:'),
                      Expanded(
                        child: TextFormField(
                          enabled: !_isBusy,
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
                          onChanged: (_) => _refreshDraftState(),
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
                        thumbColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.orange
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() {
                            admin = value;
                            _hasDraftChanges =
                                _tipperNameController.text != _originalName ||
                                _tipperEmailController.text != _originalEmail ||
                                _tipperLogonController.text != _originalLogon ||
                                admin != _originalAdmin;
                          });
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
                                builder: (context, tippersViewModelConsumer, child) {
                                  return Switch(
                                    value:
                                        (tippersViewModelConsumer.inGodMode &&
                                        tippersViewModelConsumer
                                                .selectedTipper ==
                                            tipper),
                                    thumbColor:
                                        WidgetStateProperty.resolveWith(
                                      (states) => states
                                              .contains(WidgetState.selected)
                                          ? Colors.red
                                          : null,
                                    ),
                                    onChanged: (value) {
                                      if (value == true) {
                                        // admins cannot god mode themselves - display snackbar if they try
                                        if (tippersViewModelConsumer
                                                .authenticatedTipper ==
                                            tipper) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              backgroundColor: Colors.red,
                                              content: const Text(
                                                'For technical reasons, admins cannot god mode themselves.\n\nAsk another admin to do it for you.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        // if godmode is already turned on for another tipper
                                        // then continue with this change, but display a snackbar
                                        // saying we turned it off for tipper A, and turned it on here for tipper B
                                        if (tippersViewModelConsumer
                                            .inGodMode) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              backgroundColor: Colors.red,
                                              content: Text(
                                                'God mode changed from ${tippersViewModelConsumer.selectedTipper.name} to ${tipper.name}',
                                              ),
                                            ),
                                          );
                                        }

                                        tippersViewModelConsumer
                                                .selectedTipper =
                                            tipper;
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
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  // add a row for 'Paid Comps', display a list of all DAUComps
                  // if the tipper is a paid up member, then show a tick
                  // allow the admin to edit which comps this tipper has paid for
                  FutureBuilder<List<DAUComp>>(
                    future: di<DAUCompsViewModel>().getDAUcomps(),
                    builder:
                        (
                          BuildContext context,
                          AsyncSnapshot<List<DAUComp>> snapshot,
                        ) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: League.nrl.colour,
                              ),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Text('No Records');
                          } else {
                            final List<DAUComp> comps = snapshot.data!;
                            // sort the comps by name descending
                            comps.sort(
                              (a, b) => b.name.toLowerCase().compareTo(
                                a.name.toLowerCase(),
                              ),
                            );
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Select the competitions this tipper has paid for:',
                                    ),
                                    if (_paidForAutoSaveInProgress)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                DataTable(
                                  sortColumnIndex: 1,
                                  sortAscending: true,
                                  columns: const [
                                    DataColumn(label: Text('Paid')),
                                    DataColumn(label: Text('Competition Name')),
                                  ],
                                  rows: comps
                                      .map(
                                        (comp) => DataRow(
                                          cells: [
                                            DataCell(
                                              Checkbox(
                                                value: tipper.paidForComp(comp),
                                                onChanged: _isBusy
                                                    ? null
                                                    : (bool? value) {
                                                        log('Checkbox changed to $value');
                                                        if (value == null) return;
                                                        _savePaidCompSelection(comp, value);
                                                      },
                                              ),
                                            ),
                                            DataCell(Text(comp.name)),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            );
                          }
                        },
                  ),
                ],
              ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isBusy
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminTipperMergeEditPage(
                              widget.tippersViewModel,
                              tipper,
                            ),
                          ),
                        );
                      },
                child: const Text('Merge...'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
