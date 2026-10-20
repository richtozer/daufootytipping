import 'dart:async';

import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/connection_loss_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_controls_test_app.dart';

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

  Future<void> pumpNotice(WidgetTester tester, {ThemeData? theme}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ConnectionLossNotice(monitor: monitor),
          ),
        ),
      ),
    );
  }

  Future<void> showNotice(WidgetTester tester) async {
    connection.add(false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }

  testWidgets('shows in the app as main.dart places it, above the Navigator', (
    tester,
  ) async {
    final controls = AppControlsViewModel();
    addTearDown(controls.dispose);
    await tester.pumpWidget(
      appWithControls(
        controls,
        home: const Scaffold(body: Text('home')),
        notice: ConnectionLossNotice(monitor: monitor),
      ),
    );
    await showNotice(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(ConnectionLossNotice.message), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(ConnectionLossNotice.message), findsNothing);
  });

  testWidgets('shows nothing while the connection is fine', (tester) async {
    await pumpNotice(tester);
    connection.add(true);
    await tester.pump();

    expect(find.text(ConnectionLossNotice.message), findsNothing);
  });

  testWidgets('says to restart the app once the connection has been down', (
    tester,
  ) async {
    await pumpNotice(tester);
    await showNotice(tester);

    expect(find.text(ConnectionLossNotice.message), findsOneWidget);
    expect(find.textContaining('restart the app'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets(
    'announces the message to screen readers and keeps Dismiss reachable',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpNotice(tester);
      await showNotice(tester);

      expect(
        tester.getSemantics(find.text(ConnectionLossNotice.message)),
        matchesSemantics(
          label: ConnectionLossNotice.message,
          isLiveRegion: true,
        ),
      );
      expect(
        tester.getSemantics(find.byIcon(Icons.close)),
        matchesSemantics(
          label: ConnectionLossNotice.dismissLabel,
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    },
  );

  testWidgets('goes away when the connection returns', (tester) async {
    await pumpNotice(tester);
    await showNotice(tester);

    connection.add(true);
    await tester.pump();
    await tester.pump();

    expect(find.text(ConnectionLossNotice.message), findsNothing);
  });

  testWidgets('can be dismissed', (tester) async {
    await pumpNotice(tester);
    await showNotice(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text(ConnectionLossNotice.message), findsNothing);
    expect(monitor.noticeVisible, isFalse);
  });

  testWidgets('is readable in the dark theme', (tester) async {
    await pumpNotice(tester, theme: ThemeData.dark());
    await showNotice(tester);

    expect(find.text(ConnectionLossNotice.message), findsOneWidget);
    expect(tester.takeException(), isNull);
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
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ConnectionLossNotice(monitor: monitor),
            ),
          ),
        ),
      ),
    );
    await showNotice(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(ConnectionLossNotice.message), findsOneWidget);
  });
}
