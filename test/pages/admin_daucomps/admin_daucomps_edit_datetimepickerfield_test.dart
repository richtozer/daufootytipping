import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'accepting the pickers unchanged keeps the time the field shows',
    (tester) async {
      // Rounds hold UTC instants. Late evening UTC lands on a different local
      // day and hour in most time zones, so a picker seeded with the UTC wall
      // clock would hand back a different instant.
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
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              onDateTimeChanged: (dateTime) => selectedDateTime = dateTime,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final selected = selectedDateTime;
      expect(selected, isNotNull);
      expect(selected?.isAtSameMomentAs(roundStartUtc), isTrue);
      expect(controller.text, formatRoundDateTime(roundStartUtc));
    },
  );
}
