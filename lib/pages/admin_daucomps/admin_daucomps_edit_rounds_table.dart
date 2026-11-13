import 'package:flutter/material.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart';

class AdminDaucompsEditRoundsTable extends StatefulWidget {
  final List<DAURound> rounds;
  final Function(DAURound round, DateTime newDate, bool isStartDate)
  onRoundDateChanged;

  const AdminDaucompsEditRoundsTable({
    super.key,
    required this.rounds,
    required this.onRoundDateChanged,
  });

  @override
  AdminDaucompsEditRoundsTableState createState() =>
      AdminDaucompsEditRoundsTableState();
}

class AdminDaucompsEditRoundsTableState
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
        if (widget.rounds[i].dAUroundNumber !=
                oldWidget.rounds[i].dAUroundNumber ||
            !widget.rounds[i].getRoundStartDate().isAtSameMomentAs(
              oldWidget.rounds[i].getRoundStartDate(),
            ) ||
            !widget.rounds[i].getRoundEndDate().isAtSameMomentAs(
              oldWidget.rounds[i].getRoundEndDate(),
            )) {
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
        text: formatRoundDateTime(round.getRoundStartDate()),
      );
      _endDateControllers[round.dAUroundNumber] = TextEditingController(
        text: formatRoundDateTime(round.getRoundEndDate()),
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
              child: Text(
                'First kickoff',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.bottom,
              child: Text(
                'Last kickoff',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.bottom,
              child: Text('NRL', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.bottom,
              child: Text('AFL', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    onDateTimeChanged: (selectedDateTime) => widget
                        .onRoundDateChanged(round, selectedDateTime, true),
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
                    onDateTimeChanged: (selectedDateTime) => widget
                        .onRoundDateChanged(round, selectedDateTime, false),
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
