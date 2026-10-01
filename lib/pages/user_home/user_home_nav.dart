import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The width a rail needs before its destinations stop being comfortably
/// tappable. Below this the bar stays where it is.
const double kNavigationRailWidth = 80;

/// Below this the pane is short enough that the bar's height is worth more
/// than the width a rail costs. A phone in landscape is about 390.
const double kShortPaneHeight = 500;

/// A rail has to come out of the content's width once no inset is paying for
/// it, so only a pane with width to spare trades.
const double kWideEnoughForRail = 600;

/// Whether the navigation belongs down the side rather than along the bottom.
///
/// Two ways to earn it. A horizontal display inset wide enough to hold the
/// rail -- a folded phone's camera strip -- is room the content cannot use
/// anyway, because nothing interactive may sit under it, so the move is free
/// and the bar's height simply comes back. Failing that, a short wide pane
/// pays for the rail out of its width, which is the thing it has: landscape
/// is short of height and the bar spends 60pt of it.
///
/// A pane that is merely narrow keeps the bar. A cramped rail would be worse
/// than the bar it replaced, and there is no spare width to take it from.
bool shouldUseNavigationRail({
  required Size size,
  required EdgeInsets displayPadding,
}) {
  if (math.max(displayPadding.left, displayPadding.right) >=
      kNavigationRailWidth) {
    return true;
  }
  return size.height < kShortPaneHeight && size.width >= kWideEnoughForRail;
}

/// Which side the rail goes. The wider inset claims it, since that edge is
/// already spent; failing that the leading edge, where a rail is looked for.
///
/// iOS reserves the same strip on both sides in landscape whichever edge the
/// Dynamic Island is on, so this lands on the leading edge there and the rail
/// keeps clear of that side regardless.
bool navigationRailOnRight(EdgeInsets displayPadding) =>
    displayPadding.right > displayPadding.left;

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
