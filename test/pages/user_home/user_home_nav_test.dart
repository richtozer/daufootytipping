import 'package:daufootytipping/pages/user_home/user_home_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Navigation placement', () {
    test('an inset wide enough to hold the rail earns one', () {
      expect(
        shouldUseNavigationRail(
          const EdgeInsets.only(right: kNavigationRailWidth),
        ),
        isTrue,
      );
      expect(
        shouldUseNavigationRail(
          const EdgeInsets.only(left: kNavigationRailWidth + 20),
        ),
        isTrue,
      );
    });

    test('a narrower inset keeps the bar rather than cramping the rail', () {
      expect(
        shouldUseNavigationRail(
          const EdgeInsets.only(right: kNavigationRailWidth - 1),
        ),
        isFalse,
      );
      expect(shouldUseNavigationRail(EdgeInsets.zero), isFalse);
    });

    test('vertical insets are not somewhere to put a rail', () {
      expect(
        shouldUseNavigationRail(const EdgeInsets.only(top: 200, bottom: 200)),
        isFalse,
      );
    });

    test('the rail follows whichever inset offers the room', () {
      expect(navigationRailOnRight(const EdgeInsets.only(right: 96)), isTrue);
      expect(navigationRailOnRight(const EdgeInsets.only(left: 96)), isFalse);
    });
  });
}
