import 'dart:async';

import 'package:daufootytipping/pages/user_home/user_home_profile_delete_dialog.dart';
import 'package:daufootytipping/services/account_deletion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _switchedOff =
    'Deleting accounts is switched off at the moment. Nothing was deleted. '
    'Please try again later.';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required Future<String?> Function() deleteAccount,
    required Future<void> Function() onDeleted,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DeleteAccountDialog(
                    deleteAccount: deleteAccount,
                    onDeleted: onDeleted,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  TextButton button(WidgetTester tester, {required bool last}) {
    final Finder buttons = find.byType(TextButton);
    return tester.widget<TextButton>(last ? buttons.last : buttons.first);
  }

  testWidgets('a refusal is shown in the dialog, which stays open and usable', (
    tester,
  ) async {
    var deleted = 0;
    await open(
      tester,
      deleteAccount: () async => _switchedOff,
      onDeleted: () async => deleted++,
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text(_switchedOff), findsOneWidget);
    expect(find.text('Confirm Account Deletion'), findsOneWidget);
    expect(button(tester, last: false).onPressed, isNotNull, reason: 'Cancel');
    expect(button(tester, last: true).onPressed, isNotNull, reason: 'Delete');
    expect(deleted, 0);
  });

  testWidgets('trying again after a refusal clears it, and goes ahead', (
    tester,
  ) async {
    final results = <String?>[_switchedOff, null];
    var deleted = 0;
    await open(
      tester,
      deleteAccount: () async => results.removeAt(0),
      onDeleted: () async => deleted++,
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text(_switchedOff), findsOneWidget);

    await tester.tap(find.text('Delete'));
    // The real onDeleted leaves the page; the stub leaves the dialog and its
    // spinner on screen, so pump frames rather than wait for it to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(_switchedOff), findsNothing);
    expect(deleted, 1);
  });

  testWidgets('shows progress and locks both buttons while it runs', (
    tester,
  ) async {
    final Completer<String?> running = Completer<String?>();
    var deleted = 0;
    await open(
      tester,
      deleteAccount: () => running.future,
      onDeleted: () async => deleted++,
    );

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(button(tester, last: false).onPressed, isNull, reason: 'Cancel');
    expect(button(tester, last: true).onPressed, isNull, reason: 'Delete');

    running.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(deleted, 1);
  });

  testWidgets('an unexpected error is reported in the dialog too', (
    tester,
  ) async {
    await open(
      tester,
      deleteAccount: () async => throw StateError('boom'),
      onDeleted: () async {},
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text(AccountDeletion.deletionFailedMessage), findsOneWidget);
    expect(find.text('Confirm Account Deletion'), findsOneWidget);
  });

  testWidgets('Cancel closes it without deleting anything', (tester) async {
    var asked = 0;
    await open(
      tester,
      deleteAccount: () async {
        asked++;
        return null;
      },
      onDeleted: () async {},
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Account Deletion'), findsNothing);
    expect(asked, 0);
  });
}
