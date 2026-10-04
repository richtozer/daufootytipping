import 'package:daufootytipping/widgets/app_nav/app_controls_scopes.dart';
import 'package:flutter/material.dart';

/// How far the end of scrolling content is held clear of the bottom edge: the
/// device's own inset and no more, so it can scroll under the floating controls
/// instead of stopping above them.
class AppScrollEndPadding extends InheritedWidget {
  const AppScrollEndPadding({
    super.key,
    required this.padding,
    required super.child,
  });

  final double padding;

  static double of(BuildContext context) => maybeOf(context) ?? 0;

  /// Null where nothing above scrolls under the controls, which is how a scroll
  /// view tells it must leave room for them instead.
  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppScrollEndPadding>()
      ?.padding;

  @override
  bool updateShouldNotify(AppScrollEndPadding oldWidget) =>
      oldWidget.padding != padding;
}

/// The body of a page whose scrolling content runs under the floating controls.
///
/// A SafeArea that leaves the bottom alone, since the controls' room is the
/// content's to scroll beneath. The end of the content keeps clear of the
/// device's own bottom inset, and the controls fade away once it is scrolled to
/// its end so the last rows can be read, then return as it scrolls back up.
class AppUnderControlsArea extends StatelessWidget {
  const AppUnderControlsArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: AppScrollEndPadding(
        padding: MediaQuery.viewPaddingOf(context).bottom,
        child: AppControlsFadeAtScrollEnd(child: child),
      ),
    );
  }
}
