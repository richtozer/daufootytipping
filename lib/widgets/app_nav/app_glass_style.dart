import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';

/// The corner of a tab chip or a round item: the same as the tips game card.
const double kGlassItemRadius = kCardCornerRadius;

/// The corner of the glass around them, concentric with the items so the
/// padding between them is even all the way round.
const double kGlassOuterRadius = kGlassItemRadius + kGlassPadding;

/// Padding between the edge of a glass control and the items inside it.
const double kGlassPadding = 4;

/// The height of a tab, and of a round item inside a horizontal group.
const double kGlassItemExtent = 56;

/// The square every tab icon is centred in, badge or not, so labels line up.
const double kGlassIconSlot = 32;

/// The width of a tab in a horizontal pill.
const double kGlassHorizontalTabWidth = 80;

/// The width of a tab or round item in a pill running down the side.
const double kGlassSideItemWidth = 56;

/// How thick a glass control is across its short axis: the height of a
/// horizontal pill, the width of a vertical one.
const double kGlassHorizontalThickness = kGlassItemExtent + 2 * kGlassPadding;
const double kGlassSideThickness = kGlassSideItemWidth + 2 * kGlassPadding;

/// How much the surface behind a glass control is blurred.
const double kGlassBlurSigma = 14;

/// The colours of the app's glass controls: frosted over the backdrop, with
/// the same selection green the navigation has always used.
///
/// Follows the platform brightness, as the rest of the app's custom surfaces
/// do, so the controls match the scheme the screens around them are in.
@immutable
class AppGlassStyle {
  const AppGlassStyle._({
    required this.fill,
    required this.border,
    required this.shadow,
    required this.foreground,
    required this.selectedFill,
    required this.selectedForeground,
  });

  static const AppGlassStyle light = AppGlassStyle._(
    fill: Color(0x66FFFFFF),
    border: Color(0xCCFFFFFF),
    shadow: Color(0x3D142808),
    foreground: Color(0xFF14200C),
    selectedFill: Color(0xF2C5E1A5),
    selectedForeground: Color(0xFF14200C),
  );

  static const AppGlassStyle dark = AppGlassStyle._(
    fill: Color(0x70222C1C),
    border: Color(0x29FFFFFF),
    shadow: Color(0x80000000),
    foreground: Color(0xFFE8EFDF),
    selectedFill: Color(0xFF4E7A36),
    selectedForeground: Color(0xFFFFFFFF),
  );

  factory AppGlassStyle.of(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark
      ? dark
      : light;

  final Color fill;
  final Color border;
  final Color shadow;
  final Color foreground;
  final Color selectedFill;
  final Color selectedForeground;
}
