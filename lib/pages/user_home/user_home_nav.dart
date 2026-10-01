import 'dart:math' as math;
import 'dart:ui' show DisplayFeature;

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

/// How far a cutout or hinge on one edge actually reaches in from it.
///
/// An edge inset reserves the whole edge for an obstruction that usually
/// occupies a fraction of it, and reports one on edges a Dynamic Island is
/// nowhere near -- a rounded corner earns the same allowance as a camera.
/// A display feature carries its real bounds, so the rail can be held off by
/// what is genuinely in the way and no more.
double displayFeatureInset({
  required List<DisplayFeature> features,
  required Size size,
  required bool fromRight,
}) {
  var inset = 0.0;
  for (final feature in features) {
    final bounds = feature.bounds;
    if (fromRight) {
      if (bounds.right >= size.width - 0.5) {
        inset = math.max(inset, size.width - bounds.left);
      }
    } else if (bounds.left <= 0.5) {
      inset = math.max(inset, bounds.right);
    }
  }
  return inset;
}

/// How far to hold the rail off the edge it sits against.
///
/// Falls back to the edge inset where the display reports no features at all,
/// rather than sitting the destinations under an obstruction it cannot see.
double navigationRailInset({
  required List<DisplayFeature> features,
  required Size size,
  required EdgeInsets displayPadding,
  required bool onRight,
}) {
  if (features.isEmpty) {
    return onRight ? displayPadding.right : displayPadding.left;
  }
  return displayFeatureInset(
    features: features,
    size: size,
    fromRight: onRight,
  );
}

/// Which side the rail goes. The edge with something actually in the way
/// claims it, since that edge is already spent; failing that the wider inset,
/// and failing that the leading edge, where a rail is looked for.
bool navigationRailOnRight({
  required List<DisplayFeature> features,
  required Size size,
  required EdgeInsets displayPadding,
}) {
  final left = displayFeatureInset(
    features: features,
    size: size,
    fromRight: false,
  );
  final right = displayFeatureInset(
    features: features,
    size: size,
    fromRight: true,
  );
  if (left != right) return right > left;
  return displayPadding.right > displayPadding.left;
}

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
