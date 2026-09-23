import 'package:daufootytipping/dev/adaptive_tips_samples.dart';
import 'package:daufootytipping/dev/adaptive_tips_prototype.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/load_tips_fonts.dart';

final _theme = ThemeData.localize(
    FlexThemeData.light(scheme: FlexScheme.green), Typography.englishLike2021);
TipsCardLayout _layout(double width, double scale, List<TipsCardDisplay> cards,
    {bool percentStats = false}) =>
    TipsCardLayout.measure(width: width, textScaler: TextScaler.linear(scale),
      textTheme: _theme.textTheme, textDirection: TextDirection.ltr,
      cards: [for (final card in cards) card.content(_theme.textTheme)], percentStats: percentStats);

void main() {
  setUpAll(loadTipsFonts);
  final samples = tipsSamples(selections: {}, saving: {});

  test('one tall result row does not reserve four tall rows', () {
    final theme = _theme.textTheme;
    final short = TextSpan(text: 'Result: Home', style: theme.bodyMedium);
    final tall = TextSpan(text: 'Your tip:\nAway\n13+', style: theme.bodyMedium);
    TipsCardLayout measure(List<TextSpan> results, {bool percent = false}) =>
        TipsCardLayout.measure(width: 900, textScaler: const TextScaler.linear(2.5),
          textTheme: theme, textDirection: TextDirection.ltr, percentStats: percent,
          cards: [TipsCardContent(home: TextSpan(text: 'A', style: theme.titleMedium),
            away: TextSpan(text: 'B', style: theme.titleMedium), info: '',
            results: results, editable: false)]);
    final mixed = measure([tall, short, short, short]);
    final repeated = measure([tall, tall, tall, tall]);
    expect(mixed.mode, TipsCardMode.standard);
    expect(mixed.carouselHeight, lessThan(repeated.carouselHeight));
    // Results are not a swipe panel on the percentage surface.
    expect(measure([tall, tall, tall, tall], percent: true).carouselHeight,
        measure([], percent: true).carouselHeight);
  });

  testWidgets('measured transitions are consistent and standard stays compact', (tester) async {
    final standard = _layout(390, 1, samples);
    expect(standard.mode, TipsCardMode.standard);
    expect(standard.cardExtent, 128);
    expect(_layout(240, 2, samples).choices, TipsChoiceArrangement.vertical);
    expect(_layout(360, 1, samples).mode, TipsCardMode.standard);
    expect(_layout(1600, 1, samples).mode, TipsCardMode.wide);
    expect(_layout(390, 3.2, samples).mode, TipsCardMode.stacked);
    for (final scale in [1.0, 1.5, 2.0, 3.2]) {
      final measured = _layout(390, scale, samples);
      expect(_layout(measured.wideMinWidth - 1, scale, samples).mode,
          isNot(TipsCardMode.wide));
      expect(_layout(measured.wideMinWidth + 1, scale, samples).mode,
          TipsCardMode.wide);
    }
  });

  for (final (width, scale) in [
    (240.0, 1.0), (320.0, 1.0), (360.0, 1.0), (390.0, 1.0),
    (768.0, 1.0), (844.0, 1.0), (1280.0, 1.0),
    (240.0, 2.0), (240.0, 3.2), (390.0, 1.5), (390.0, 2.5), (390.0, 3.2), (1280.0, 2.0),
  ]) {
    testWidgets('all panel states fit at width $width, text $scale', (tester) async {
      var errorDetails = '';
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        errorDetails = details.toString();
        previousErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousErrorHandler);
      tester.view.physicalSize = const Size(1800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cards = tipsSamples(selections: {}, saving: {}, longNames: scale > 1);
      for (final index in [0, 1, 6, 8, 9, 10, 11]) {
        final card = cards[index];
        for (final panel in [TipsPanel.tips, TipsPanel.result, TipsPanel.info, TipsPanel.percentages]) {
          final layout = _layout(width, scale, cards,
              percentStats: panel == TipsPanel.percentages);
          await tester.pumpWidget(MaterialApp(theme: _theme, home: Scaffold(
            body: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width,
                child: AdaptiveTipsCard(key: ValueKey('$index:$panel:$width:$scale'),
                  data: card, layout: layout, activePanel: panel,
                  percentStats: panel == TipsPanel.percentages,
                  onPanelChanged: (_) {}, onTip: (_) {},
                ),
              )),
            ),
          )));
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull,
              reason: '${card.id}, $panel, ${layout.mode}, ${layout.choices}\n$errorDetails');
        }
      }
    });
  }

  testWidgets('normal team names and scaled versus row fit at 3.2x', (tester) async {
    tester.view.physicalSize = const Size(1800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Long names add spare height and previously masked the scaled V overflow.
    for (final width in [390.0, 844.0, 976.0, 1280.0]) {
      for (final index in [0, 10, 11]) {
        await tester.pumpWidget(MaterialApp(theme: _theme, home: Scaffold(
          body: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(3.2)),
            child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width,
              child: AdaptiveTipsCard(key: ValueKey('$width:$index'),
                data: samples[index], layout: _layout(width, 3.2, samples),
                activePanel: TipsPanel.tips, onPanelChanged: (_) {}, onTip: (_) {}),
            )),
          ),
        )));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$width, ${samples[index].id}');
      }
    }
  });

  testWidgets('rotation preserves panel and selected tip, swiping preserves height', (tester) async {
    tester.view.physicalSize = const Size(1800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var panel = TipsPanel.tips;
    var selection = GameResult.e;
    Future<void> pump(double width, {bool kickoff = false}) async {
      final cards = tipsSamples(selections: {'27-3': selection}, saving: {}, kickoff: kickoff);
      final layout = _layout(width, 1, cards);
      await tester.pumpWidget(MaterialApp(theme: _theme, home: Scaffold(body: Align(
        alignment: Alignment.topLeft, child: SizedBox(width: width,
          child: AdaptiveTipsCard(key: const ValueKey('27-3'), data: cards[10], layout: layout,
            activePanel: panel, onPanelChanged: (value) => panel = value,
            onTip: (value) => selection = value),
        ),
      ))));
      await tester.pumpAndSettle();
    }
    await pump(390);
    await tester.tap(find.text('Home'));
    expect(selection, GameResult.b);
    final height = tester.getSize(find.byType(AdaptiveTipsCard)).height;
    await tester.drag(find.byType(AdaptiveTipsCard), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(panel, TipsPanel.info);
    expect(tester.getSize(find.byType(AdaptiveTipsCard)).height, height);
    await pump(1280);
    expect(panel, TipsPanel.info);
    expect(selection, GameResult.b);
    await pump(390, kickoff: true);
    expect(panel, TipsPanel.info);
    expect(find.textContaining('Kickoff:').hitTestable(), findsOneWidget);
  });

  testWidgets('panels fit immediately on each side of measured transitions', (tester) async {
    tester.view.physicalSize = const Size(3000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scale in [1.0, 1.5, 2.0]) {
      final measured = _layout(390, scale, samples);
      for (final threshold in [measured.standardMinWidth, measured.wideMinWidth]) {
        for (final width in [threshold - 1, threshold + 1]) {
          for (final percentages in [false, true]) {
            await tester.pumpWidget(MaterialApp(theme: _theme, home: Scaffold(
              body: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width,
                  child: AdaptiveTipsCard(key: ValueKey('$width:$scale:$percentages'),
                    data: samples[1], layout: _layout(width, scale, samples, percentStats: percentages),
                    activePanel: TipsPanel.tips, percentStats: percentages,
                    onPanelChanged: (_) {}, onTip: (_) {}),
                )),
              ),
            )));
            await tester.pump();
            expect(tester.takeException(), isNull, reason: '$width, $scale, $percentages');
          }
        }
      }
    }
  });

  testWidgets('keyboard changes carousel panel without changing the tip', (tester) async {
    var panel = TipsPanel.tips;
    await tester.pumpWidget(MaterialApp(theme: _theme, home: Scaffold(body: Center(
      child: SizedBox(width: 390, child: AdaptiveTipsCard(
        data: samples[10], layout: _layout(390, 1, samples), activePanel: panel,
        onPanelChanged: (value) => panel = value, onTip: (_) {},
      )),
    ))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(panel, TipsPanel.info);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sample list keeps the viewed game through rotation', (tester) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AdaptiveTipsPrototypeApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Round 25'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('25-1')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('rotate')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('25-1')).hitTestable(), findsOneWidget);
  });
}
