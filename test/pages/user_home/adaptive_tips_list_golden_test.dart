import 'package:daufootytipping/dev/adaptive_tips_prototype.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/load_tips_fonts.dart';

void main() {
  setUpAll(() => loadTipsFonts(includeFallbacks: true));
  for (final width in [360, 768, 1280]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('multi-round list $width at $scale', (tester) async {
        tester.view.physicalSize = const Size(1600, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const AdaptiveTipsPrototypeApp());
        await tester.pumpAndSettle();
        tester.widget<Slider>(find.byKey(const Key('width'))).onChanged!(width.toDouble());
        tester.widget<Slider>(find.byKey(const Key('text-scale'))).onChanged!(scale);
        await tester.pumpAndSettle();
        final boundary = find.byKey(const Key('sample-list-visual'));
        final list = find.byKey(const Key('sample-list'));
        final scrollable = find.descendant(of: list, matching: find.byType(Scrollable)).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.pixels, 0);
        expect(find.byKey(const ValueKey('24-1')), findsOneWidget);
        Future<void> capture(String stage) async {
          expect(tester.takeException(), isNull);
          await expectLater(boundary,
              matchesGoldenFile('goldens/list-$width-$scale-$stage.png'));
        }
        await capture('startup');

        await tester.tap(find.widgetWithText(TextButton, 'Round 25'));
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(0));
        expect(find.byKey(const ValueKey('25-1')), findsOneWidget);
        // Show the previous round's final card and the incoming sticky header.
        position.jumpTo(position.pixels - 100);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('24-4')), findsOneWidget);
        await capture('round-boundary');

        await tester.tap(find.widgetWithText(TextButton, 'First tippable'));
        await tester.pumpAndSettle();
        final target = find.byKey(const ValueKey('27-3'));
        expect(target, findsOneWidget);
        final viewport = tester.getRect(boundary);
        final game = tester.getRect(target);
        expect(game.top, greaterThanOrEqualTo(viewport.top + 80 * scale - 1));
        expect(game.bottom, lessThanOrEqualTo(viewport.bottom + 1));
        await capture('first-tippable');
      });
    }
  }
}
