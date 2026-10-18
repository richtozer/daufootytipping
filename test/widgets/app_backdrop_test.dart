import 'dart:math' as math;

import 'package:daufootytipping/widgets/app_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Alignment original;
  late math.Random originalRandom;
  setUp(() {
    original = AppBackdrop.viewport;
    originalRandom = AppBackdrop.random;
    AppBackdrop.reset();
  });
  tearDown(() {
    AppBackdrop.viewport = original;
    AppBackdrop.random = originalRandom;
    AppBackdrop.reset();
  });

  Future<Image> pumpBackdrop(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: AppBackdrop(),
        ),
      ),
    );
    return tester.widget<Image>(find.byType(Image));
  }

  testWidgets('keeps its proportions on a wide display', (tester) async {
    final image = await pumpBackdrop(tester, const Size(1600, 900));

    // Cover crops and zooms instead of stretching to fill.
    expect(image.fit, BoxFit.cover);
    expect(tester.getSize(find.byType(AppBackdrop)), const Size(1600, 900));
  });

  testWidgets('shows the part of the picture it was told to', (tester) async {
    AppBackdrop.viewport = const Alignment(-0.4, 0.7);

    final image = await pumpBackdrop(tester, const Size(1600, 900));

    expect(image.alignment, const Alignment(-0.4, 0.7));
  });

  test('a random viewport always lies within the picture', () {
    final source = math.Random(7);
    final seen = <Alignment>{};
    for (var i = 0; i < 200; i++) {
      final viewport = AppBackdrop.randomViewport(source);
      expect(viewport.x, inInclusiveRange(-1, 1));
      expect(viewport.y, inInclusiveRange(-1, 1));
      seen.add(viewport);
    }
    expect(seen.length, greaterThan(100), reason: 'it really does vary');
  });

  group('picking a new crop', () {
    test('keeps the crop while the screen keeps its shape', () {
      AppBackdrop.random = math.Random(1);
      final first = AppBackdrop.viewportFor(const Size(1200, 800));

      // A browser window dragged a little, or the same shape on another phone.
      expect(AppBackdrop.viewportFor(const Size(1300, 800)), first);
      expect(AppBackdrop.viewportFor(const Size(1100, 820)), first);
      expect(AppBackdrop.viewportFor(const Size(1200, 800)), first);
    });

    test('picks a new crop when the phone is turned', () {
      AppBackdrop.random = math.Random(2);
      final portrait = AppBackdrop.viewportFor(const Size(390, 844));

      final landscape = AppBackdrop.viewportFor(const Size(844, 390));
      final turnedBack = AppBackdrop.viewportFor(const Size(390, 844));

      expect(landscape, isNot(portrait));
      expect(turnedBack, isNot(landscape));
    });

    test('picks a new crop when a Duo folds to a different shape', () {
      AppBackdrop.random = math.Random(3);
      final folded = AppBackdrop.viewportFor(const Size(480, 340));

      final open = AppBackdrop.viewportFor(const Size(340, 600));

      expect(open, isNot(folded));
    });

    test('keeps the crop for a drag that stays near the same shape', () {
      AppBackdrop.random = math.Random(4);
      final first = AppBackdrop.viewportFor(const Size(1000, 800));

      // Each step is small next to the shape the crop was picked for, so a
      // slow drag does not re-roll it on every pixel.
      for (var width = 1010.0; width <= 1200; width += 10) {
        expect(AppBackdrop.viewportFor(Size(width, 800)), first);
      }
    });

    test('ignores a screen with no size', () {
      AppBackdrop.random = math.Random(5);
      final first = AppBackdrop.viewportFor(const Size(1200, 800));

      expect(AppBackdrop.viewportFor(Size.zero), first);
    });
  });

  testWidgets('every screen draws the same crop at the same shape', (
    tester,
  ) async {
    AppBackdrop.random = math.Random(6);

    final first = await pumpBackdrop(tester, const Size(1200, 800));
    final second = await pumpBackdrop(tester, const Size(1260, 800));

    expect(first.alignment, second.alignment);
  });

  testWidgets('turning the screen draws a new crop', (tester) async {
    AppBackdrop.random = math.Random(8);

    final portrait = await pumpBackdrop(tester, const Size(390, 844));
    final landscape = await pumpBackdrop(tester, const Size(844, 390));

    expect(landscape.alignment, isNot(portrait.alignment));
  });
}
