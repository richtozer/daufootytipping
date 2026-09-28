import 'package:daufootytipping/pages/user_home/user_home_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Navigation placement', () {
    const phonePortrait = Size(390, 844);
    const phoneLandscape = Size(844, 390);
    const tabletLandscape = Size(1180, 820);

    bool rail(Size size, [EdgeInsets padding = EdgeInsets.zero]) =>
        shouldUseNavigationRail(size: size, displayPadding: padding);

    test('an inset wide enough to hold the rail earns one for free', () {
      expect(
        rail(phonePortrait, const EdgeInsets.only(right: kNavigationRailWidth)),
        isTrue,
      );
      expect(
        rail(phonePortrait, const EdgeInsets.only(left: kNavigationRailWidth)),
        isTrue,
      );
    });

    test('a narrower inset keeps the bar rather than cramping the rail', () {
      expect(
        rail(
          phonePortrait,
          const EdgeInsets.only(right: kNavigationRailWidth - 1),
        ),
        isFalse,
      );
    });

    test('a short wide pane buys the rail out of its width', () {
      // A phone in landscape: the bar spends height the pane has least of,
      // and a notch inset alone is too narrow to pay for the rail.
      expect(rail(phoneLandscape), isTrue);
      expect(rail(phoneLandscape, const EdgeInsets.only(left: 59)), isTrue);
    });

    test('a tall pane keeps the bar however wide it is', () {
      expect(rail(phonePortrait), isFalse);
      expect(rail(tabletLandscape), isFalse);
    });

    test('a short pane with no width to spare keeps the bar', () {
      expect(rail(const Size(kWideEnoughForRail - 1, 400)), isFalse);
    });

    test('vertical insets are not somewhere to put a rail', () {
      expect(
        rail(phonePortrait, const EdgeInsets.only(top: 200, bottom: 200)),
        isFalse,
      );
    });

    test('an inset paying for the rail decides which side it goes', () {
      expect(navigationRailOnRight(const EdgeInsets.only(right: 96)), isTrue);
      expect(navigationRailOnRight(const EdgeInsets.only(left: 96)), isFalse);
    });

    test('otherwise the rail sits on the leading edge', () {
      expect(navigationRailOnRight(EdgeInsets.zero), isFalse);
    });
  });
}
