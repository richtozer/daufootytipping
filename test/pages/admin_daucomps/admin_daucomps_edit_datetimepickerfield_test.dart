import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'selecting a date updates with 0:00 UTC without opening a time picker',
    (tester) async {
      // Rounds hold UTC instants. Late evening UTC must still seed the date
      // picker with its UTC calendar date and return 0:00 UTC on the picked date.
      final roundStartUtc = DateTime.utc(2026, 3, 5, 22, 30);
      final controller = TextEditingController(
        text: formatRoundDateTime(roundStartUtc),
      );
      addTearDown(controller.dispose);
      DateTime? selectedDateTime;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateTimePickerField(
              controller: controller,
              initialDate: roundStartUtc,
              firstDate: DateTime.utc(2000),
              lastDate: DateTime.utc(2100),
              onDateTimeChanged: (dateTime) => selectedDateTime = dateTime,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();

      await tester.tap(find.text('6'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(selectedDateTime, DateTime.utc(2026, 3, 6));
      expect(selectedDateTime?.isUtc, isTrue);
      expect(controller.text, 'Fri 6/3');
    },
  );

  testWidgets('cancelling the date picker leaves the field unchanged', (
    tester,
  ) async {
    final roundStartUtc = DateTime.utc(2026, 11, 12, 14, 30);
    final controller = TextEditingController(
      text: formatRoundDateTime(roundStartUtc),
    );
    addTearDown(controller.dispose);
    DateTime? selectedDateTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DateTimePickerField(
            controller: controller,
            initialDate: roundStartUtc,
            firstDate: DateTime.utc(2000),
            lastDate: DateTime.utc(2100),
            onDateTimeChanged: (dateTime) => selectedDateTime = dateTime,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(selectedDateTime, isNull);
    expect(controller.text, 'Thu 12/11');
  });
}
