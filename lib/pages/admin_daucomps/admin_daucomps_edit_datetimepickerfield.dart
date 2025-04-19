import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
      decoration: const InputDecoration(
        isDense: true,
      ),
      onTap: () async {
        FocusScope.of(context).requestFocus(FocusNode());
        DateTime? date = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (date != null) {
          TimeOfDay? time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(initialDate),
          );
          if (time != null) {
            DateTime selectedDateTime = DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            );
            controller.text =
                '${DateFormat('E d/M').format(selectedDateTime.toLocal())} ${DateFormat('h:mm a').format(selectedDateTime.toLocal()).replaceAll(" AM", "a").replaceAll(" PM", "p")}';
            onDateTimeChanged(selectedDateTime);
          }
        }
      },
    );
  }
}
