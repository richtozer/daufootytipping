import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
// import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart'; // No longer directly used here
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_warning.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_rounds_table.dart'; // Import the new widget
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_buttons.dart'; // Import the new buttons
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_form.dart'; // Import the new form widget
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http; // No longer needed here
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

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers for round start and end dates are now managed by AdminDaucompsEditRoundsTable

  @override
  void initState() {
    super.initState();
    _initTextControllersListeners();
    // _initializeRoundControllers(); // Removed
    _updateSaveButtonState();
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
    widget._nrlRegularCompEndDateController.removeListener(_updateSaveButtonState);
    widget._aflRegularCompEndDateController.removeListener(_updateSaveButtonState);
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
      widget._nrlRegularCompEndDateController.text !=
              (widget.daucomp!.nrlRegularCompEndDateUTC != null
                  ? DateFormat('yyyy-MM-dd')
                      .format(widget.daucomp!.nrlRegularCompEndDateUTC!)
                  : '') ||
          widget._aflRegularCompEndDateController.text !=
              (widget.daucomp!.aflRegularCompEndDateUTC != null
                  ? DateFormat('yyyy-MM-dd')
                      .format(widget.daucomp!.aflRegularCompEndDateUTC!)
                  : '');
    }

    log('shouldEnableSave = $shouldEnableSave');

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
        currentRounds: dauCompsViewModel.selectedDAUComp?.daurounds ?? [], // Added this line
      );

      if (!mounted) return; // Check if the widget is still in the tree

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(result['message'] ?? 'Operation successful'),
            duration: const Duration(seconds: 4),
          ),
        );
        // Optionally, if new comp data is returned and needs to be used immediately by UI:
        // if (widget.daucomp == null && result['newCompData'] != null) {
        //   // Potentially update state or trigger a refresh if staying on page
        // }
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'An error occurred'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on Exception catch (e) { // Catching specific Exception type
      log("Exception in _saveDAUComp UI layer: $e");
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          content: const Text('Failed to update the DAU Comp record'), // Generic message
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
                      daucompAflJsonURLController: widget._daucompAflJsonURLController,
                      daucompNrlJsonURLController: widget._daucompNrlJsonURLController,
                      nrlRegularCompEndDateController: widget._nrlRegularCompEndDateController,
                      aflRegularCompEndDateController: widget._aflRegularCompEndDateController,
                      dauCompsViewModel: dauCompsViewModeconsumer,
                      onFormInteracted: () {
                        setState(() {
                          disableSaves = false;
                        });
                      },
                    ),
                    if (widget.daucomp != null) ...[
                      if (dauCompsViewModeconsumer.unassignedGames.isNotEmpty)
                        AdminDaucompsEditWarning(viewModel: dauCompsViewModeconsumer),
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
                        rounds: dauCompsViewModeconsumer.activeDAUComp?.daurounds.where((r) => r.games.isNotEmpty).toList() ?? [],
                        onRoundDateChanged: (DAURound round, DateTime newDate, bool isStartDate) {
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
      dauCompsViewModel.linkGamesWithRounds(dauCompsViewModel.selectedDAUComp!.daurounds);
    }
  }

  // buttonFixture method is now removed
  // buttonScoring method is now removed
}
