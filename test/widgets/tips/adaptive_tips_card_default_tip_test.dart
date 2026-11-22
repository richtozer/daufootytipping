import 'package:daufootytipping/dev/adaptive_tips_samples.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/load_tips_fonts.dart';

void main() {
  setUpAll(loadTipsFonts);

  final theme = ThemeData.localize(
    FlexThemeData.light(scheme: FlexScheme.green),
    Typography.englishLike2021,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    bool defaultTip = false,
    TipsStatus status = TipsStatus.finalScore,
    VoidCallback? onInterimScore,
  }) async {
    final sample = tipsSamples(selections: {}, saving: {}).first;
    final card = TipsCardDisplay(
      id: 'default-tip',
      home: sample.home,
      away: sample.away,
      league: sample.league,
      info: sample.info,
      status: status,
      selected: GameResult.d,
      result: GameResult.d,
      points: '2 / 2',
      average: '1.0 / 2',
      defaultTip: defaultTip,
    );
    final layout = TipsCardLayout.measure(
      width: 390,
      textScaler: TextScaler.noScaling,
      textTheme: theme.textTheme,
      textDirection: TextDirection.ltr,
      cards: [card.content(theme.textTheme)],
    );
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AdaptiveTipsCard(
            data: card,
            layout: layout,
            activePanel: TipsPanel.result,
            onPanelChanged: (_) {},
            onTip: (_) {},
            onInterimScore: onInterimScore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a default tip carries an (i) that explains it', (tester) async {
    await pumpCard(tester, defaultTip: true);

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pump();
    expect(
      find.textContaining('automatically given a default tip'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tip the tipper chose has no (i)', (tester) async {
    await pumpCard(tester, defaultTip: false);

    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a game on an interim score says so and opens the list', (
    tester,
  ) async {
    var opened = 0;
    await pumpCard(
      tester,
      status: TipsStatus.interim,
      onInterimScore: () => opened++,
    );

    expect(
      find.byTooltip('Scores are based on interim live score data.'),
      findsOneWidget,
    );
    await tester.tap(find.textContaining('Result:'));
    expect(opened, 1);
  });

  testWidgets('a final score is not tappable as an interim one', (
    tester,
  ) async {
    var opened = 0;
    await pumpCard(tester, onInterimScore: () => opened++);

    expect(
      find.byTooltip('Scores are based on interim live score data.'),
      findsNothing,
    );
    await tester.tap(find.textContaining('Result:'));
    expect(opened, 0);
  });

  testWidgets('average points explains itself', (tester) async {
    await pumpCard(tester);

    expect(
      find.byTooltip(
        'This is the average points collected by tippers for this game. Your aim is to collect more points than this to improve your ranking. If the game score is not finalised then this is an interim average.',
      ),
      findsOneWidget,
    );
  });
}
