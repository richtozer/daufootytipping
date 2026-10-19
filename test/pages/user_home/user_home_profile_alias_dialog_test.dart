import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_alias_dialog.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class _MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  late _MockTippersViewModel tippers;
  late Tipper tipper;

  Future<void> openDialog(
    WidgetTester tester, {
    required Size size,
    double keyboard = 0,
    String name = 'toaster',
  }) async {
    await di.reset();
    tipper = Tipper(
      dbkey: 'tipper-1',
      authuid: 'auth-1',
      email: 'comm@example.com',
      name: name,
      tipperRole: TipperRole.tipper,
      compsPaidFor: const [],
    );
    tippers = _MockTippersViewModel();
    when(() => tippers.setTipperName(any(), any())).thenAnswer((_) async {});
    di.registerSingleton<TippersViewModel>(tippers);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showEditAliasDialog(context, tipper),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'landscape with the keyboard up, the field and Save stay in view',
    (tester) async {
      const screen = Size(852, 393);
      const keyboard = 200.0;
      await openDialog(tester, size: screen, keyboard: keyboard);

      final visibleBottom = screen.height - keyboard;
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(visibleBottom),
      );
      expect(
        tester.getRect(find.text('Save')).bottom,
        lessThanOrEqualTo(visibleBottom),
      );
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets('a portrait phone shows the whole dialog', (tester) async {
    await openDialog(tester, size: const Size(390, 844), keyboard: 300);

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('the buttons are the app\'s outlined and filled styles', (
    tester,
  ) async {
    await openDialog(tester, size: const Size(390, 844));

    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('an empty or one-letter alias is refused, a good one saved', (
    tester,
  ) async {
    await openDialog(tester, size: const Size(390, 844));

    await tester.enterText(find.byType(TextField), ' ');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Alias cannot be empty.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'a');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('at least 2 characters'), findsOneWidget);
    verifyNever(() => tippers.setTipperName(any(), any()));

    await tester.enterText(find.byType(TextField), 'The Oracle');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => tippers.setTipperName('tipper-1', 'The Oracle')).called(1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a tipper with no alias cannot back out', (tester) async {
    await openDialog(tester, size: const Size(390, 844), name: '');

    expect(find.text('Create Tipper Alias'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}
