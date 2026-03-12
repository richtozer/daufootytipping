import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  late MockDAUCompsViewModel mockDauCompsViewModel;
  late MockTippersViewModel mockTippersViewModel;
  late Tipper tipper;

  Future<void> pumpEditPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TipperAdminEditPage(mockTippersViewModel, tipper),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    mockDauCompsViewModel = MockDAUCompsViewModel();
    mockTippersViewModel = MockTippersViewModel();

    tipper = Tipper(
      dbkey: 'tipper-1',
      authuid: 'auth-1',
      email: 'comm@example.com',
      logon: 'login@example.com',
      name: 'Test Tipper',
      tipperRole: TipperRole.admin,
      compsPaidFor: const [],
      acctLoggedOnUTC: DateTime.utc(2025, 3, 5, 23, 32, 50),
    );

    when(() => mockDauCompsViewModel.selectedDAUComp).thenReturn(null);
    when(() => mockDauCompsViewModel.getDAUcomps()).thenAnswer(
      (_) async => <DAUComp>[],
    );

    when(
      () => mockTippersViewModel.isEmailOrLogonAlreadyAssigned(
        any(),
        any(),
        tipper,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => mockTippersViewModel.updateTipperAttribute(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => mockTippersViewModel.saveBatchOfTipperChangesToDb(),
    ).thenAnswer((_) async {});

    di.registerSingleton<DAUCompsViewModel>(mockDauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('renders logon as read-only and shows last login time', (
    tester,
  ) async {
    await pumpEditPage(tester);

    final Finder logonFieldFinder = find.byKey(
      TipperAdminEditPage.logonFieldKey,
    );
    final Finder lastLoginFieldFinder = find.byKey(
      TipperAdminEditPage.lastLoginFieldKey,
    );
    final TextField logonField = tester.widget<TextField>(
      find.descendant(of: logonFieldFinder, matching: find.byType(TextField)),
    );
    final TextField lastLoginField = tester.widget<TextField>(
      find.descendant(
        of: lastLoginFieldFinder,
        matching: find.byType(TextField),
      ),
    );

    expect(logonFieldFinder, findsOneWidget);
    expect(lastLoginFieldFinder, findsOneWidget);
    expect(logonField.controller?.text, 'login@example.com');
    expect(
      lastLoginField.controller?.text,
      DateFormat('dd MMM yy HH:mm').format(tipper.acctLoggedOnUTC!.toLocal()),
    );
    expect(logonField.readOnly, isTrue);
    expect(
      logonField.decoration?.border,
      InputBorder.none,
    );
    expect(
      lastLoginField.decoration?.border,
      InputBorder.none,
    );
    expect(find.text('Linked login email is read-only here'), findsNothing);
    expect(find.byKey(TipperAdminEditPage.emailInfoButtonKey), findsNothing);
    expect(find.byKey(TipperAdminEditPage.tipHistoryButtonKey), findsOneWidget);
  });

  testWidgets(
    'collapses logon row and shows info dialog when login and email match',
    (tester) async {
      tipper = Tipper(
        dbkey: 'tipper-1',
        authuid: 'auth-1',
        email: 'same@example.com',
        logon: 'same@example.com',
        name: 'Test Tipper',
        tipperRole: TipperRole.admin,
        compsPaidFor: const [],
        acctLoggedOnUTC: DateTime.utc(2025, 3, 5, 23, 32, 50),
      );

      await pumpEditPage(tester);

      expect(find.text('Logon:'), findsNothing);
      final TextFormField emailField = tester.widget<TextFormField>(
        find.byKey(TipperAdminEditPage.emailFieldKey),
      );
      expect(emailField.controller?.text, 'same@example.com');
      expect(find.byKey(TipperAdminEditPage.emailInfoButtonKey), findsOneWidget);

      await tester.tap(find.byKey(TipperAdminEditPage.emailInfoButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text('Login and communications emails are the same'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'OK'), findsOneWidget);
    },
  );

  testWidgets('save does not persist logon updates', (tester) async {
    await pumpEditPage(tester);

    await tester.enterText(
      find.byKey(TipperAdminEditPage.emailFieldKey),
      'updated@example.com',
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(TipperAdminEditPage.saveButtonKey))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(TipperAdminEditPage.saveButtonKey));
    await tester.pumpAndSettle();

    verify(
      () => mockTippersViewModel.isEmailOrLogonAlreadyAssigned(
        'updated@example.com',
        'login@example.com',
        tipper,
      ),
    ).called(1);
    verify(
      () => mockTippersViewModel.updateTipperAttribute(
        'tipper-1',
        'email',
        'updated@example.com',
      ),
    ).called(1);
    verifyNever(
      () => mockTippersViewModel.updateTipperAttribute(any(), 'logon', any()),
    );
  });
}
