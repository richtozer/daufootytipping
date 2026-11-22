import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:flutter/widgets.dart';

/// The width a right display inset needs to hold the side pill and a little
/// air either side, which is what lets it take the inset for free.
const double kSideControlsInsetWidth = kGlassSideThickness + 8;

/// Below this the pane is short enough that a bottom pill costs more than the
/// width a side pill takes. A phone in landscape is about 390.
const double kShortPaneHeight = 500;

/// A side pill comes out of the content's width once no inset is paying for
/// it, so only a pane with width to spare trades.
const double kWideEnoughForRail = 600;

/// Where the app's navigation controls sit.
enum AppNavPlacement {
  /// Along the bottom edge, in the bottom-right corner.
  bottom,

  /// Down the right edge, at the bottom, under the thumb.
  trailingEdge,
}

/// Decides from the shape of the space, never the platform, so the same rule
/// serves a phone, a folding phone and a browser window.
///
/// Two ways to earn the side. A right-hand display inset wide enough to hold
/// the pill -- a folded phone's camera strip -- is room the content cannot use
/// anyway, so the move is free and the bottom edge comes back to the content.
/// Failing that, a short wide pane pays for the pill out of its width, which
/// is the thing it has: landscape is short of height.
///
/// A pane that is merely narrow keeps the bottom pill. The side is always the
/// right, so the controls stay under the right thumb in every layout.
AppNavPlacement appNavPlacement({
  required Size size,
  required EdgeInsets displayPadding,
}) {
  if (displayPadding.right >= kSideControlsInsetWidth) {
    return AppNavPlacement.trailingEdge;
  }
  if (size.height < kShortPaneHeight && size.width >= kWideEnoughForRail) {
    return AppNavPlacement.trailingEdge;
  }
  return AppNavPlacement.bottom;
}

/// How far up from the bottom edge the side controls must sit to clear the
/// camera a folded Duo has in a corner of its outer display.
const double kCornerCameraClearance = 80;

/// The longer side over the shorter below which a short display is the
/// squarish outer display of a folded Duo, not a phone in landscape (about 2.2).
const double kFoldedDuoMaxAspect = 1.6;

/// The gap the side controls must keep from the bottom edge to stay clear of a
/// corner camera, or zero where the display has none.
///
/// iOS reports no region for that camera, so the display's shape stands in for
/// it. Where it is shorter than a tablet and squarer than any phone, the
/// controls go above the camera's corner, in line with it as Apple does.
double sideControlsBottomClearance({required Size size}) {
  final shortSide = size.shortestSide;
  if (shortSide >= kShortPaneHeight) {
    return 0;
  }
  return size.longestSide / shortSide < kFoldedDuoMaxAspect
      ? kCornerCameraClearance
      : 0;
}
