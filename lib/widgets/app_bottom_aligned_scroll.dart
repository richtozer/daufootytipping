import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A tab page's content, held at the bottom within thumb reach, that still
/// scrolls where a short display cannot fit it.
///
/// Leaves the room the floating controls take along the bottom as scroll
/// padding, so the last row rests clear of them and every row can be scrolled
/// into view. A plain scroll view leaves the column unbounded, which ignores
/// the alignment, so the content is held to the viewport height as a minimum.
///
/// Any scrolling page in the home tabs that is not a ListView, which reads the
/// controls' room from MediaQuery itself, should use this or apply the same
/// padding.
class AppBottomAlignedScroll extends StatelessWidget {
  const AppBottomAlignedScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controlsRoom = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, viewport) => SingleChildScrollView(
        padding: EdgeInsets.only(bottom: controlsRoom),
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
