import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/pages/user_auth/user_auth_login_issue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    String message = 'We can\'t sign you in right now.',
    VoidCallback? onRetry,
    bool displaySignOutButton = true,
    Future<bool> Function(Uri url)? openUrl,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // The test font is wider than a real one: shrink it so the existing fixed-width
        // buttons are not what these tests are about.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.7)),
          child: child!,
        ),
        home: LoginIssueScreen(
          message: message,
          onRetry: onRetry,
          displaySignOutButton: displaySignOutButton,
          openUrl: openUrl ?? (Uri url) async => true,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the message with Retry, Sign Out and Get help', (
    tester,
  ) async {
    await pump(tester, onRetry: () {});
    expect(find.text('We can\'t sign you in right now.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.text(LoginIssueScreen.getHelpLabel), findsOneWidget);
  });

  testWidgets('Get help opens the support site', (tester) async {
    final opened = <Uri>[];
    await pump(
      tester,
      openUrl: (Uri url) async {
        opened.add(url);
        return true;
      },
    );
    await tester.tap(find.text(LoginIssueScreen.getHelpLabel));
    await tester.pump();
    expect(opened, [Uri.parse(p.supportUrl)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'a support site that cannot be opened is explained, with its address',
    (tester) async {
      await pump(tester, openUrl: (Uri url) async => false);
      await tester.tap(find.text(LoginIssueScreen.getHelpLabel));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining(p.supportUrl), findsOneWidget);
    },
  );

  testWidgets('a launcher that throws is handled the same way', (tester) async {
    await pump(
      tester,
      openUrl: (Uri url) async => throw StateError('no browser'),
    );
    await tester.tap(find.text(LoginIssueScreen.getHelpLabel));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
    'every error screen offers help, even with no Retry and no Sign Out',
    (tester) async {
      await pump(tester, displaySignOutButton: false);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Sign Out'), findsNothing);
      expect(find.text(LoginIssueScreen.getHelpLabel), findsOneWidget);
    },
  );

  testWidgets('Retry still retries', (tester) async {
    var retried = 0;
    await pump(tester, onRetry: () => retried++);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets(
    'on a short screen (a phone in landscape) it scrolls instead of overflowing',
    (tester) async {
      tester.view.physicalSize = const Size(800, 320);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester, onRetry: () {});
      expect(tester.takeException(), isNull);
      final scrollable = find.byType(SingleChildScrollView);
      expect(scrollable, findsOneWidget);
      await tester.dragUntilVisible(
        find.text(LoginIssueScreen.getHelpLabel),
        scrollable,
        const Offset(0, -100),
      );
      expect(find.text(LoginIssueScreen.getHelpLabel), findsOneWidget);
    },
  );
}
