import 'dart:async';

import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/dau_shared.dart'
    show AdminMergeTippersResult, deletedTipperName;
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tipper_merge.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/app_controls_test_app.dart';

class _MockTippersViewModel extends Mock implements TippersViewModel {}

class _MockIdentityService extends Mock implements IdentityService {}

void main() {
  late _MockTippersViewModel tippers;
  late _MockIdentityService identity;
  late AppControlsViewModel appControls;
  late Tipper source;

  Tipper tipperNamed(String key, String name) => Tipper(
    dbkey: key,
    compsPaidFor: const [],
    authuid: 'uid-$key',
    email: '$key@example.test',
    logon: '$key-login@example.test',
    name: name,
    tipperRole: TipperRole.tipper,
  );

  const preview = AdminMergeTippersResult(
    targetId: 'target',
    tipsMoved: 5,
    tipsReplaced: 2,
    loginMoved: true,
    accountMoved: true,
    dryRun: true,
  );
  const done = AdminMergeTippersResult(
    targetId: 'target',
    tipsMoved: 5,
    tipsReplaced: 2,
    loginMoved: true,
    accountMoved: true,
    dryRun: false,
  );

  Future<AdminMergeTippersResult> merge({required bool dryRun}) =>
      identity.adminMergeTippers(
        originalId: 'source',
        targetId: 'target',
        mergeTips: true,
        mergeLogon: true,
        dryRun: dryRun,
      );

  Future<void> pumpMergePage(WidgetTester tester) async {
    await tester.pumpWidget(
      appWithControls(
        appControls,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    // Two pages deep, as in the app (list, edit, merge): a merge goes back to the list.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('the edit page')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AdminTipperMergeEditPage(tippers, source),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseTarget(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButton<Tipper>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target').last);
    // Not pumpAndSettle: while the preview is pending its spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> tapMerge(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(AdminTipperMergeEditPage.mergeButtonKey),
    );
    await tester.pump();
    await tester.tap(find.byKey(AdminTipperMergeEditPage.mergeButtonKey));
    await tester.pumpAndSettle();
  }

  VoidCallback? mergeAction(WidgetTester tester) => tester
      .widget<ElevatedButton>(
        find.byKey(AdminTipperMergeEditPage.mergeButtonKey),
      )
      .onPressed;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;
    appControls = registerAppControlsViewModel();
    source = tipperNamed('source', 'Source');
    tippers = _MockTippersViewModel();
    when(() => tippers.tippers).thenReturn([
      source,
      tipperNamed('target', 'Target'),
      tipperNamed('other', 'Other'),
    ]);
    identity = _MockIdentityService();
    di.registerSingleton<IdentityService>(identity);
  });

  tearDown(() async => di.reset());

  testWidgets(
    'choosing a target asks the server what a merge would do, and does not merge',
    (tester) async {
      when(() => merge(dryRun: true)).thenAnswer((_) async => preview);
      await pumpMergePage(tester);

      await chooseTarget(tester);

      verify(() => merge(dryRun: true)).called(1);
      verifyNever(() => merge(dryRun: false));
      expect(find.text('• move 5 tips to Target'), findsOneWidget);
      expect(
        find.textContaining('replace 2 tips Target already has'),
        findsOneWidget,
      );
      expect(find.text('• move the login to Target'), findsOneWidget);
      expect(find.text('• move the sign-in account to Target'), findsOneWidget);
      expect(find.text('• delete Source'), findsOneWidget);
      expect(mergeAction(tester), isNotNull);
    },
  );

  testWidgets(
    'a tipper who deleted their account cannot be chosen as the target',
    (tester) async {
      when(() => tippers.tippers).thenReturn([
        source,
        tipperNamed('target', 'Target'),
        Tipper(
          dbkey: 'gone',
          compsPaidFor: const [],
          authuid: '',
          email: null,
          name: deletedTipperName,
          tipperRole: TipperRole.tipper,
          accountDeletedUTC: DateTime.utc(2026, 11, 11),
        ),
        tipperNamed('other', 'Other'),
      ]);
      await pumpMergePage(tester);

      await tester.tap(find.byType(DropdownButton<Tipper>));
      await tester.pumpAndSettle();

      expect(find.text('Target'), findsWidgets);
      expect(find.text('Other'), findsWidgets);
      expect(
        find.text(deletedTipperName),
        findsNothing,
        reason:
            'the history is merged into the record they signed up with again',
      );
    },
  );

  testWidgets('says that paid competitions are not merged', (tester) async {
    await pumpMergePage(tester);

    expect(
      find.textContaining('paid competitions will not be merged'),
      findsOneWidget,
    );
    expect(find.textContaining('tick the target as paid'), findsOneWidget);
  });

  testWidgets('merging waits for the preview', (tester) async {
    final pending = Completer<AdminMergeTippersResult>();
    when(() => merge(dryRun: true)).thenAnswer((_) => pending.future);
    await pumpMergePage(tester);

    await chooseTarget(tester);
    expect(mergeAction(tester), isNull);

    pending.complete(preview);
    await tester.pumpAndSettle();
    expect(mergeAction(tester), isNotNull);
  });

  testWidgets('a refused preview is explained, and merging stays off', (
    tester,
  ) async {
    when(() => merge(dryRun: true)).thenAnswer(
      (_) async => throw const IdentityFailure(
        kind: IdentityFailureKind.refused,
        code: 'failed-precondition',
        message: 'server words',
        reason: reasons.identityReasonClaimed,
      ),
    );
    await pumpMergePage(tester);

    await chooseTarget(tester);

    expect(find.textContaining('already belongs'), findsOneWidget);
    expect(mergeAction(tester), isNull);
  });

  testWidgets(
    'merging asks first, then merges for real and goes back to the list',
    (tester) async {
      when(() => merge(dryRun: true)).thenAnswer((_) async => preview);
      when(() => merge(dryRun: false)).thenAnswer((_) async => done);
      await pumpMergePage(tester);
      await chooseTarget(tester);

      await tapMerge(tester);
      await tester.pumpAndSettle();
      expect(find.text('Confirm Merge'), findsOneWidget);
      verifyNever(() => merge(dryRun: false));

      await tester.tap(find.widgetWithText(TextButton, 'Merge'));
      await tester.pumpAndSettle();

      verify(() => merge(dryRun: false)).called(1);
      expect(find.byType(AdminTipperMergeEditPage), findsNothing);
      expect(find.text('the edit page'), findsNothing);
      expect(
        find.text('Merged Source into Target: 5 tips moved.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('cancelling the confirmation merges nothing', (tester) async {
    when(() => merge(dryRun: true)).thenAnswer((_) async => preview);
    await pumpMergePage(tester);
    await chooseTarget(tester);

    await tapMerge(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => merge(dryRun: false));
    expect(find.byType(AdminTipperMergeEditPage), findsOneWidget);
  });

  testWidgets(
    'a merge the server could not finish is explained and can be run again',
    (tester) async {
      when(() => merge(dryRun: true)).thenAnswer((_) async => preview);
      when(() => merge(dryRun: false)).thenAnswer(
        (_) async => throw const IdentityFailure(
          kind: IdentityFailureKind.transient,
          code: 'aborted',
          message: 'server words',
          reason: reasons.identityReasonBusy,
        ),
      );
      await pumpMergePage(tester);
      await chooseTarget(tester);

      await tapMerge(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Merge'));
      await tester.pumpAndSettle();

      expect(find.text('Merge not completed'), findsOneWidget);
      expect(find.textContaining('in progress'), findsOneWidget);
      expect(
        find.textContaining('running it again finishes it'),
        findsOneWidget,
      );
      expect(find.textContaining('server words'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminTipperMergeEditPage), findsOneWidget);
      expect(mergeAction(tester), isNotNull);
    },
  );
}
