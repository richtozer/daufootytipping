import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formats a round start date in UTC without time of day, for example
/// `Thu 5/3` or `Thu 12/11`.
String formatRoundDateTime(DateTime dateTime) {
  final utcDate = dateTime.toUtc();
  return DateFormat('E d/M').format(utcDate);
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
        final utcInitial = initialDate.toUtc();
        final firstUtc = firstDate.toUtc();
        final lastUtc = lastDate.toUtc();
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: DateTime.utc(
            utcInitial.year,
            utcInitial.month,
            utcInitial.day,
          ),
          firstDate: DateTime.utc(firstUtc.year, firstUtc.month, firstUtc.day),
          lastDate: DateTime.utc(lastUtc.year, lastUtc.month, lastUtc.day),
        );
        if (picked != null) {
          final selectedDate = DateTime.utc(
            picked.year,
            picked.month,
            picked.day,
          );
          controller.text = formatRoundDateTime(selectedDate);
          onDateTimeChanged(selectedDate);
        }
      },
    );
  }
}
