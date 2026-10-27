import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tipper_merge.dart';
import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import 'package:intl/intl.dart';
import 'package:watch_it/watch_it.dart';

/// How a save of the tipper record ended.
enum _SaveOutcome {
  /// The server accepted the change.
  saved,

  /// The change is queued on this device; the server has not answered yet.
  queued,

  /// The change was rejected, or could not be started.
  notSaved,
}

class TipperAdminEditPage extends StatefulWidget {
  static const Key nameFieldKey = ValueKey('tipper-admin-name-field');
  static const Key emailFieldKey = ValueKey('tipper-admin-email-field');
  static const Key logonFieldKey = ValueKey('tipper-admin-logon-field');
  static const Key lastLoginFieldKey = ValueKey(
    'tipper-admin-last-login-field',
  );
  static const Key emailInfoButtonKey = ValueKey(
    'tipper-admin-email-info-button',
  );

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
  late TextEditingController _tipperLastLoginController;

  final FocusNode _emailFocusNode = FocusNode();
  late Tipper tipper;
  late bool admin;
  late TippersViewModel tippersViewModel;

  late String _originalName;
  late String _originalEmail;
  late String _originalLogon;
  late bool _originalAdmin;
  late Set<String> _originalPaidCompKeys;

  /// The comps ticked as paid. A draft, like the fields, until Save writes it.
  late Set<String> _paidCompKeys;

  /// Fetched once, so ticking a comp does not reload the table.
  late final Future<List<DAUComp>> _compsFuture;

  bool _hasDraftChanges = false;
  bool _manualSaveInProgress = false;
  bool _godModeChangeInProgress = false;
  bool _allowPop = false;

  bool get _isBusy => _manualSaveInProgress || _godModeChangeInProgress;
  bool get _canSave => _hasDraftChanges && !_isBusy;
  bool get _shouldCollapseLogon =>
      _sameEmail(_tipperEmailController.text, _tipperLogonController.text);

  String _formatLastLogin(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Never';
    }
    return DateFormat('dd MMM yy HH:mm').format(dateTime.toLocal());
  }

  bool _sameEmail(String? firstEmail, String? secondEmail) {
    final String normalizedFirstEmail = firstEmail?.trim().toLowerCase() ?? '';
    final String normalizedSecondEmail =
        secondEmail?.trim().toLowerCase() ?? '';
    return normalizedFirstEmail.isNotEmpty &&
        normalizedFirstEmail == normalizedSecondEmail;
  }

  @override
  void initState() {
    super.initState();
    tipper = widget.tipper;

    tippersViewModel = widget.tippersViewModel;
    admin = tipper.tipperRole == TipperRole.admin;
    _tipperNameController = TextEditingController(text: tipper.name);
    _tipperEmailController = TextEditingController(text: tipper.email ?? '');
    _tipperLogonController = TextEditingController(text: tipper.logon ?? '');
    _tipperLastLoginController = TextEditingController(
      text: _formatLastLogin(tipper.acctLoggedOnUTC),
    );

    _originalName = tipper.name;
    _originalEmail = tipper.email ?? '';
    _originalLogon = tipper.logon ?? '';
    _originalAdmin = admin;
    _originalPaidCompKeys = {
      for (final DAUComp comp in tipper.compsPaidFor) ?comp.dbkey,
    };
    _paidCompKeys = {..._originalPaidCompKeys};
    _compsFuture = di<DAUCompsViewModel>().getDAUcomps();
  }

  @override
  void dispose() {
    _tipperNameController.dispose();
    _tipperEmailController.dispose();
    _tipperLogonController.dispose();
    _tipperLastLoginController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  void _refreshDraftState({bool forceRebuild = false}) {
    final bool hasChanges =
        _tipperNameController.text != _originalName ||
        _tipperEmailController.text != _originalEmail ||
        _tipperLogonController.text != _originalLogon ||
        admin != _originalAdmin ||
        !setEquals(_paidCompKeys, _originalPaidCompKeys);

    if (_hasDraftChanges == hasChanges && !forceRebuild) return;
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

  void _setCompPaid(DAUComp comp, bool isPaid) {
    final String? compKey = comp.dbkey;
    if (compKey == null) return;
    if (isPaid) {
      _paidCompKeys.add(compKey);
    } else {
      _paidCompKeys.remove(compKey);
    }
    _refreshDraftState(forceRebuild: true);
  }

  String _queuedMessage(String change) =>
      '$change is queued on this device. The server has not confirmed it yet; '
      'it will apply when the connection recovers.';

  Future<_SaveOutcome> _saveTipper(BuildContext context) async {
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
        return _SaveOutcome.notSaved;
      }

      if (tipper.dbkey == null) {
        return _SaveOutcome.notSaved;
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
        "tipperRole",
        admin == true
            ? TipperRole.admin.toString().split('.').last
            : TipperRole.tipper.toString().split('.').last,
      );

      await tippersViewModel.updateTipperAttribute(
        tipper.dbkey!,
        "compsParticipatedIn",
        _paidCompKeys.toList(),
      );

      await tippersViewModel.saveBatchOfTipperChangesToDb(
        acknowledgementLimit: defaultWriteAcknowledgementLimit,
      );

      return _SaveOutcome.saved;
    } on WriteNotConfirmedException catch (e) {
      log('Tipper ${tipper.dbkey} update is queued: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
            content: Text(_queuedMessage('Your change')),
          ),
        );
      }
      return _SaveOutcome.queued;
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
      return _SaveOutcome.notSaved;
    }
  }

  Future<void> _onSavePressed(BuildContext context) async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() {
      _manualSaveInProgress = true;
    });

    final _SaveOutcome outcome = await _saveTipper(context);
    if (!mounted) return;

    setState(() {
      _manualSaveInProgress = false;
    });

    if (outcome != _SaveOutcome.notSaved && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  bool _isGodModeTipper(TippersViewModel viewModel) =>
      viewModel.inGodMode && viewModel.selectedTipper.dbkey == tipper.dbkey;

  /// God mode is not part of the tipper record, so it sits with Save in the
  /// floating controls as an action that takes effect at once, rather than
  /// among the fields waiting for Save. There is no god mode without a comp.
  AppGlassAction? _godModeAction(BuildContext context) {
    if (di<DAUCompsViewModel>().selectedDAUComp == null) return null;
    final TippersViewModel viewModel = di<TippersViewModel>();
    final bool isGodModeTipper = _isGodModeTipper(viewModel);
    return AppGlassAction.text(
      label: isGodModeTipper ? 'Exit God Mode' : 'God Mode',
      // Red, as the god mode banner and the god mode tipper's row are.
      colour: isGodModeTipper ? Colors.red : null,
      onPressed: _isBusy ? null : () => _onGodModePressed(context, viewModel),
    );
  }

  /// Turns god mode on for this tipper, or off if it is already on for them,
  /// then goes back to the tipper list.
  Future<void> _onGodModePressed(
    BuildContext context,
    TippersViewModel viewModel,
  ) async {
    final Tipper? authenticatedTipper = viewModel.authenticatedTipper;
    if (authenticatedTipper == null) return;
    final bool isGodModeTipper = _isGodModeTipper(viewModel);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    if (!isGodModeTipper && authenticatedTipper.dbkey == tipper.dbkey) {
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'For technical reasons, admins cannot god mode themselves.\n\nAsk another admin to do it for you.',
          ),
        ),
      );
      return;
    }

    if (!await _confirmDiscardDraftChanges(context) || !mounted) return;

    final String? previousGodModeTipperName =
        viewModel.inGodMode && !isGodModeTipper
        ? viewModel.selectedTipper.name
        : null;
    setState(() {
      _godModeChangeInProgress = true;
    });

    try {
      await viewModel.changeSelectedTipperAfterRefresh(
        isGodModeTipper ? authenticatedTipper : tipper,
        refreshSelectedTipperViewModels: () =>
            di<DAUCompsViewModel>().selectedTipperChanged(),
      );
    } catch (error, stackTrace) {
      log(
        'TipperAdminEditPage: failed to change god mode tipper: $error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _godModeChangeInProgress = false;
        });
      }
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Could not refresh tips for god mode. Please try again.',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    if (previousGodModeTipperName != null) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'God mode changed from $previousGodModeTipperName to ${tipper.name}',
          ),
        ),
      );
    }
    navigator.pop();
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
      // Back is the floating control's maybePop, which the PopScope above holds
      // while a save runs and answers with the discard prompt.
      child: AppAdminPage(
        title: 'Edit Tipper',
        actions: [
          AppGlassAction.text(
            label: 'Merge',
            onPressed: _isBusy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminTipperMergeEditPage(
                        widget.tippersViewModel,
                        tipper,
                      ),
                    ),
                  ),
          ),
          ?_godModeAction(context),
          AppGlassAction(
            icon: _manualSaveInProgress ? Icons.hourglass_bottom : Icons.save,
            label: 'Save',
            onPressed: _canSave ? () => _onSavePressed(context) : null,
          ),
        ],
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
                        const Text(
                          'Name:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: TipperAdminEditPage.nameFieldKey,
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
                        const SizedBox(width: 12),
                        const Text(
                          'DAU\nAdmin:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Switch(
                          value: admin,
                          thumbColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Colors.orange
                                : null,
                          ),
                          onChanged: (value) {
                            admin = value;
                            _refreshDraftState(forceRebuild: true);
                          },
                        ),
                      ],
                    ),

                    Row(
                      children: [
                        const Text(
                          'Email:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: TipperAdminEditPage.emailFieldKey,
                            enabled: !_isBusy,
                            controller: _tipperEmailController,
                            decoration: InputDecoration(
                              hintText: 'Email for communications',
                              suffixIcon: _shouldCollapseLogon
                                  ? IconButton(
                                      key: TipperAdminEditPage
                                          .emailInfoButtonKey,
                                      icon: const Icon(
                                        Icons.info_outline,
                                        size: 18,
                                      ),
                                      tooltip: 'Email info',
                                      onPressed: () {
                                        showDialog<void>(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              content: const Text(
                                                'Login and communications emails are the same',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                  },
                                                  child: const Text('OK'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    )
                                  : null,
                            ),
                            validator: (String? value) {
                              if (value == null ||
                                  !EmailValidator.validate(value)) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                            onChanged: (_) =>
                                _refreshDraftState(forceRebuild: true),
                          ),
                        ),
                      ],
                    ),
                    if (!_shouldCollapseLogon)
                      Row(
                        children: [
                          const Text(
                            'Logon:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: TextFormField(
                              key: TipperAdminEditPage.logonFieldKey,
                              enabled: !_isBusy,
                              readOnly: true,
                              controller: _tipperLogonController,
                              decoration: const InputDecoration(
                                hintText: 'Email for logon',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        const Text(
                          'Last\nLogin:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: TipperAdminEditPage.lastLoginFieldKey,
                            enabled: !_isBusy,
                            readOnly: true,
                            controller: _tipperLastLoginController,
                            decoration: const InputDecoration(
                              hintText: 'Last login time',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // add a row for 'Paid Comps', display a list of all DAUComps
                    // if the tipper is a paid up member, then show a tick
                    // allow the admin to edit which comps this tipper has paid for
                    FutureBuilder<List<DAUComp>>(
                      future: _compsFuture,
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
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  DataTable(
                                    sortColumnIndex: 1,
                                    sortAscending: true,
                                    columns: const [
                                      DataColumn(label: Text('Paid')),
                                      DataColumn(
                                        label: Text('Competition Name'),
                                      ),
                                    ],
                                    rows: comps
                                        .map(
                                          (comp) => DataRow(
                                            cells: [
                                              DataCell(
                                                Checkbox(
                                                  value:
                                                      tipper.isAnonymous ||
                                                      _paidCompKeys.contains(
                                                        comp.dbkey,
                                                      ),
                                                  onChanged: _isBusy
                                                      ? null
                                                      : (bool? value) =>
                                                            _setCompPaid(
                                                              comp,
                                                              value ?? false,
                                                            ),
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
            ],
          ),
        ),
      ),
    );
  }
}
