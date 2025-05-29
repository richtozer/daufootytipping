import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_warning.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_rounds_table.dart'; // Import the new widget
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_buttons.dart'; // Import the new buttons
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_form.dart'; // Import the new form widget
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class DAUCompsEditPage extends StatefulWidget {
  final DAUComp? daucomp;

  late final TextEditingController _daucompNameController;
  late final TextEditingController _daucompAflJsonURLController;
  late final TextEditingController _daucompNrlJsonURLController;
  late final TextEditingController _nrlRegularCompEndDateController;
  late final TextEditingController _aflRegularCompEndDateController;

  DAUCompsEditPage(this.daucomp, {super.key}) {
    _daucompNameController = TextEditingController(text: daucomp?.name);
    _daucompAflJsonURLController =
        TextEditingController(text: daucomp?.aflFixtureJsonURL.toString());
    _daucompNrlJsonURLController =
        TextEditingController(text: daucomp?.nrlFixtureJsonURL.toString());
    _nrlRegularCompEndDateController = TextEditingController(
        text: daucomp?.nrlRegularCompEndDateUTC != null
            ? DateFormat('yyyy-MM-dd')
                .format(daucomp!.nrlRegularCompEndDateUTC!)
            : '');
    _aflRegularCompEndDateController = TextEditingController(
        text: daucomp?.aflRegularCompEndDateUTC != null
            ? DateFormat('yyyy-MM-dd')
                .format(daucomp!.aflRegularCompEndDateUTC!)
            : '');
  }

  @override
  State<DAUCompsEditPage> createState() => _DAUCompsEditPageState();
}

class _DAUCompsEditPageState extends State<DAUCompsEditPage> {
  bool disableSaves = true;
  bool disableBack = false;
  bool _localActiveCompState = false;
  // Initial value, will be correctly set in initState

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers for round start and end dates are now managed by AdminDaucompsEditRoundsTable

  @override
  void initState() {
    super.initState();
    // Correct initialization of _localActiveCompState
    if (widget.daucomp != null) {
      final globalDauCompsVM = di<
          DAUCompsViewModel>(); // Assuming DAUCompsViewModel is registered with WatchIt
      _localActiveCompState = globalDauCompsVM.initDAUCompDbKey != null &&
          widget.daucomp!.dbkey == globalDauCompsVM.initDAUCompDbKey;
    } else {
      _localActiveCompState = false; // New comps are not active by default
    }

    _initTextControllersListeners();
    _updateSaveButtonState(); // Call after _localActiveCompState is set
  }

  @override
  void dispose() {
    // Dispose all controllers
    // for (var controller in _startDateControllers.values) { // Removed
    //   controller.dispose();
    // }
    // for (var controller in _endDateControllers.values) { // Removed
    //   controller.dispose();
    // }
    widget._daucompNameController.removeListener(_updateSaveButtonState);
    widget._daucompAflJsonURLController.removeListener(_updateSaveButtonState);
    widget._daucompNrlJsonURLController.removeListener(_updateSaveButtonState);
    widget._nrlRegularCompEndDateController
        .removeListener(_updateSaveButtonState);
    widget._aflRegularCompEndDateController
        .removeListener(_updateSaveButtonState);
    super.dispose();
  }

  void _initTextControllersListeners() {
    widget._daucompNameController.addListener(_updateSaveButtonState);
    widget._daucompAflJsonURLController.addListener(_updateSaveButtonState);
    widget._daucompNrlJsonURLController.addListener(_updateSaveButtonState);
    widget._nrlRegularCompEndDateController.addListener(_updateSaveButtonState);
    widget._aflRegularCompEndDateController.addListener(_updateSaveButtonState);
  }

  // _initializeRoundControllers() removed

  void _updateSaveButtonState() {
    bool shouldEnableSave;
    bool originalActiveStatus = false;
    if (widget.daucomp != null) {
      final globalDauCompsVM = di<DAUCompsViewModel>();
      originalActiveStatus = globalDauCompsVM.initDAUCompDbKey != null &&
          widget.daucomp!.dbkey == globalDauCompsVM.initDAUCompDbKey;
    }

    if (widget.daucomp == null) {
      shouldEnableSave = widget._daucompNameController.text.isNotEmpty &&
          widget._daucompAflJsonURLController.text.isNotEmpty &&
          widget._daucompNrlJsonURLController.text.isNotEmpty;
      // For new comps, also consider if _localActiveCompState is true (if we allow setting new comp as active immediately)
      // Based on current logic, new comp is only set active on save, so _localActiveCompState change might not enable save alone.
      // However, if other fields are filled, and user toggles active, it should be saveable.
      // The original logic didn't factor in _localActiveCompState for new comps for enabling save.
      // Let's assume any interaction makes it saveable if basic fields are there.
      // The original logic for new comp save was only based on text fields.
      // Adding `|| _localActiveCompState` might be too aggressive if other fields are empty.
      // The current `onFormInteracted` in AdminDaucompsEditForm handles `disableSaves = false;`
      // which then calls this. So, we just need to ensure the condition includes active state change.
    } else {
      shouldEnableSave =
          (widget._daucompNameController.text != widget.daucomp!.name ||
                  widget._daucompAflJsonURLController.text !=
                      widget.daucomp!.aflFixtureJsonURL.toString() ||
                  widget._daucompNrlJsonURLController.text !=
                      widget.daucomp!.nrlFixtureJsonURL.toString() ||
                  widget._nrlRegularCompEndDateController.text !=
                      (widget.daucomp!.nrlRegularCompEndDateUTC != null
                          ? DateFormat('yyyy-MM-dd')
                              .format(widget.daucomp!.nrlRegularCompEndDateUTC!)
                          : '') ||
                  widget._aflRegularCompEndDateController.text !=
                      (widget.daucomp!.aflRegularCompEndDateUTC != null
                          ? DateFormat('yyyy-MM-dd')
                              .format(widget.daucomp!.aflRegularCompEndDateUTC!)
                          : '')) ||
              (_localActiveCompState !=
                  originalActiveStatus); // Added this condition
    }

    log('shouldEnableSave = $shouldEnableSave, _localActiveCompState = $_localActiveCompState, originalActiveStatus = $originalActiveStatus');

    if (disableSaves != !shouldEnableSave) {
      setState(() {
        disableSaves = !shouldEnableSave;
      });
      log('state change disableSaves = $disableSaves');
    }
  }

  Future<void> _saveDAUComp(
      DAUCompsViewModel dauCompsViewModel, BuildContext context) async {
    try {
      // Prepare data for the ViewModel call
      String name = widget._daucompNameController.text;
      String aflUrl = widget._daucompAflJsonURLController.text;
      String nrlUrl = widget._daucompNrlJsonURLController.text;
      String? nrlEndDate = widget._nrlRegularCompEndDateController.text;
      String? aflEndDate = widget._aflRegularCompEndDateController.text;

      // Call the ViewModel method
      var result = await dauCompsViewModel.processAndSaveDauComp(
        name: name,
        aflFixtureJsonURL: aflUrl,
        nrlFixtureJsonURL: nrlUrl,
        nrlRegularCompEndDateString: nrlEndDate.isNotEmpty ? nrlEndDate : null,
        aflRegularCompEndDateString: aflEndDate.isNotEmpty ? aflEndDate : null,
        existingComp: widget.daucomp,
        currentRounds: dauCompsViewModel.selectedDAUComp?.daurounds ??
            [], // Added this line
      );

      if (!mounted) return; // Check if the widget is still in the tree

      if (result['success'] == true) {
        String? targetCompDbKey = widget.daucomp?.dbkey;
        if (widget.daucomp == null && result['newCompData'] != null) {
          targetCompDbKey = (result['newCompData'] as DAUComp?)?.dbkey;
        }

        if (targetCompDbKey != null) {
          bool persistedActiveStatus = false;
          final globalDauCompsVM = di<DAUCompsViewModel>();
          if (globalDauCompsVM.initDAUCompDbKey != null) {
            persistedActiveStatus =
                targetCompDbKey == globalDauCompsVM.initDAUCompDbKey;
          }

          // If locally marked active AND it's different from its persisted state OR it's a new comp being marked active
          if (_localActiveCompState &&
              (_localActiveCompState != persistedActiveStatus ||
                  widget.daucomp == null)) {
            ConfigViewModel remoteConfigService = ConfigViewModel();
            await remoteConfigService.setConfigCurrentDAUComp(targetCompDbKey);
            log('Active comp set to: $targetCompDbKey via main save button');
            // Optionally refresh DAUCompsViewModel's activeDAUComp if necessary,
            // though changing initDAUCompDbKey in ConfigViewModel usually triggers wider app refresh.
            // dauCompsViewModel.changeDisplayedDAUComp(await dauCompsViewModel.findComp(targetCompDbKey), true); // Example
          }
          // No action needed if _localActiveCompState is false, as per plan (cannot deactivate this way).
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green,
              content: Text(result['message'] ?? 'Operation successful'),
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'An error occurred'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on Exception catch (e) {
      // Catching specific Exception type
      log("Exception in _saveDAUComp UI layer: $e");
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            content: const Text(
                'Failed to update the DAU Comp record'), // Generic message
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

  // isUriActive method removed

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DAUCompsViewModel>(
      create: (context) => DAUCompsViewModel(widget.daucomp?.dbkey, true),
      child: Scaffold(
          appBar: AppBar(
            leading: Builder(
              builder: (BuildContext context) {
                return IconButton(
                  icon: disableBack
                      ? const ImageIcon(null)
                      : const Icon(Icons.arrow_back),
                  onPressed: () async {
                    if (!disableBack) {
                      // changethe displayed comp back to the active comp
                      await di<DAUCompsViewModel>().changeDisplayedDAUComp(
                          di<DAUCompsViewModel>().activeDAUComp!, false);

                      if (context.mounted) {
                        Navigator.maybePop(context);
                      }
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
                                Navigator.of(context).pop(); // Close the dialog
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
              Consumer<DAUCompsViewModel>(
                builder: (context, dauCompsViewModel, child) {
                  return IconButton(
                    color: Colors.green,
                    disabledColor: Colors.grey,
                    icon: disableSaves
                        ? const Icon(Icons.save)
                        : Icon(Icons.save),
                    onPressed: disableSaves
                        ? null
                        : () async {
                            final isValid = _formKey.currentState!.validate();
                            if (isValid) {
                              setState(() {
                                disableSaves = true;
                                disableBack = true;
                              });

                              await _saveDAUComp(dauCompsViewModel, context);

                              setState(() {
                                disableSaves = true;
                                disableBack = false;
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
            // Form tag is removed from here and now lives in AdminDaucompsEditForm
            child: SingleChildScrollView(
              child: Consumer<DAUCompsViewModel>(
                  builder: (context, dauCompsViewModeconsumer, child) {
                // This is the mainColumn
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (widget.daucomp != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          AdminDaucompsEditFixtureButton(
                            dauCompsViewModel: dauCompsViewModeconsumer,
                            daucomp: widget.daucomp,
                            setStateCallback: (fn) => setState(fn),
                          ),
                          AdminDaucompsEditScoringButton(
                            dauCompsViewModel: dauCompsViewModeconsumer,
                            daucomp: widget.daucomp,
                            setStateCallback: (fn) => setState(fn),
                          ),
                        ],
                      ),
                    AdminDaucompsEditForm(
                      formKey: _formKey,
                      daucomp: widget.daucomp,
                      daucompNameController: widget._daucompNameController,
                      daucompAflJsonURLController:
                          widget._daucompAflJsonURLController,
                      daucompNrlJsonURLController:
                          widget._daucompNrlJsonURLController,
                      nrlRegularCompEndDateController:
                          widget._nrlRegularCompEndDateController,
                      aflRegularCompEndDateController:
                          widget._aflRegularCompEndDateController,
                      dauCompsViewModel: dauCompsViewModeconsumer,
                      onFormInteracted: () {
                        // This existing callback is fine for text field interactions.
                        // Active status changes are handled by onActiveStatusChangedLocally.
                        // We still want to enable save if other form fields change.
                        setState(() {
                          disableSaves = false;
                        });
                        _updateSaveButtonState(); // Ensure save button state considers all changes
                      },
                      isLocallyMarkedActive: _localActiveCompState,
                      onActiveStatusChangedLocally: (bool newValue) {
                        setState(() {
                          final globalDauCompsVM = di<DAUCompsViewModel>();
                          bool isCurrentGlobalActive = widget.daucomp != null &&
                              globalDauCompsVM.initDAUCompDbKey != null &&
                              widget.daucomp!.dbkey ==
                                  globalDauCompsVM.initDAUCompDbKey;

                          if (!newValue && isCurrentGlobalActive) {
                            // Tried to toggle off the currently globally active comp
                            // Do not change _localActiveCompState, it remains true (or rather, it's not set to false).
                            // The UI switch will revert because _localActiveCompState isn't updated to false.
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'You cannot turn off the active comp. Instead, edit another comp to be active.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            // To ensure the Switch widget visually reverts if the parent state wasn't actually changed to 'false':
                            // We don't set _localActiveCompState = false, so the existing _localActiveCompState (true) will be passed back in next build.
                          } else {
                            _localActiveCompState = newValue;
                            _updateSaveButtonState();
                          }
                        });
                      },
                    ),
                    if (widget.daucomp != null) ...[
                      if (dauCompsViewModeconsumer.unassignedGames.isNotEmpty)
                        AdminDaucompsEditWarning(
                            viewModel: dauCompsViewModeconsumer),
                      Row(
                        //mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              'Counts of games grouped by DAU round:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.info_outline),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text('Information'),
                                    content: const Text(
                                      'This is a list of round start and end times. Any game kickoff times that fall within this range are included in the round and counted by league.\n\nWhen the comp is first created and added in the app, these dates are automatically calculated based on round information provided in the fixture.\n\nIf needed, an Admin can override these dates as needed. If the date is bold then it has been subsequently changed and overridden by an admin.',
                                    ),
                                    actions: <Widget>[
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
                          ),
                        ],
                      ),
                      AdminDaucompsEditRoundsTable(
                        rounds: dauCompsViewModeconsumer
                                .activeDAUComp?.daurounds
                                .where((r) => r.games.isNotEmpty)
                                .toList() ??
                            [],
                        onRoundDateChanged: (DAURound round, DateTime newDate,
                            bool isStartDate) {
                          setState(() {
                            if (isStartDate) {
                              round.adminOverrideRoundStartDate = newDate;
                            } else {
                              round.adminOverrideRoundEndDate = newDate;
                            }
                            _recalculateGameCounts();
                            disableSaves = false;
                          });
                        },
                      ),
                    ],
                  ],
                );
              }),
            ),
          )),
    );
  }

  void _recalculateGameCounts() async {
    // Use the ViewModel's current selectedDAUComp for the most up-to-date rounds
    final dauCompsViewModel = di<DAUCompsViewModel>();
    if (dauCompsViewModel.selectedDAUComp != null &&
        dauCompsViewModel.selectedDAUComp!.daurounds.isNotEmpty) {
      dauCompsViewModel
          .linkGamesWithRounds(dauCompsViewModel.selectedDAUComp!.daurounds);
    }
  }

  // buttonFixture method is now removed
  // buttonScoring method is now removed
}
