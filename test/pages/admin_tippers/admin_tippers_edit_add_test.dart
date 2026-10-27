import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_edit_add.dart';
import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/app_controls_test_app.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  late MockDAUCompsViewModel mockDauCompsViewModel;
  late MockTippersViewModel mockTippersViewModel;
  late Tipper tipper;
  late AppControlsViewModel appControls;

  Future<void> pumpEditPage(WidgetTester tester) async {
    // Pushed, as it is in the app, so the floating controls offer Back and Save.
    await tester.pumpWidget(
      // A Scaffold underneath, as the tippers list is in the app, so a snackbar
      // shown as the edit page closes has somewhere to appear.
      appWithControls(
        appControls,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => TipperAdminEditPage(mockTippersViewModel, tipper),
          ),
        );
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump();
  }

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;
    appControls = registerAppControlsViewModel();

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
    when(() => mockDauCompsViewModel.getDAUcomps())
        .thenAnswer((_) async => <DAUComp>[]);

    when(
      () => mockTippersViewModel.isEmailOrLogonAlreadyAssigned(
        any(),
        any(),
        tipper,
      ),
    ).thenAnswer((_) async => null);
    when(() => mockTippersViewModel.updateTipperAttribute(any(), any(), any()))
        .thenAnswer((_) async {});
    when(
      () => mockTippersViewModel.saveBatchOfTipperChangesToDb(
        acknowledgementLimit: any(named: 'acknowledgementLimit'),
      ),
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
    expect(logonField.decoration?.border, InputBorder.none);
    expect(lastLoginField.decoration?.border, InputBorder.none);
    expect(find.text('Linked login email is read-only here'), findsNothing);
    expect(find.byKey(TipperAdminEditPage.emailInfoButtonKey), findsNothing);
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
      expect(
        find.byKey(TipperAdminEditPage.emailInfoButtonKey),
        findsOneWidget,
      );

      await tester.tap(find.byKey(TipperAdminEditPage.emailInfoButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text('Login and communications emails are the same'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'OK'), findsOneWidget);
    },
  );

  testWidgets(
    'a save the server has not answered tells the user it is queued and lets them leave',
    (tester) async {
      when(
        () => mockTippersViewModel.saveBatchOfTipperChangesToDb(
          acknowledgementLimit: any(named: 'acknowledgementLimit'),
        ),
      ).thenThrow(const WriteNotConfirmedException('tipper update'));
      await pumpEditPage(tester);

      await tester.enterText(
        find.byKey(TipperAdminEditPage.emailFieldKey),
        'updated@example.com',
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(find.textContaining('is queued on this device'), findsOneWidget);
      expect(
        find.byKey(TipperAdminEditPage.emailFieldKey),
        findsNothing,
        reason: 'the screen closes instead of staying on a busy indicator',
      );
      verify(
        () => mockTippersViewModel.saveBatchOfTipperChangesToDb(
          acknowledgementLimit: defaultWriteAcknowledgementLimit,
        ),
      ).called(1);
    },
  );

  testWidgets('a save the server rejects keeps the user on the screen', (
    tester,
  ) async {
    when(
      () => mockTippersViewModel.saveBatchOfTipperChangesToDb(
        acknowledgementLimit: any(named: 'acknowledgementLimit'),
      ),
    ).thenAnswer((_) async => throw Exception('permission denied'));
    await pumpEditPage(tester);

    await tester.enterText(
      find.byKey(TipperAdminEditPage.emailFieldKey),
      'updated@example.com',
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(find.text('Failed to update Tipper record'), findsOneWidget);
    expect(find.byKey(TipperAdminEditPage.emailFieldKey), findsOneWidget);
  });

  testWidgets('save does not persist logon updates', (tester) async {
    await pumpEditPage(tester);

    await tester.enterText(
      find.byKey(TipperAdminEditPage.emailFieldKey),
      'updated@example.com',
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<InkResponse>(
            find.ancestor(
              of: find.byIcon(Icons.save),
              matching: find.byType(InkResponse),
            ),
          )
          .onTap,
      isNotNull,
    );
    await tester.tap(find.byIcon(Icons.save));
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

  group('paid ticks', () {
    final DAUComp comp = DAUComp(
      dbkey: 'comp-2026',
      name: 'DAU 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );

    GestureTapCallback? saveTap(WidgetTester tester) => tester
        .widget<InkResponse>(
          find.ancestor(
            of: find.byIcon(Icons.save),
            matching: find.byType(InkResponse),
          ),
        )
        .onTap;

    Future<void> tickComp(WidgetTester tester) async {
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      // The floating controls take the page's new Save a frame later.
      await tester.pump();
      await tester.pump();
    }

    setUp(() {
      when(() => mockDauCompsViewModel.getDAUcomps())
          .thenAnswer((_) async => <DAUComp>[comp]);
    });

    testWidgets('a tick is a draft that only Save writes', (tester) async {
      await pumpEditPage(tester);
      expect(saveTap(tester), isNull);

      await tickComp(tester);

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(saveTap(tester), isNotNull);
      verifyNever(
        () => mockTippersViewModel.updateTipperAttribute(
          any(),
          'compsParticipatedIn',
          any(),
        ),
      );

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      verify(
        () => mockTippersViewModel.updateTipperAttribute(
          'tipper-1',
          'compsParticipatedIn',
          <String>['comp-2026'],
        ),
      ).called(1);
    });

    testWidgets('unticking again leaves nothing to save', (tester) async {
      await pumpEditPage(tester);

      await tickComp(tester);
      await tickComp(tester);

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(saveTap(tester), isNull);
    });

    testWidgets('discarding a tick leaves the tipper unpaid', (tester) async {
      await pumpEditPage(tester);
      await tickComp(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(TipperAdminEditPage), findsNothing);
      expect(tipper.compsPaidFor, isEmpty);
      verifyNever(
        () => mockTippersViewModel.saveBatchOfTipperChangesToDb(
          acknowledgementLimit: any(named: 'acknowledgementLimit'),
        ),
      );
    });
  });

  testWidgets('Merge sits in the floating controls ahead of Save', (
    tester,
  ) async {
    await pumpEditPage(tester);

    expect(find.text('Merge'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(
      tester.getCenter(find.text('Merge')).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.save)).dx),
    );
  });

  group('god mode action', () {
    late TippersViewModel realTippersViewModel;
    late Tipper authenticatedAdmin;

    setUp(() {
      realTippersViewModel = TippersViewModel(true, skipInit: true);
      authenticatedAdmin = Tipper(
        dbkey: 'admin-auth',
        authuid: 'auth-admin',
        email: 'admin@example.com',
        name: 'Admin',
        tipperRole: TipperRole.admin,
        compsPaidFor: const [],
      );
      realTippersViewModel.setLinkedTippersForTest(authenticatedAdmin);
      di.registerSingleton<TippersViewModel>(realTippersViewModel);
      when(() => mockDauCompsViewModel.selectedDAUComp).thenReturn(
        DAUComp(
          dbkey: 'comp-1',
          name: 'Comp',
          aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
          nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
          daurounds: const [],
        ),
      );
    });

    testWidgets(
      'waits for the tip view model refresh, then goes back to the tipper list',
      (tester) async {
        final refreshCompleter = Completer<void>();
        var notificationCount = 0;
        realTippersViewModel.addListener(() {
          notificationCount++;
        });
        when(() => mockDauCompsViewModel.selectedTipperChanged())
            .thenAnswer((_) => refreshCompleter.future);

        await pumpEditPage(tester);
        await tester.tap(find.text('God\nMode'));
        await tester.pump();

        expect(realTippersViewModel.selectedTipper, same(tipper));
        expect(notificationCount, 0);
        expect(find.byType(TipperAdminEditPage), findsOneWidget);

        refreshCompleter.complete();
        await tester.pumpAndSettle();

        expect(notificationCount, 1);
        expect(realTippersViewModel.inGodMode, isTrue);
        expect(find.byType(TipperAdminEditPage), findsNothing);
        verify(() => mockDauCompsViewModel.selectedTipperChanged()).called(1);
      },
    );

    testWidgets('exits god mode for the tipper it is on for', (tester) async {
      when(() => mockDauCompsViewModel.selectedTipperChanged())
          .thenAnswer((_) async {});
      await realTippersViewModel.changeSelectedTipperAfterRefresh(
        tipper,
        refreshSelectedTipperViewModels: () async {},
      );

      await pumpEditPage(tester);
      await tester.tap(find.text('Exit\nGod\nMode'));
      await tester.pumpAndSettle();

      expect(realTippersViewModel.selectedTipper, same(authenticatedAdmin));
      expect(realTippersViewModel.inGodMode, isFalse);
      expect(find.byType(TipperAdminEditPage), findsNothing);
    });

    testWidgets('stays on the page if the refresh fails', (tester) async {
      when(() => mockDauCompsViewModel.selectedTipperChanged())
          .thenAnswer((_) async => throw StateError('refresh failed'));

      await pumpEditPage(tester);
      await tester.tap(find.text('God\nMode'));
      await tester.pumpAndSettle();

      expect(realTippersViewModel.inGodMode, isFalse);
      expect(find.byType(TipperAdminEditPage), findsOneWidget);
      expect(
        find.text('Could not refresh tips for god mode. Please try again.'),
        findsOneWidget,
      );
    });
  });
}
