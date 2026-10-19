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
  test('percentage chips go inline as soon as they fit', () {
    final cards = tipsSamples(selections: {}, saving: {});
    TipsCardLayout layoutAt(double width) => TipsCardLayout.measure(
      width: width,
      textScaler: TextScaler.noScaling,
      textTheme: theme.textTheme,
      textDirection: TextDirection.ltr,
      cards: [for (final c in cards) c.content(theme.textTheme)],
      percentStats: true,
    );

    // A narrow phone keeps the pyramid beside the matchup.
    expect(layoutAt(390).choices, TipsChoiceArrangement.paired);
    // Between a phone and a tablet the matchup moves above one row of chips.
    final middle = layoutAt(560);
    expect(middle.mode, TipsCardMode.stacked);
    expect(middle.choices, TipsChoiceArrangement.inline);
    // Wider still, the matchup returns to the left of one row of chips.
    expect(layoutAt(700).mode, isNot(TipsCardMode.stacked));
    expect(layoutAt(700).choices, TipsChoiceArrangement.inline);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('percentage cards fit at every width, text scale $scale', (
      tester,
    ) async {
      final failures = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) =>
          failures.add(details.exceptionAsString().split('\n').first);
      addTearDown(() => FlutterError.onError = previous);
      tester.view.physicalSize = const Size(1500, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cards = tipsSamples(
        selections: {},
        saving: {},
        longNames: scale > 1,
      );
      for (var w = 300; w <= 1300; w += 20) {
        final layout = TipsCardLayout.measure(
          width: w.toDouble(),
          textScaler: TextScaler.linear(scale),
          textTheme: theme.textTheme,
          textDirection: TextDirection.ltr,
          cards: [for (final c in cards) c.content(theme.textTheme)],
          percentStats: true,
        );
        for (final i in [0, 6, 10]) {
          final card = TipsCardDisplay(
            id: cards[i].id,
            home: cards[i].home,
            away: cards[i].away,
            league: cards[i].league,
            info: cards[i].info,
            status: TipsStatus.finalScore,
            selected: GameResult.d,
            result: GameResult.d,
            percentages: const [100.0, 100.0, 100.0, 100.0, 100.0],
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: w.toDouble(),
                      height: layout.cardExtent,
                      child: AdaptiveTipsCard(
                        key: ValueKey('$w:$i'),
                        data: card,
                        layout: layout,
                        activePanel: TipsPanel.percentages,
                        percentStats: true,
                        onPanelChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          if (failures.isNotEmpty) {
            // ignore: avoid_print
            print(
              'FAIL w=$w card=$i ${layout.mode.name}/${layout.choices.name}: ${failures.first}',
            );
            failures.clear();
          }
        }
      }
    });
  }
}
