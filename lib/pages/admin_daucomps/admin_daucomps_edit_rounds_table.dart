import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart';

class AdminDaucompsEditRoundsTable extends StatefulWidget {
  final List<DAURound> rounds;
  final Function(DAURound round, DateTime newDate, bool isStartDate)
      onRoundDateChanged;

  const AdminDaucompsEditRoundsTable({
    Key? key,
    required this.rounds,
    required this.onRoundDateChanged,
  }) : super(key: key);

  @override
  _AdminDaucompsEditRoundsTableState createState() =>
      _AdminDaucompsEditRoundsTableState();
}

class _AdminDaucompsEditRoundsTableState
    extends State<AdminDaucompsEditRoundsTable> {
  final Map<int, TextEditingController> _startDateControllers = {};
  final Map<int, TextEditingController> _endDateControllers = {};

  @override
  void initState() {
    super.initState();
    _initializeRoundControllers();
  }

  @override
  void didUpdateWidget(covariant AdminDaucompsEditRoundsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool needsReinitialization = false;
    if (widget.rounds.length != oldWidget.rounds.length) {
      needsReinitialization = true;
    } else {
      for (int i = 0; i < widget.rounds.length; i++) {
        if (widget.rounds[i].dAUroundNumber != oldWidget.rounds[i].dAUroundNumber ||
            widget.rounds[i].getRoundStartDate().toLocal() != oldWidget.rounds[i].getRoundStartDate().toLocal() ||
            widget.rounds[i].getRoundEndDate().toLocal() != oldWidget.rounds[i].getRoundEndDate().toLocal() ||
            widget.rounds[i].firstGameKickOffUTC.toLocal() != oldWidget.rounds[i].firstGameKickOffUTC.toLocal() ||
            widget.rounds[i].lastGameKickOffUTC.toLocal() != oldWidget.rounds[i].lastGameKickOffUTC.toLocal() ||
            (widget.rounds[i].adminOverrideRoundStartDate != oldWidget.rounds[i].adminOverrideRoundStartDate) ||
            (widget.rounds[i].adminOverrideRoundEndDate != oldWidget.rounds[i].adminOverrideRoundEndDate)
            ) {
          needsReinitialization = true;
          break;
        }
      }
    }

    if (needsReinitialization) {
      _disposeControllers();
      _initializeRoundControllers();
    }
  }

  void _initializeRoundControllers() {
    for (var round in widget.rounds) {
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

  void _disposeControllers() {
    for (var controller in _startDateControllers.values) {
      controller.dispose();
    }
    _startDateControllers.clear();
    for (var controller in _endDateControllers.values) {
      controller.dispose();
    }
    _endDateControllers.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Table(
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
              verticalAlignment: TableCellVerticalAlignment.bottom,
              child: Text('#'),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.bottom,
              child: Text('First kickoff',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.bottom,
              child: Text('Last kickoff',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.bottom,
              child:
                  Text('NRL', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.bottom,
              child:
                  Text('AFL', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        for (DAURound round in widget.rounds)
          if (round.games.isNotEmpty)
            TableRow(
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Text(round.dAUroundNumber.toString()),
                ),
                TableCell(
                  child: DateTimePickerField(
                    key: ValueKey('start-${round.dAUroundNumber}'),
                    controller: _startDateControllers[round.dAUroundNumber]!,
                    initialDate: round.getRoundStartDate(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    isBold: round.adminOverrideRoundStartDate != null,
                    onDateTimeChanged: (selectedDateTime) {
                      widget.onRoundDateChanged(round, selectedDateTime, true);
                       // Update controller text after parent handles state change
                      _startDateControllers[round.dAUroundNumber]!.text = 
                          '${DateFormat('E d/M').format(selectedDateTime.toLocal())} ${DateFormat('h:mm a').format(selectedDateTime.toLocal()).replaceAll(" AM", "a").replaceAll(" PM", "p")}';

                    },
                  ),
                ),
                TableCell(
                  child: DateTimePickerField(
                    key: ValueKey('end-${round.dAUroundNumber}'),
                    controller: _endDateControllers[round.dAUroundNumber]!,
                    initialDate: round.getRoundEndDate(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    isBold: round.adminOverrideRoundEndDate != null,
                    onDateTimeChanged: (selectedDateTime) {
                      widget.onRoundDateChanged(round, selectedDateTime, false);
                       _endDateControllers[round.dAUroundNumber]!.text = 
                          '${DateFormat('E d/M').format(selectedDateTime.toLocal())} ${DateFormat('h:mm a').format(selectedDateTime.toLocal()).replaceAll(" AM", "a").replaceAll(" PM", "p")}';
                    },
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Text(round.nrlGameCount.toString()),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Text(round.aflGameCount.toString()),
                ),
              ],
            ),
      ],
    );
  }
}
