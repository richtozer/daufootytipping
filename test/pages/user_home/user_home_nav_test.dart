import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;

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

    const landscape = Size(844, 390);
    DisplayFeature cutout(Rect bounds) => DisplayFeature(
      bounds: bounds,
      type: DisplayFeatureType.cutout,
      state: DisplayFeatureState.unknown,
    );
    final islandRight = cutout(const Rect.fromLTRB(807, 150, 844, 240));
    final islandLeft = cutout(const Rect.fromLTRB(0, 150, 37, 240));

    bool onRight(List<DisplayFeature> f, EdgeInsets p) =>
        navigationRailOnRight(features: f, size: landscape, displayPadding: p);
    double inset(List<DisplayFeature> f, EdgeInsets p, bool right) =>
        navigationRailInset(
          features: f,
          size: landscape,
          displayPadding: p,
          onRight: right,
        );

    test('the edge with something in the way claims the rail', () {
      expect(onRight([islandRight], EdgeInsets.zero), isTrue);
      expect(onRight([islandLeft], EdgeInsets.zero), isFalse);
    });

    test('a cutout outranks the far edge reporting a wider inset', () {
      // iOS allows for a rounded corner on the edge the island is nowhere
      // near, and can report it as the larger of the two. The island is
      // what the rail should be following.
      expect(
        onRight([islandRight], const EdgeInsets.only(left: 59, right: 37)),
        isTrue,
      );
    });

    test('the rail clears the cutout, not the whole edge', () {
      expect(inset([islandRight], const EdgeInsets.only(right: 59), true), 37);
      // Nothing on the leading edge, so its inset was never an obstruction.
      expect(inset([islandRight], const EdgeInsets.only(left: 59), false), 0);
    });

    test('with no features reported it falls back to the edge insets', () {
      expect(onRight([], const EdgeInsets.only(right: 96)), isTrue);
      expect(onRight([], const EdgeInsets.only(left: 96)), isFalse);
      expect(onRight([], EdgeInsets.zero), isFalse);
      expect(inset([], const EdgeInsets.only(right: 59), true), 59);
      expect(inset([], const EdgeInsets.only(left: 59), false), 59);
    });
  });
}
