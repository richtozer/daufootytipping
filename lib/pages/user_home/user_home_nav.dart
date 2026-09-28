import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The width a rail needs before its destinations stop being comfortably
/// tappable. Below this the bar stays where it is.
const double kNavigationRailWidth = 80;

/// Whether the navigation belongs down the side rather than along the bottom.
///
/// A horizontal display inset wide enough to hold the rail -- a folded phone's
/// camera strip -- is room the content cannot use anyway, because nothing
/// interactive may sit under it. Moving the navigation into it costs nothing
/// and hands the bar's height back to the content, which is what a short pane
/// is short of. A narrower inset is left alone: a cramped rail would be worse
/// than the bar it replaced.
bool shouldUseNavigationRail(EdgeInsets displayPadding) =>
    math.max(displayPadding.left, displayPadding.right) >= kNavigationRailWidth;

/// Which side the rail goes, following whichever inset is offering the room.
bool navigationRailOnRight(EdgeInsets displayPadding) =>
    displayPadding.right >= displayPadding.left;

/// A destination described once and rendered by either the bar or the rail,
/// which take different types for the same thing.
@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.shortLabel,
    required this.wideLabel,
    this.enabled = true,
  });

  final Widget icon;

  /// Used by the rail, and by the bar on a narrow display.
  final String shortLabel;

  /// The letter-spaced form the bar uses where there is room for it.
  final String wideLabel;

  final bool enabled;
}
