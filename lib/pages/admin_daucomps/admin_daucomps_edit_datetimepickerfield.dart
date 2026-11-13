import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formats a round boundary for the admin rounds table, in local time, as a
/// short day and date followed by the time with an abbreviated meridiem, for
/// example `Thu 5/3 7:50p`.
String formatRoundDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final time = DateFormat('h:mm a')
      .format(local)
      .replaceAll(' AM', 'a')
      .replaceAll(' PM', 'p');
  return '${DateFormat('E d/M').format(local)} $time';
}

class DateTimePickerField extends StatelessWidget {
  final TextEditingController controller;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final void Function(DateTime selectedDateTime) onDateTimeChanged;
  final bool isBold;

  const DateTimePickerField({
    super.key,
    required this.controller,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateTimeChanged,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: TextStyle(
        fontSize: 14,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      ),
      decoration: const InputDecoration(isDense: true),
      onTap: () async {
        FocusScope.of(context).requestFocus(FocusNode());
        // The field shows local time, so seed both pickers with it too.
        final localInitialDate = initialDate.toLocal();
        DateTime? date = await showDatePicker(
          context: context,
          initialDate: localInitialDate,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (date != null) {
          if (!context.mounted) return;
          TimeOfDay? time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(localInitialDate),
          );
          if (time != null) {
            DateTime selectedDateTime = DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            );
            controller.text = formatRoundDateTime(selectedDateTime);
            onDateTimeChanged(selectedDateTime);
          }
        }
      },
    );
  }
}
