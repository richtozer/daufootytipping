import 'dart:math' as math;

import 'package:daufootytipping/widgets/app_under_controls_area.dart';
import 'package:flutter/widgets.dart';

/// A page's content, held at the bottom within thumb reach, that still scrolls
/// where a short display cannot fit it.
///
/// On a tab page the room the floating controls take along the bottom is left
/// as scroll padding, so the last row rests clear of them and every row can be
/// scrolled into view.
///
/// Under an [AppUnderControlsArea] the content scrolls under the controls
/// instead, with the end held clear of the device's own inset only. A short
/// list still sits above the controls, so none of it is covered, and a long one
/// runs beneath them until the controls fade at its end.
///
/// A plain scroll view leaves the column unbounded, which ignores the
/// alignment, so the content is held to the viewport height as a minimum.
class AppBottomAlignedScroll extends StatelessWidget {
  const AppBottomAlignedScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controlsRoom = MediaQuery.paddingOf(context).bottom;
    final scrollEnd = AppScrollEndPadding.maybeOf(context);
    return LayoutBuilder(
      builder: (context, viewport) => SingleChildScrollView(
        padding: EdgeInsets.only(bottom: scrollEnd ?? controlsRoom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, viewport.maxHeight - controlsRoom),
          ),
          child: Align(alignment: Alignment.bottomCenter, child: child),
        ),
      ),
    );
  }
}
