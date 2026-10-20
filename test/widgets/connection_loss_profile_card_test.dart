import 'dart:async';

import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_panel_card.dart';
import 'package:daufootytipping/widgets/connection_loss_notice.dart';
import 'package:daufootytipping/widgets/connection_loss_profile_card.dart';
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

  Future<void> pumpCard(
    WidgetTester tester, {
    ThemeData? theme,
    double width = 400,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    // A stretch column, as the Profile page's cards sit in, beside a panel card
    // to compare widths with.
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: textScaler),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppPanelCard(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('another card'),
                      ),
                    ),
                    ConnectionLossProfileCard(monitor: monitor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> loseConnection(WidgetTester tester) async {
    connection.add(false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }

  test('the wording reassures about tips and gives the way back', () {
    expect(
      ConnectionLossProfileCard.detail,
      startsWith('Your tips are kept on this phone'),
    );
    expect(ConnectionLossProfileCard.detail, contains('lodged'));
    expect(ConnectionLossProfileCard.detail, contains('restart the app'));
    expect(
      ConnectionLossProfileCard.detail,
      isNot(contains('lost')),
      reason: 'the tips are queued, not lost',
    );
  });

  testWidgets('shows nothing while the connection is fine', (tester) async {
    await pumpCard(tester);
    connection.add(true);
    await tester.pump();

    expect(find.text(ConnectionLossProfileCard.heading), findsNothing);
  });

  testWidgets('says the connection is lost, and what to do', (tester) async {
    await pumpCard(tester);
    await loseConnection(tester);

    expect(find.text(ConnectionLossProfileCard.heading), findsOneWidget);
    expect(find.text(ConnectionLossProfileCard.detail), findsOneWidget);
    expect(find.textContaining('restart the app'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('cannot be dismissed: it has no controls at all', (tester) async {
    await pumpCard(tester);
    await loseConnection(tester);

    expect(
      find.descendant(
        of: find.byType(ConnectionLossProfileCard),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ConnectionLossProfileCard),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('stays when the banner has been dismissed', (tester) async {
    await pumpCard(tester);
    await loseConnection(tester);

    monitor.dismiss();
    await tester.pump();

    expect(monitor.noticeVisible, isFalse);
    expect(find.text(ConnectionLossProfileCard.heading), findsOneWidget);
  });

  testWidgets('goes away when the connection returns', (tester) async {
    await pumpCard(tester);
    await loseConnection(tester);

    connection.add(true);
    await tester.pump();
    await tester.pump();

    expect(find.text(ConnectionLossProfileCard.heading), findsNothing);
  });

  testWidgets('is as wide as the other cards', (tester) async {
    await pumpCard(tester);
    await loseConnection(tester);

    final other = tester.getSize(
      find.descendant(
        of: find.byType(AppPanelCard),
        matching: find.byType(Card),
      ),
    );
    final ours = tester.getSize(
      find.descendant(
        of: find.byType(ConnectionLossProfileCard),
        matching: find.byType(Card),
      ),
    );
    expect(ours.width, other.width);
    expect(ours.width, 400, reason: 'the full width of the column it sits in');
  });

  testWidgets('sits below the card above it, not over it', (tester) async {
    await pumpCard(tester);
    await loseConnection(tester);

    expect(
      tester.getTopLeft(find.byType(ConnectionLossProfileCard)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppPanelCard)).dy),
    );
  });

  testWidgets('uses the same AFL red and white as the banner', (tester) async {
    await pumpCard(tester);
    await loseConnection(tester);

    final card = tester.widget<Card>(
      find.descendant(
        of: find.byType(ConnectionLossProfileCard),
        matching: find.byType(Card),
      ),
    );
    expect(card.color, League.afl.colour);
    expect(card.color, ConnectionLossNotice.background);
    expect(
      tester
          .widget<Text>(find.text(ConnectionLossProfileCard.heading))
          .style
          ?.color,
      ConnectionLossNotice.foreground,
    );
  });

  testWidgets('announces itself to screen readers when it appears', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester);
    await loseConnection(tester);

    expect(
      tester.getSemantics(find.text(ConnectionLossProfileCard.detail)),
      matchesSemantics(
        label:
            '${ConnectionLossProfileCard.heading}\n'
            '${ConnectionLossProfileCard.detail}',
        isLiveRegion: true,
      ),
    );
    handle.dispose();
  });

  for (final theme in [ThemeData.light(), ThemeData.dark()]) {
    testWidgets('is drawn in the ${theme.brightness.name} theme', (
      tester,
    ) async {
      await pumpCard(tester, theme: theme);
      await loseConnection(tester);

      expect(find.text(ConnectionLossProfileCard.heading), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('fits a narrow screen at large text without overflowing', (
    tester,
  ) async {
    await pumpCard(tester, width: 320, textScaler: const TextScaler.linear(2));
    await loseConnection(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(ConnectionLossProfileCard.detail), findsOneWidget);
  });

  group('with the banner', () {
    late AppControlsViewModel controls;

    setUp(() => controls = AppControlsViewModel());
    tearDown(() => controls.dispose());

    Future<void> pumpApp(WidgetTester tester, {required Widget home}) {
      return tester.pumpWidget(
        appWithControls(
          controls,
          home: home,
          notice: ConnectionLossNotice(monitor: monitor),
        ),
      );
    }

    Widget cardPage() =>
        Scaffold(body: ConnectionLossProfileCard(monitor: monitor));

    Future<void> push(WidgetTester tester, Widget page) async {
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(MaterialPageRoute<void>(builder: (_) => page));
      await tester.pumpAndSettle();
    }

    testWidgets('the banner does not sit on top of the card', (tester) async {
      await pumpApp(tester, home: cardPage());
      await tester.pump();
      await loseConnection(tester);
      await tester.pump();

      expect(find.text(ConnectionLossProfileCard.heading), findsOneWidget);
      expect(find.text(ConnectionLossNotice.message), findsNothing);
    });

    testWidgets('a banner already showing is dismissed when the card appears', (
      tester,
    ) async {
      await pumpApp(tester, home: const Scaffold(body: Text('elsewhere')));
      await loseConnection(tester);
      expect(find.text(ConnectionLossNotice.message), findsOneWidget);

      await push(tester, cardPage());

      expect(find.text(ConnectionLossProfileCard.heading), findsOneWidget);
      expect(find.text(ConnectionLossNotice.message), findsNothing);
    });

    testWidgets('and it stays dismissed after leaving, for that outage', (
      tester,
    ) async {
      await pumpApp(tester, home: const Scaffold(body: Text('elsewhere')));
      await loseConnection(tester);
      await push(tester, cardPage());

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.text(ConnectionLossNotice.message), findsNothing);
      expect(monitor.connectionLost, isTrue);
    });

    testWidgets('a page pushed over the card lets the banner show', (
      tester,
    ) async {
      await pumpApp(tester, home: cardPage());
      await tester.pump();
      await push(tester, const Scaffold(body: Text('covering page')));

      await loseConnection(tester);
      await tester.pump();

      expect(find.text(ConnectionLossNotice.message), findsOneWidget);
    });

    testWidgets('uncovering the card dismisses the banner again', (
      tester,
    ) async {
      await pumpApp(tester, home: cardPage());
      await tester.pump();
      await push(tester, const Scaffold(body: Text('covering page')));
      await loseConnection(tester);
      await tester.pump();
      expect(find.text(ConnectionLossNotice.message), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.text(ConnectionLossNotice.message), findsNothing);
      expect(find.text(ConnectionLossProfileCard.heading), findsOneWidget);
    });

    testWidgets('once the card is gone a new outage shows the banner', (
      tester,
    ) async {
      await pumpApp(tester, home: cardPage());
      await tester.pump();
      await pumpApp(tester, home: const Scaffold(body: Text('no card now')));
      await tester.pump();

      await loseConnection(tester);
      await tester.pump();

      expect(find.text(ConnectionLossNotice.message), findsOneWidget);
    });
  });
}
