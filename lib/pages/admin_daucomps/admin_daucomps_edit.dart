import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
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

  // Controllers for round start and end dates
  final Map<int, TextEditingController> _startDateControllers = {};
  final Map<int, TextEditingController> _endDateControllers = {};

  @override
  void initState() {
    super.initState();
    _initTextControllersListeners();
    _initializeRoundControllers();
    _updateSaveButtonState();
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (var controller in _startDateControllers.values) {
      controller.dispose();
    }
    for (var controller in _endDateControllers.values) {
      controller.dispose();
    }
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

  void _initializeRoundControllers() {
    if (widget.daucomp != null) {
      for (var round in widget.daucomp!.daurounds) {
        _startDateControllers[round.dAUroundNumber] = TextEditingController(
          text:
              '${DateFormat('E d/M').format(round.getRoundStartDate().toLocal())} ${DateFormat('h:mm a').format(round.firstGameKickOffUTC.toLocal()).replaceAll(" AM", "a").replaceAll(" PM", "p")}',
        );

        _endDateControllers[round.dAUroundNumber] = TextEditingController(
          text:
              '${DateFormat('E d/M').format(round.getRoundEndDate().toLocal())} ${DateFormat('h:mm a').format(round.lastGameKickOffUTC.toLocal()).replaceAll(" AM", "a").replaceAll(" PM", "p")}',
        );
      }
    }
  }

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
            nrlRegularCompEndDateUTC: widget
                    ._nrlRegularCompEndDateController.text.isNotEmpty
                ? DateTime.parse(widget._nrlRegularCompEndDateController.text)
                : null,
            aflRegularCompEndDateUTC: widget
                    ._aflRegularCompEndDateController.text.isNotEmpty
                ? DateTime.parse(widget._aflRegularCompEndDateController.text)
                : null,
            daurounds: [],
          );

          await dauCompsViewModel.newDAUComp(newDAUComp);
          await dauCompsViewModel.saveBatchOfCompAttributes();
          // init gamesViewModel for the new comp
          dauCompsViewModel.gamesViewModel =
              GamesViewModel(newDAUComp, dauCompsViewModel);
          await dauCompsViewModel.gamesViewModel?.initialLoadComplete;

          String res =
              await dauCompsViewModel.getNetworkFixtureData(newDAUComp);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.green,
                content: Text(res),
                duration: const Duration(seconds: 4),
              ),
            );
          }

          Navigator.of(context).pop(); // Navigate back to the previous page
        } else {
          dauCompsViewModel.updateCompAttribute(widget.daucomp!.dbkey!, "name",
              widget._daucompNameController.text);
          dauCompsViewModel.updateCompAttribute(widget.daucomp!.dbkey!,
              "aflFixtureJsonURL", widget._daucompAflJsonURLController.text);
          dauCompsViewModel.updateCompAttribute(widget.daucomp!.dbkey!,
              "nrlFixtureJsonURL", widget._daucompNrlJsonURLController.text);
          dauCompsViewModel.updateCompAttribute(
              widget.daucomp!.dbkey!,
              "nrlRegularCompEndDateUTC",
              widget._nrlRegularCompEndDateController.text.isNotEmpty
                  ? DateTime.parse(widget._nrlRegularCompEndDateController.text)
                      .toIso8601String()
                  : null);
          dauCompsViewModel.updateCompAttribute(
              widget.daucomp!.dbkey!,
              "aflRegularCompEndDateUTC",
              widget._aflRegularCompEndDateController.text.isNotEmpty
                  ? DateTime.parse(widget._aflRegularCompEndDateController.text)
                      .toIso8601String()
                  : null);
          // if any of the rounds have an admin override then save these too
          for (DAURound round in dauCompsViewModel.activeDAUComp!.daurounds) {
            if (round.adminOverrideRoundStartDate != null) {
              dauCompsViewModel.updateRoundAttribute(
                  widget.daucomp!.dbkey!,
                  round.dAUroundNumber,
                  "adminOverrideRoundStartDate",
                  round.adminOverrideRoundStartDate!.toUtc().toIso8601String());
            }

            if (round.adminOverrideRoundEndDate != null) {
              dauCompsViewModel.updateRoundAttribute(
                  widget.daucomp!.dbkey!,
                  round.dAUroundNumber,
                  "adminOverrideRoundEndDate",
                  round.adminOverrideRoundEndDate!.toUtc().toIso8601String());
            }
          }

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

          Navigator.of(context).pop(); // Navigate back to the previous page
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
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Consumer<DAUCompsViewModel>(
                    builder: (context, dauCompsViewModeconsumer, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (widget.daucomp != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            buttonFixture(context, dauCompsViewModeconsumer),
                            buttonScoring(context, dauCompsViewModeconsumer),
                          ],
                        ),
                      Row(
                        children: [
                          if (widget.daucomp != null)
                            const Text('Active\nComp:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          if (widget.daucomp != null)
                            Switch(
                              value: widget.daucomp != null &&
                                  di<DAUCompsViewModel>().initDAUCompDbKey !=
                                      null &&
                                  widget.daucomp!.dbkey ==
                                      di<DAUCompsViewModel>().initDAUCompDbKey,
                              onChanged: (bool value) async {
                                if (widget.daucomp == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                          'You cannot set the active comp for a new record. Save the record first.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }
                                if (value) {
                                  ConfigViewModel remoteConfigService =
                                      ConfigViewModel();
                                  remoteConfigService.setConfigCurrentDAUComp(
                                      widget.daucomp!.dbkey!);
                                  // await consumer.changeDisplayedDAUComp(
                                  //     widget.daucomp!, true);
                                  log('Active comp changed to: ${widget.daucomp!.name}');
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                          'You cannot turn off the active comp. Instead edit another comp to be active.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              },
                            ),
                          if (widget.daucomp != null) const SizedBox(width: 10),
                          Text('Name: ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: TextFormField(
                              controller: widget._daucompNameController,
                              decoration: const InputDecoration(
                                hintText: 'DAU Comp name',
                                isDense: true,
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
                      const Text('NRL json URL:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'enter URL here',
                                isDense: true,
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
                      const Text('AFL json URL:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'enter URL here',
                                isDense: true,
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
                      Row(
                        children: [
                          Text('NRL Regular Comp Cutoff: ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: TextFormField(
                              controller:
                                  widget._nrlRegularCompEndDateController,
                              decoration: const InputDecoration(
                                hintText: 'not set',
                                isDense: true,
                              ),
                              onTap: () async {
                                FocusScope.of(context)
                                    .requestFocus(FocusNode());
                                DateTime? date = await showDatePicker(
                                  context: context,
                                  initialDate: widget
                                          .daucomp?.nrlRegularCompEndDateUTC ??
                                      DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null) {
                                  widget._nrlRegularCompEndDateController.text =
                                      DateFormat('yyyy-MM-dd').format(date);
                                  setState(() {
                                    disableSaves = false;
                                  });
                                }
                              },
                              validator: (String? value) {
                                if (value != null && value.isNotEmpty) {
                                  try {
                                    DateFormat('yyyy-MM-dd').parse(value);
                                  } catch (e) {
                                    return 'Invalid date format';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              widget._nrlRegularCompEndDateController.clear();
                              setState(() {
                                disableSaves = false;
                              });
                            },
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text('AFL Regular Comp Cutoff: ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: TextFormField(
                              controller:
                                  widget._aflRegularCompEndDateController,
                              decoration: const InputDecoration(
                                hintText: 'not set',
                                isDense: true,
                              ),
                              onTap: () async {
                                FocusScope.of(context)
                                    .requestFocus(FocusNode());
                                DateTime? date = await showDatePicker(
                                  context: context,
                                  initialDate: widget
                                          .daucomp?.aflRegularCompEndDateUTC ??
                                      DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null) {
                                  widget._aflRegularCompEndDateController.text =
                                      DateFormat('yyyy-MM-dd').format(date);
                                  setState(() {
                                    disableSaves = false;
                                  });
                                }
                              },
                              validator: (String? value) {
                                if (value != null && value.isNotEmpty) {
                                  try {
                                    DateFormat('yyyy-MM-dd').parse(value);
                                  } catch (e) {
                                    return 'Invalid date format';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              widget._aflRegularCompEndDateController.clear();
                              setState(() {
                                disableSaves = false;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20.0),
                      if (widget.daucomp == null) ...[
                        const Text(
                            'After adding a new comp name and URLs, click the save button and then reopen this record to see the round details.',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                      if (widget.daucomp != null) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (dauCompsViewModeconsumer
                                .unassignedGames.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(8.0),
                                margin: const EdgeInsets.only(bottom: 16.0),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  border: Border.all(color: Colors.red),
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Warning: Unassigned Games Detected!',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                    const SizedBox(height: 8.0),
                                    const Text(
                                      'The following games have kickoff dates before the regular comp cutoff (if supplied), but are not assigned to any round.\n\nPlease modify the round dates to include these game(s).\n\nEach item is in the following format: \n- League-LeagueRoundNumber-MatchNumber HomeTeam v AwayTeam (Kickoff time):',
                                      style: TextStyle(color: Colors.black),
                                    ),
                                    const SizedBox(height: 8.0),
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: dauCompsViewModeconsumer
                                          .unassignedGames.length,
                                      itemBuilder: (context, index) {
                                        final game = dauCompsViewModeconsumer
                                            .unassignedGames[index];
                                        return Text(
                                          '- ${game.league.name}-${game.fixtureRoundNumber}-${game.fixtureMatchNumber} ${game.homeTeam.name} v ${game.awayTeam.name} (${DateFormat('yyyy-MM-dd HH:mm').format(game.startTimeUTC.toLocal())})',
                                          style: const TextStyle(
                                              color: Colors.black),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Counts of games grouped by DAU round:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                      child: Text('First kickoff',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.bottom,
                                      child: Text('Last kickoff',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.bottom,
                                      child: Text('NRL',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    TableCell(
                                      verticalAlignment:
                                          TableCellVerticalAlignment.bottom,
                                      child: Text('AFL',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                for (DAURound round in dauCompsViewModeconsumer
                                        .activeDAUComp?.daurounds ??
                                    [])
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
                                          child: DateTimePickerField(
                                            controller: _startDateControllers[
                                                round.dAUroundNumber]!,
                                            initialDate:
                                                round.getRoundStartDate(),
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2100),
                                            isBold: round
                                                    .adminOverrideRoundStartDate !=
                                                null,
                                            onDateTimeChanged:
                                                (selectedDateTime) {
                                              round.adminOverrideRoundStartDate =
                                                  selectedDateTime;
                                              _recalculateGameCounts(); // Recalculate counts
                                              setState(() {
                                                disableSaves = false;
                                              });
                                            },
                                          ),
                                        ),
                                        TableCell(
                                          child: DateTimePickerField(
                                            controller: _endDateControllers[
                                                round.dAUroundNumber]!,
                                            initialDate:
                                                round.getRoundEndDate(),
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2100),
                                            isBold: round
                                                    .adminOverrideRoundEndDate !=
                                                null,
                                            onDateTimeChanged:
                                                (selectedDateTime) {
                                              round.adminOverrideRoundEndDate =
                                                  selectedDateTime;
                                              _recalculateGameCounts(); // Recalculate counts
                                              setState(() {
                                                disableSaves = false;
                                              });
                                            },
                                          ),
                                        ),
                                        TableCell(
                                          verticalAlignment:
                                              TableCellVerticalAlignment.middle,
                                          child: Text(
                                              round.nrlGameCount.toString()),
                                        ),
                                        TableCell(
                                          verticalAlignment:
                                              TableCellVerticalAlignment.middle,
                                          child: Text(
                                              round.aflGameCount.toString()),
                                        ),
                                      ],
                                    ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                }),
              ),
            ),
          )),
    );
  }

  void _recalculateGameCounts() async {
    di<DAUCompsViewModel>().linkGamesWithRounds(widget.daucomp!.daurounds);
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
                  backgroundColor: Colors.green,
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

  Widget buttonScoring(
      BuildContext context, DAUCompsViewModel dauCompsViewModel) {
    if (widget.daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          if (dauCompsViewModel.statsViewModel?.isUpdateScoringRunning ??
              false) {
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
            String syncResult = await dauCompsViewModel.statsViewModel
                    ?.updateStats(widget.daucomp!, null, null) ??
                'Stats update failed: statsViewModel is null';
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
        child: Text(
            !(dauCompsViewModel.statsViewModel?.isUpdateScoringRunning ?? false)
                ? 'Rescore'
                : 'Scoring...'),
      );
    }
  }
}
