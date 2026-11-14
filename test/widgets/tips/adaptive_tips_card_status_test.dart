import 'package:daufootytipping/dev/adaptive_tips_samples.dart';
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

  Future<TipsCardLayout> pumpCard(WidgetTester tester, double width) async {
    final sample = tipsSamples(selections: {}, saving: {}).first;
    final card = TipsCardDisplay(
      id: 'status',
      home: sample.home,
      away: sample.away,
      league: sample.league,
      info: sample.info,
      status: TipsStatus.today,
    );
    final layout = TipsCardLayout.measure(
      width: width,
      textScaler: TextScaler.noScaling,
      textTheme: theme.textTheme,
      textDirection: TextDirection.ltr,
      cards: [card.content(theme.textTheme)],
    );
    tester.view.physicalSize = Size(width, 800);
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
            activePanel: TipsPanel.tips,
            onPanelChanged: (_) {},
            onTip: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return layout;
  }

  Banner statusBanner(WidgetTester tester) => tester.widget<Banner>(
    find.byWidgetPredicate(
      (widget) => widget is Banner && widget.message == 'Game today',
    ),
  );

  testWidgets('a wide card ribbons its status over the matchup corner', (
    tester,
  ) async {
    final layout = await pumpCard(tester, 1100);

    expect(layout.mode, TipsCardMode.wide);
    expect(statusBanner(tester).location, BannerLocation.topStart);
  });

  testWidgets('a phone card ribbons its status over the matchup corner', (
    tester,
  ) async {
    final layout = await pumpCard(tester, 390);

    expect(layout.mode, isNot(TipsCardMode.wide));
    expect(statusBanner(tester).location, BannerLocation.topStart);
  });
}
