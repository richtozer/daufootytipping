import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_warning.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_rounds_table.dart'; // Import the new widget
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_buttons.dart'; // Import the new buttons
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_form.dart'; // Import the new form widget
import 'package:daufootytipping/services/rounds_linking_service.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

@visibleForTesting
DAUCompsViewModel createAdminDauCompsViewModel({
  required String? compKey,
  required ConfigViewModel configViewModel,
  bool skipInit = false,
  String? cloudFunctionsBaseURLOverride,
}) {
  return DAUCompsViewModel(
    compKey,
    true,
    skipInit: skipInit,
    cloudFunctionsBaseURLOverride: cloudFunctionsBaseURLOverride,
    cloudFunctionsBaseURLProvider: () => configViewModel.cloudFunctionsBaseURL,
    adminScoringRescoreURLProvider: () =>
        configViewModel.adminScoringRescoreURL,
    adminScoringRescoreURLLoader: configViewModel.loadAdminScoringRescoreURL,
    adminCheckFixtureUrlURLProvider: () =>
        configViewModel.adminCheckFixtureUrlURL,
    adminCheckFixtureUrlURLLoader: configViewModel.loadAdminCheckFixtureUrlURL,
  );
}

class DAUCompsEditPage extends StatefulWidget {
  final DAUComp? daucomp;
  final DAUCompsViewModel? adminDauCompsViewModel;

  const DAUCompsEditPage(
    this.daucomp, {
    super.key,
    this.adminDauCompsViewModel,
  });

  @override
  State<DAUCompsEditPage> createState() => _DAUCompsEditPageState();
}

class _DAUCompsEditPageState extends State<DAUCompsEditPage> {
  bool disableSaves = true;
  bool disableBack = false;
  bool _localActiveCompState = false;
  late final DAUCompsViewModel _pageDauCompsViewModel;
  late final bool _ownsPageDauCompsViewModel;
  // Initial value, will be correctly set in initState
  late final TextEditingController _daucompNameController;
  late final TextEditingController _daucompAflJsonURLController;
  late final TextEditingController _daucompNrlJsonURLController;
  late final TextEditingController _nrlRegularCompEndDateController;
  late final TextEditingController _aflRegularCompEndDateController;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final RoundsLinkingService _roundsLinking = const RoundsLinkingService();
  late final Map<int, DateTime?> _initialRoundStartOverrides;
  late String _lastValidNrlCutoffText;
  late String _lastValidAflCutoffText;
  bool _isRevertingCutoff = false;

  /// What the Run updates action last showed, so the page rebuilds only when
  /// that changes.
  late ({bool ready, bool busy}) _shownRunUpdates;

  // Controllers for round start dates are managed by AdminDaucompsEditRoundsTable

  @override
  void initState() {
    super.initState();
    _ownsPageDauCompsViewModel = widget.adminDauCompsViewModel == null;
    _pageDauCompsViewModel =
        widget.adminDauCompsViewModel ??
        createAdminDauCompsViewModel(
          compKey: widget.daucomp?.dbkey,
          configViewModel: context.read<ConfigViewModel>(),
        );
    _shownRunUpdates = _runUpdatesState();
    _pageDauCompsViewModel.addListener(_refreshRunUpdatesAction);
    // The admin view models finish loading without notifying, and Run updates
    // needs them, so the page checks again once loading is done.
    unawaited(
      _pageDauCompsViewModel.otherViewModelsLoadComplete.then(
        (_) => _refreshRunUpdatesAction(),
      ),
    );
    _initialRoundStartOverrides = <int, DateTime?>{
      if (widget.daucomp != null)
        for (final r in widget.daucomp!.daurounds)
          r.dAUroundNumber: r.adminOverrideRoundStartDate,
    };
    _daucompNameController = TextEditingController(text: widget.daucomp?.name);
    _daucompAflJsonURLController = TextEditingController(
      text: widget.daucomp?.aflFixtureJsonURL.toString(),
    );
    _daucompNrlJsonURLController = TextEditingController(
      text: widget.daucomp?.nrlFixtureJsonURL.toString(),
    );
    _nrlRegularCompEndDateController = TextEditingController(
      text: widget.daucomp?.nrlRegularCompEndDateUTC != null
          ? DateFormat('yyyy-MM-dd')
                .format(widget.daucomp!.nrlRegularCompEndDateUTC!)
          : '',
    );
    _aflRegularCompEndDateController = TextEditingController(
      text: widget.daucomp?.aflRegularCompEndDateUTC != null
          ? DateFormat('yyyy-MM-dd')
                .format(widget.daucomp!.aflRegularCompEndDateUTC!)
          : '',
    );
    _lastValidNrlCutoffText = _nrlRegularCompEndDateController.text;
    _lastValidAflCutoffText = _aflRegularCompEndDateController.text;
    // Correct initialization of _localActiveCompState
    if (widget.daucomp != null) {
      final globalDauCompsVM =
          di<
            DAUCompsViewModel
          >(); // Assuming DAUCompsViewModel is registered with WatchIt
      _localActiveCompState =
          globalDauCompsVM.initDAUCompDbKey != null &&
          widget.daucomp!.dbkey == globalDauCompsVM.initDAUCompDbKey;
    } else {
      _localActiveCompState = false; // New comps are not active by default
    }

    _initTextControllersListeners();
    _updateSaveButtonState(); // Call after _localActiveCompState is set
  }

  @override
  void dispose() {
    _daucompNameController.removeListener(_updateSaveButtonState);
    _daucompAflJsonURLController.removeListener(_updateSaveButtonState);
    _daucompNrlJsonURLController.removeListener(_updateSaveButtonState);
    _nrlRegularCompEndDateController.removeListener(_onNrlCutoffChanged);
    _aflRegularCompEndDateController.removeListener(_onAflCutoffChanged);
    _daucompNameController.dispose();
    _daucompAflJsonURLController.dispose();
    _daucompNrlJsonURLController.dispose();
    _nrlRegularCompEndDateController.dispose();
    _aflRegularCompEndDateController.dispose();
    _pageDauCompsViewModel.removeListener(_refreshRunUpdatesAction);
    if (_ownsPageDauCompsViewModel) {
      _pageDauCompsViewModel.dispose();
    }
    super.dispose();
  }

  void _initTextControllersListeners() {
    _daucompNameController.addListener(_updateSaveButtonState);
    _daucompAflJsonURLController.addListener(_updateSaveButtonState);
    _daucompNrlJsonURLController.addListener(_updateSaveButtonState);
    _nrlRegularCompEndDateController.addListener(_onNrlCutoffChanged);
    _aflRegularCompEndDateController.addListener(_onAflCutoffChanged);
  }

  void _onNrlCutoffChanged() => _handleCutoffControllerChanged(
    League.nrl,
    _nrlRegularCompEndDateController,
    lastValid: _lastValidNrlCutoffText,
    setLastValid: (value) => _lastValidNrlCutoffText = value,
  );

  void _onAflCutoffChanged() => _handleCutoffControllerChanged(
    League.afl,
    _aflRegularCompEndDateController,
    lastValid: _lastValidAflCutoffText,
    setLastValid: (value) => _lastValidAflCutoffText = value,
  );

  void _handleCutoffControllerChanged(
    League league,
    TextEditingController controller, {
    required String lastValid,
    required void Function(String value) setLastValid,
  }) {
    if (_isRevertingCutoff) return;
    final text = controller.text.trim();
    if (text.isEmpty) {
      setLastValid('');
      _updateSaveButtonState();
      return;
    }
    DateTime? parsed;
    try {
      parsed = DateFormat('yyyy-MM-dd').parseStrict(text);
    } on FormatException {
      return;
    }
    final error = _roundsLinking.validateLeagueCutoffEdit(
      league: league,
      oldCutoffUTC: league == League.nrl
          ? widget.daucomp?.nrlRegularCompEndDateUTC?.toUtc()
          : widget.daucomp?.aflRegularCompEndDateUTC?.toUtc(),
      newCutoffUTC: parsed.toUtc(),
      allGames: _allGamesForValidation(_pageDauCompsViewModel),
    );
    if (error != null) {
      _isRevertingCutoff = true;
      controller.text = lastValid;
      _isRevertingCutoff = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
      return;
    }
    setLastValid(controller.text);
    _updateSaveButtonState();
  }

  List<Game> _allGamesForValidation(DAUCompsViewModel viewModel) {
    final rounds = viewModel.selectedDAUComp?.daurounds ?? const <DAURound>[];
    final seen = <String>{};
    final games = <Game>[];
    for (final r in rounds) {
      for (final g in r.games) {
        if (seen.add(g.dbkey)) games.add(g);
      }
    }
    for (final g in viewModel.unassignedGames) {
      if (seen.add(g.dbkey)) games.add(g);
    }
    return games;
  }

  void _updateSaveButtonState() {
    bool shouldEnableSave;
    bool originalActiveStatus = false;
    if (widget.daucomp != null) {
      final globalDauCompsVM = di<DAUCompsViewModel>();
      originalActiveStatus =
          globalDauCompsVM.initDAUCompDbKey != null &&
          widget.daucomp!.dbkey == globalDauCompsVM.initDAUCompDbKey;
    }

    if (widget.daucomp == null) {
      shouldEnableSave =
          _daucompNameController.text.isNotEmpty &&
          _daucompAflJsonURLController.text.isNotEmpty &&
          _daucompNrlJsonURLController.text.isNotEmpty;
    } else {
      final rounds =
          _pageDauCompsViewModel.selectedDAUComp?.daurounds ??
          widget.daucomp!.daurounds;
      final roundStartsChanged = rounds.any(
        (r) => !r.getRoundStartDate().isAtSameMomentAs(
          r.roundStartDateWithOverride(
            _initialRoundStartOverrides[r.dAUroundNumber],
          ),
        ),
      );
      shouldEnableSave =
          (_daucompNameController.text != widget.daucomp!.name ||
              _daucompAflJsonURLController.text !=
                  widget.daucomp!.aflFixtureJsonURL.toString() ||
              _daucompNrlJsonURLController.text !=
                  widget.daucomp!.nrlFixtureJsonURL.toString() ||
              _nrlRegularCompEndDateController.text !=
                  (widget.daucomp!.nrlRegularCompEndDateUTC != null
                      ? DateFormat('yyyy-MM-dd')
                            .format(widget.daucomp!.nrlRegularCompEndDateUTC!)
                      : '') ||
              _aflRegularCompEndDateController.text !=
                  (widget.daucomp!.aflRegularCompEndDateUTC != null
                      ? DateFormat('yyyy-MM-dd')
                            .format(widget.daucomp!.aflRegularCompEndDateUTC!)
                      : '') ||
              roundStartsChanged) ||
          (_localActiveCompState != originalActiveStatus);
    }

    log(
      'shouldEnableSave = $shouldEnableSave, _localActiveCompState = $_localActiveCompState, originalActiveStatus = $originalActiveStatus',
    );

    if (disableSaves != !shouldEnableSave) {
      setState(() {
        disableSaves = !shouldEnableSave;
      });
      log('state change disableSaves = $disableSaves');
    }
  }

  Future<void> _saveDAUComp(
    DAUCompsViewModel dauCompsViewModel,
    BuildContext context,
  ) async {
    try {
      // Prepare data for the ViewModel call
      String name = _daucompNameController.text;
      String aflUrl = _daucompAflJsonURLController.text;
      String nrlUrl = _daucompNrlJsonURLController.text;
      String? nrlEndDate = _nrlRegularCompEndDateController.text;
      String? aflEndDate = _aflRegularCompEndDateController.text;

      // Call the ViewModel method
      var result = await dauCompsViewModel.processAndSaveDauComp(
        name: name,
        aflFixtureJsonURL: aflUrl,
        nrlFixtureJsonURL: nrlUrl,
        nrlRegularCompEndDateString: nrlEndDate.isNotEmpty ? nrlEndDate : null,
        aflRegularCompEndDateString: aflEndDate.isNotEmpty ? aflEndDate : null,
        existingComp: widget.daucomp,
        currentRounds:
            dauCompsViewModel.selectedDAUComp?.daurounds ??
            [], // Added this line
        initialRoundStartOverrides: _initialRoundStartOverrides,
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
              'Failed to update the DAU Comp record',
            ), // Generic message
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
    }
  }

  // isUriActive method removed

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DAUCompsViewModel>.value(
      value: _pageDauCompsViewModel,
      // Back is the floating control's maybePop, which stops here while a save
      // or an admin update is running and asks before it lets go.
      child: PopScope(
        canPop: !disableBack,
        onPopInvokedWithResult: (didPop, result) =>
            _confirmDiscardChanges(didPop),
        child: AppAdminPage(
          title: 'Edit DAU Comp',
          actions: [
            ?_runUpdatesAction(),
            AppGlassAction(
              icon: Icons.save,
              label: 'Save',
              onPressed: disableSaves
                  ? null
                  : () async {
                      final isValid = _formKey.currentState!.validate();
                      if (isValid) {
                        setState(() {
                          disableSaves = true;
                          disableBack = true;
                        });

                        await _saveDAUComp(_pageDauCompsViewModel, context);

                        setState(() {
                          disableSaves = true;
                          disableBack = false;
                        });
                      }
                    },
            ),
          ],
          body: Padding(
            padding: const EdgeInsets.all(16),
            // Form tag is removed from here and now lives in AdminDaucompsEditForm
            child: SingleChildScrollView(
              child: Consumer<DAUCompsViewModel>(
                builder: (context, dauCompsViewModelConsumer, child) {
                  // This is the mainColumn
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AdminDaucompsEditForm(
                        formKey: _formKey,
                        daucomp: widget.daucomp,
                        daucompNameController: _daucompNameController,
                        daucompAflJsonURLController:
                            _daucompAflJsonURLController,
                        daucompNrlJsonURLController:
                            _daucompNrlJsonURLController,
                        nrlRegularCompEndDateController:
                            _nrlRegularCompEndDateController,
                        aflRegularCompEndDateController:
                            _aflRegularCompEndDateController,
                        dauCompsViewModel: dauCompsViewModelConsumer,
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
                            bool isCurrentGlobalActive =
                                widget.daucomp != null &&
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
                                    'You cannot turn off the active comp. Instead, edit another comp to be active.',
                                  ),
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
                        if (dauCompsViewModelConsumer
                            .unassignedGames
                            .isNotEmpty)
                          AdminDaucompsEditWarning.unassigned(
                            games: dauCompsViewModelConsumer.unassignedGames,
                          ),
                        if (dauCompsViewModelConsumer
                            .splitRoundGames
                            .isNotEmpty)
                          AdminDaucompsEditWarning.splitRound(
                            splitGames:
                                dauCompsViewModelConsumer.splitRoundGames,
                          ),
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
                                        'This is a list of round start dates (0:00 UTC). Any game kickoff times from a round\'s start date (0:00 UTC) up to the next round\'s start date are included in the round and counted by league.\n\nWhen the comp is first created and added in the app, these dates are automatically calculated based on round information provided in the fixture.\n\nIf needed, an Admin can override these dates as needed. If the date is bold then it has been subsequently changed and overridden by an admin.',
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
                          rounds:
                              dauCompsViewModelConsumer
                                  .selectedDAUComp
                                  ?.daurounds
                                  .toList() ??
                              [],
                          onRoundDateChanged:
                              (DAURound round, DateTime newDate) {
                                final comp =
                                    dauCompsViewModelConsumer.selectedDAUComp ??
                                    widget.daucomp!;
                                final error = _roundsLinking
                                    .validateRoundStartDateEdit(
                                      comp: comp,
                                      rounds: comp.daurounds,
                                      editedRoundNumber: round.dAUroundNumber,
                                      newStartDateUTC: newDate.toUtc(),
                                      allGames: _allGamesForValidation(
                                        dauCompsViewModelConsumer,
                                      ),
                                    );
                                if (error != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(error),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  setState(() {});
                                  return;
                                }
                                setState(() {
                                  round.adminOverrideRoundStartDate = newDate;
                                  _recalculateGameCounts(
                                    dauCompsViewModelConsumer,
                                  );
                                });
                                _updateSaveButtonState();
                              },
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Manual repair steps, kept in the corner with Save and Back. Only an
  /// existing comp has fixtures and scores to repair. The page rebuilds as the
  /// update starts and ends, which is when the busy state changes.
  AppGlassAction? _runUpdatesAction() {
    final daucomp = widget.daucomp;
    final statsViewModel = _pageDauCompsViewModel.statsViewModel;
    if (daucomp == null) {
      return null;
    }
    final state = _runUpdatesState();
    return AppGlassAction(
      icon: Icons.sync,
      label: state.busy ? 'Updating' : 'Run updates',
      onPressed: statsViewModel == null || state.busy
          ? null
          : () => runAdminUpdates(
              context: context,
              dauCompsViewModel: _pageDauCompsViewModel,
              statsViewModel: statsViewModel,
              daucomp: daucomp,
              onDisableBack: (bool disabled) =>
                  setState(() => disableBack = disabled),
            ),
    );
  }

  /// Whether Run updates has anything to run against yet, and whether an
  /// update is already under way.
  ({bool ready, bool busy}) _runUpdatesState() {
    final statsViewModel = _pageDauCompsViewModel.statsViewModel;
    if (statsViewModel == null) {
      return (ready: false, busy: false);
    }
    return (
      ready: true,
      busy: adminUpdatesBusy(_pageDauCompsViewModel, statsViewModel),
    );
  }

  /// The action sits in the app bar, outside the page's Consumer, so nothing
  /// rebuilds it when the view model loads or a download starts. Without this
  /// it stayed disabled until an unrelated edit rebuilt the page.
  void _refreshRunUpdatesAction() {
    if (!mounted) {
      return;
    }
    final state = _runUpdatesState();
    if (state == _shownRunUpdates) {
      return;
    }
    setState(() => _shownRunUpdates = state);
  }

  Future<void> _confirmDiscardChanges(bool didPop) async {
    if (didPop || !mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text(
          'You have unsaved changes. Do you really want to discard them?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close the dialog
              Navigator.of(context).pop(); // Go back
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  void _recalculateGameCounts(DAUCompsViewModel dauCompsViewModel) async {
    if (dauCompsViewModel.selectedDAUComp != null &&
        dauCompsViewModel.selectedDAUComp!.daurounds.isNotEmpty) {
      dauCompsViewModel.linkGamesWithRounds(
        dauCompsViewModel.selectedDAUComp!.daurounds,
      );
    }
  }

  // buttonFixture method is now removed
  // buttonScoring method is now removed
}
