import 'dart:async';

import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/dau_shared.dart' show UpdateTipperAliasResult;
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_profile_alias_dialog.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class _MockTippersViewModel extends Mock implements TippersViewModel {}

class _MockIdentityService extends Mock implements IdentityService {}

void main() {
  late _MockTippersViewModel tippers;
  late _MockIdentityService identity;
  late Tipper tipper;

  IdentityFailure refused(String reason) => IdentityFailure(
    kind: IdentityFailureKind.refused,
    code: 'failed-precondition',
    message: 'server words',
    reason: reason,
  );

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
    identity = _MockIdentityService();
    when(() => identity.updateTipperAlias(any())).thenAnswer(
      (invocation) async => UpdateTipperAliasResult(
        tipperId: 'tipper-1',
        alias: invocation.positionalArguments.first as String,
      ),
    );
    di.registerSingleton<TippersViewModel>(tippers);
    di.registerSingleton<IdentityService>(identity);

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
    verifyNever(() => identity.updateTipperAlias(any()));

    await tester.enterText(find.byType(TextField), '!!');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.textContaining('at least one letter or number'),
      findsOneWidget,
    );
    verifyNever(() => identity.updateTipperAlias(any()));

    await tester.enterText(find.byType(TextField), 'The Oracle');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => identity.updateTipperAlias('The Oracle')).called(1);
    verify(() => tippers.applyOwnAlias('tipper-1', 'The Oracle')).called(1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('the server refusing or failing to change the alias', () {
    Future<void> trySaving(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField), 'The Oracle');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    void expectStillOpenAndUnchanged(WidgetTester tester) {
      expect(find.byType(AlertDialog), findsOneWidget);
      verifyNever(() => tippers.applyOwnAlias(any(), any()));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
        reason: 'the tipper can try again',
      );
    }

    testWidgets('a name another tipper has says so, in plain words', (
      tester,
    ) async {
      await openDialog(tester, size: const Size(390, 844));

      when(() => identity.updateTipperAlias(any())).thenAnswer(
        (_) async => throw refused(reasons.identityReasonAliasTaken),
      );

      await trySaving(tester);

      expect(find.textContaining('already used by another tipper'), findsOne);
      expect(find.textContaining('server words'), findsNothing);
      expectStillOpenAndUnchanged(tester);
    });

    testWidgets('a name the server will not allow says so', (tester) async {
      await openDialog(tester, size: const Size(390, 844));

      when(() => identity.updateTipperAlias(any())).thenAnswer(
        (_) async => throw refused(reasons.identityReasonInvalidAlias),
      );

      await trySaving(tester);

      expect(find.textContaining('at least one letter or number'), findsOne);
      expectStillOpenAndUnchanged(tester);
    });

    testWidgets('a server that cannot be reached says nothing changed', (
      tester,
    ) async {
      await openDialog(tester, size: const Size(390, 844));

      when(() => identity.updateTipperAlias(any())).thenAnswer(
        (_) async => throw IdentityFailure.network(Exception('offline')),
      );

      await trySaving(tester);

      expect(find.textContaining('your name was not changed'), findsOne);
      expectStillOpenAndUnchanged(tester);
    });

    testWidgets('changing names switched off says so', (tester) async {
      await openDialog(tester, size: const Size(390, 844));

      when(() => identity.updateTipperAlias(any())).thenAnswer(
        (_) async => throw refused(reasons.identityReasonNotAvailable),
      );

      await trySaving(tester);

      expect(find.textContaining('switched off'), findsOne);
      expectStillOpenAndUnchanged(tester);
    });

    testWidgets('a second try after a refusal can succeed', (tester) async {
      await openDialog(tester, size: const Size(390, 844));

      var attempts = 0;
      when(() => identity.updateTipperAlias(any()))
          .thenAnswer((invocation) async {
            attempts++;
            if (attempts == 1) {
              throw refused(reasons.identityReasonAliasTaken);
            }
            return UpdateTipperAliasResult(
              tipperId: 'tipper-1',
              alias: invocation.positionalArguments.first as String,
            );
          });

      await trySaving(tester);
      await tester.enterText(find.byType(TextField), 'Another Name');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(() => tippers.applyOwnAlias('tipper-1', 'Another Name')).called(1);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  testWidgets('while the server is answering, Save cannot be pressed again', (
    tester,
  ) async {
    await openDialog(tester, size: const Size(390, 844));

    final answer = Completer<UpdateTipperAliasResult>();
    when(() => identity.updateTipperAlias(any()))
        .thenAnswer((_) => answer.future);

    await tester.enterText(find.byType(TextField), 'The Oracle');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    verify(() => identity.updateTipperAlias('The Oracle')).called(1);

    answer.complete(
      const UpdateTipperAliasResult(tipperId: 'tipper-1', alias: 'The Oracle'),
    );
    await tester.pumpAndSettle();
    verify(() => tippers.applyOwnAlias('tipper-1', 'The Oracle')).called(1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a tipper with no alias cannot back out', (tester) async {
    await openDialog(tester, size: const Size(390, 844), name: '');

    expect(find.text('Create Tipper Alias'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}
