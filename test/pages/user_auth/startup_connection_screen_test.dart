import 'dart:async';

import 'package:daufootytipping/pages/user_auth/startup_connection_screen.dart';
import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:daufootytipping/widgets/notice_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<bool?> connection;
  late ConnectionLossMonitor monitor;

  setUp(() {
    connection = StreamController<bool?>.broadcast();
    monitor = ConnectionLossMonitor(
      connectionStates: connection.stream,
      threshold: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    monitor.dispose();
    await connection.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<void> Function()? onRetry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartupConnectionScreen(
          monitor: monitor,
          onRetry: onRetry ?? () async {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the message in the banner with Retry and no dismiss', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text(StartupConnectionScreen.message), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NoticeBanner),
        matching: find.text(StartupConnectionScreen.retryLabel),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the wording gives a step to try and the way back', () {
    expect(StartupConnectionScreen.message, contains('Retry'));
    expect(StartupConnectionScreen.message, contains('reopen the app'));
  });

  testWidgets('Retry shows progress until the attempt finishes', (
    tester,
  ) async {
    final Completer<void> attempt = Completer<void>();
    int calls = 0;
    await pumpScreen(
      tester,
      onRetry: () {
        calls++;
        return attempt.future;
      },
    );

    await tester.tap(find.text(StartupConnectionScreen.retryLabel));
    await tester.pump();

    expect(calls, 1);
    expect(find.text(StartupConnectionScreen.retryLabel), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
      reason: 'a second tap must not start another attempt',
    );

    attempt.complete();
    await tester.pump();

    expect(find.text(StartupConnectionScreen.retryLabel), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Retry comes back after a failed attempt', (tester) async {
    await pumpScreen(
      tester,
      onRetry: () => Future<void>.error(StateError('still offline')),
    );

    await tester.tap(find.text(StartupConnectionScreen.retryLabel));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(StartupConnectionScreen.retryLabel), findsOneWidget);
  });

  testWidgets('keeps the app-wide banner away while on screen', (tester) async {
    await pumpScreen(tester);

    connection.add(false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();

    expect(monitor.connectionLost, isTrue);
    expect(monitor.noticeVisible, isFalse);
  });

  testWidgets('fits a narrow screen at large text without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: StartupConnectionScreen(
            monitor: monitor,
            onRetry: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(StartupConnectionScreen.message), findsOneWidget);
  });
}
