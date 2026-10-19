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
const double kGlassItemExtent = 50;

/// The square every tab icon is centred in, badge or not, so labels line up.
const double kGlassIconSlot = 30;

/// The size of a tab's icon, filling most of its slot.
const double kGlassIconSize = 28;

/// The most a tab's label grows with the system text size. Past this the tab,
/// whose height is fixed so the footprint stays small, could not hold it.
const double kGlassMaxLabelTextScale = 1.5;

/// The label's line height, tight so a larger text size still fits the tab.
const double kGlassLabelLineHeight = 1.1;

/// The gap between a tab's icon and its label.
const double kGlassIconLabelGap = 2;

/// The width of a tab in a horizontal pill.
const double kGlassHorizontalTabWidth = 80;

/// The width of a tab or round item in a pill running down the side.
const double kGlassSideItemWidth = 48;

/// How thick a glass control is across its short axis: the height of a
/// horizontal pill, the width of a vertical one.
const double kGlassHorizontalThickness = kGlassItemExtent + 2 * kGlassPadding;
const double kGlassSideThickness = kGlassSideItemWidth + 2 * kGlassPadding;

/// The label's size under an icon: a touch smaller down the side, where the
/// chip is slimmer and the longest label, PROFILE, still has to fit.
const double kGlassHorizontalLabelSize = 10;
const double kGlassSideLabelSize = 9;

/// Space between a label's letters, so TIPS reads as T I P S as in the
/// original design. Tight down the side, where the chip is too slim for it.
const double kGlassHorizontalLabelSpacing = 3;
const double kGlassSideLabelSpacing = 0.2;

/// How much the surface behind a glass control is blurred.
const double kGlassBlurSigma = 14;

/// The colours of the app's glass controls: frosted over the backdrop, on the
/// same surface colour as the panel cards, so the selection green on the chosen
/// item stands out from it.
///
/// Follows the platform brightness, as the rest of the app's custom surfaces
/// do, so the controls match the scheme the screens around them are in.
@immutable
class AppGlassStyle {
  const AppGlassStyle._({
    required this.fill,
    required this.shadow,
    required this.foreground,
    required this.selectedFill,
    required this.selectedForeground,
  });

  static final AppGlassStyle light = AppGlassStyle._(
    fill: kPanelLightColor,
    shadow: Color(0x3D142808),
    foreground: Color(0xFF14200C),
    // Deeper than the pale selection green, which is close to the pale surface it
    // sits on: the same green as the chosen chip on a tips card.
    selectedFill: Color(0xFF8BC34A),
    selectedForeground: kOnSelectionLightColor,
  );

  static final AppGlassStyle dark = AppGlassStyle._(
    fill: kPanelDarkColor,
    shadow: Color(0x80000000),
    foreground: Color(0xFFE8EFDF),
    selectedFill: kSelectionDarkColor,
    selectedForeground: kOnSelectionDarkColor,
  );

  factory AppGlassStyle.of(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark
      ? dark
      : light;

  final Color fill;
  final Color shadow;
  final Color foreground;
  final Color selectedFill;
  final Color selectedForeground;
}
