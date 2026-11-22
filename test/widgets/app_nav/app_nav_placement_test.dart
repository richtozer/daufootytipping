import 'package:daufootytipping/widgets/app_nav/app_nav_placement.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appNavPlacement', () {
    const phonePortrait = Size(390, 844);
    const phoneLandscape = Size(844, 390);
    const foldedDuo = Size(420, 300);
    const innerDuoLandscape = Size(700, 480);
    const tabletLandscape = Size(1180, 820);
    const desktopWindow = Size(1440, 900);

    AppNavPlacement placement(
      Size size, [
      EdgeInsets padding = EdgeInsets.zero,
    ]) => appNavPlacement(size: size, displayPadding: padding);

    test('a phone in portrait keeps the pill along the bottom', () {
      expect(placement(phonePortrait), AppNavPlacement.bottom);
    });

    test('a phone in landscape takes the side, with or without insets', () {
      expect(placement(phoneLandscape), AppNavPlacement.trailingEdge);
      expect(
        placement(phoneLandscape, const EdgeInsets.symmetric(horizontal: 62)),
        AppNavPlacement.trailingEdge,
      );
    });

    test('a right inset wide enough to hold the pill earns it for free', () {
      expect(
        placement(
          phonePortrait,
          const EdgeInsets.only(right: kSideControlsInsetWidth),
        ),
        AppNavPlacement.trailingEdge,
      );
    });

    test('a narrower right inset keeps the bottom pill', () {
      expect(
        placement(
          phonePortrait,
          const EdgeInsets.only(right: kSideControlsInsetWidth - 1),
        ),
        AppNavPlacement.bottom,
      );
    });

    test('a left inset is no place for a pill that is always on the right', () {
      expect(
        placement(phonePortrait, const EdgeInsets.only(left: 200)),
        AppNavPlacement.bottom,
      );
    });

    test('a folded Duo puts the pill in its camera strip', () {
      expect(
        placement(
          foldedDuo,
          const EdgeInsets.only(right: kSideControlsInsetWidth + 8),
        ),
        AppNavPlacement.trailingEdge,
      );
    });

    test(
      'an open Duo in landscape keeps the pill where the folded one has it',
      () {
        expect(
          placement(
            innerDuoLandscape,
            const EdgeInsets.only(right: kSideControlsInsetWidth + 8),
          ),
          AppNavPlacement.trailingEdge,
        );
      },
    );

    test('a tall or generous pane keeps the bottom pill', () {
      expect(placement(tabletLandscape), AppNavPlacement.bottom);
      expect(placement(desktopWindow), AppNavPlacement.bottom);
    });

    test('a short pane with no width to spare keeps the bottom pill', () {
      expect(
        placement(const Size(kWideEnoughForRail - 1, 400)),
        AppNavPlacement.bottom,
      );
    });

    test('a short wide browser window takes the side', () {
      expect(placement(const Size(1280, 480)), AppNavPlacement.trailingEdge);
    });

    test('vertical insets are not somewhere to put a pill', () {
      expect(
        placement(phonePortrait, const EdgeInsets.only(top: 200, bottom: 200)),
        AppNavPlacement.bottom,
      );
    });
  });

  group('sideControlsBottomClearance', () {
    test('a folded Duo lifts the controls above its corner camera', () {
      expect(
        sideControlsBottomClearance(size: const Size(480, 340)),
        kCornerCameraClearance,
      );
      expect(
        sideControlsBottomClearance(size: const Size(340, 480)),
        kCornerCameraClearance,
      );
    });

    test('a phone in landscape has no corner camera to clear', () {
      expect(sideControlsBottomClearance(size: const Size(844, 390)), 0);
    });

    test('a tablet-sized pane never does', () {
      expect(sideControlsBottomClearance(size: const Size(1024, 768)), 0);
    });
  });
}
