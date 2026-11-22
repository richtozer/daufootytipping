import 'package:flutter/material.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart';

class AdminDaucompsEditRoundsTable extends StatefulWidget {
  final List<DAURound> rounds;
  final void Function(DAURound round, DateTime newDate) onRoundDateChanged;

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
    }
  }

  void _disposeControllers() {
    for (var controller in _startDateControllers.values) {
      controller.dispose();
    }
    _startDateControllers.clear();
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
        2: FlexColumnWidth(0.5),
        3: FlexColumnWidth(0.5),
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
                'Round Start (UTC)',
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
          TableRow(
            children: [
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: Text(round.dAUroundNumber.toString()),
              ),
              TableCell(
                child: Builder(
                  builder: (context) {
                    final controller =
                        _startDateControllers[round.dAUroundNumber]!;
                    final expectedText = formatRoundDateTime(
                      round.getRoundStartDate(),
                    );
                    if (controller.text != expectedText) {
                      controller.text = expectedText;
                    }
                    return DateTimePickerField(
                      key: ValueKey('start-${round.dAUroundNumber}'),
                      controller: controller,
                      initialDate: round.getRoundStartDate(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      isBold: round.adminOverrideRoundStartDate != null,
                      onDateTimeChanged: (selectedDateTime) {
                        // Re-picking the current start date is not an edit.
                        if (selectedDateTime.isAtSameMomentAs(
                          round.getRoundStartDate(),
                        )) {
                          return;
                        }
                        widget.onRoundDateChanged(round, selectedDateTime);
                      },
                    );
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
