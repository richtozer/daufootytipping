import 'dart:math' as math;

import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_observer.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_pill.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_placement.dart';
import 'package:flutter/material.dart';

/// Names the Back control for screen readers and the long-press tooltip.
const String kBackActionLabel = 'Back';

/// Gap between the controls and the edge of the display, or of its inset.
const double kControlsEdgeMargin = 12;

/// How close the side controls sit to the display edge in an inset too slim to
/// centre them in.
const double kControlsInsetEdgeMargin = 4;

/// The gap kept between the side controls and the content beside them.
const double kControlsContentGap = 8;

const Duration _morphDuration = Duration(milliseconds: 260);

/// How long the controls take to fade out of the way, and back.
const Duration _fadeDuration = Duration(milliseconds: 220);

/// Floats the app's navigation controls over the Navigator. The tab pill is
/// centred along the bottom of a tall display; Back and page actions stay in
/// the bottom-right corner. On a short wide display everything runs down the
/// right edge.
///
/// Hosted once above the Navigator so the tab pill can morph into Back as a
/// page is pushed and back again as it is popped, rather than each page
/// drawing its own. The controls run along the bottom or down the right edge
/// as [appNavPlacement] decides, and the content is told how much room they
/// take so nothing sits under them.
class AppControlsHost extends StatelessWidget {
  const AppControlsHost({
    super.key,
    required this.viewModel,
    required this.observer,
    required this.child,
  });

  final AppControlsViewModel viewModel;
  final AppControlsObserver observer;

  /// The Navigator.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final placement = appNavPlacement(
          size: media.size,
          displayPadding: media.padding,
        );
        final axis = placement == AppNavPlacement.bottom
            ? Axis.horizontal
            : Axis.vertical;
        final mode = viewModel.mode;
        final keyboardUp = media.viewInsets.bottom > 0;
        // A page with actions of its own, such as Save on a form, keeps them in
        // reach above the keyboard. Otherwise the controls step aside for it.
        final aboveKeyboard =
            keyboardUp &&
            mode == AppControlsMode.back &&
            viewModel.pageActions.isNotEmpty;
        return Stack(
          children: [
            Positioned.fill(
              child: MediaQuery(
                data: media.copyWith(
                  padding: _contentPadding(
                    media.padding,
                    media.size,
                    axis,
                    mode,
                  ),
                ),
                child: child,
              ),
            ),
            Positioned(
              // Along the bottom the tab pill is centred between the side
              // insets; Back and the page's actions stay in the right-hand
              // corner. Down the side everything hugs the right edge, where the
              // thumb is.
              left: axis == Axis.horizontal
                  ? media.padding.left + kControlsEdgeMargin
                  : null,
              right: axis == Axis.horizontal
                  ? media.padding.right + kControlsEdgeMargin
                  : _rightOffset(media.padding),
              bottom: aboveKeyboard
                  ? media.viewInsets.bottom + kControlsEdgeMargin
                  : _bottomOffset(media.padding, media.size, axis),
              child: _Controls(
                viewModel: viewModel,
                observer: observer,
                axis: axis,
                mode: keyboardUp && !aboveKeyboard
                    ? AppControlsMode.none
                    : mode,
                alignment:
                    axis == Axis.horizontal && mode == AppControlsMode.tabs
                    ? Alignment.bottomCenter
                    : Alignment.bottomRight,
                // Only along the bottom, where the content runs under them.
                faded: axis == Axis.horizontal && viewModel.controlsFaded,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The room the content must leave so the controls never cover it.
  EdgeInsets _contentPadding(
    EdgeInsets padding,
    Size size,
    Axis axis,
    AppControlsMode mode,
  ) {
    if (mode == AppControlsMode.none) {
      return padding;
    }
    if (axis == Axis.horizontal) {
      return padding.copyWith(
        bottom:
            _bottomOffset(padding, size, axis) +
            kGlassHorizontalThickness +
            kControlsEdgeMargin,
      );
    }
    // From the same offset the controls are placed at, so the room reserved is
    // exactly the room they take whatever the inset is.
    final sideRoom =
        _rightOffset(padding) + kGlassSideThickness + kControlsContentGap;
    return padding.copyWith(
      right: padding.right > sideRoom ? padding.right : sideRoom,
    );
  }

  /// Clear of the home indicator where there is one, and of a corner camera
  /// when the controls run down the side.
  double _bottomOffset(EdgeInsets padding, Size size, Axis axis) {
    final clearOfIndicator = padding.bottom > 0
        ? padding.bottom + 4
        : kControlsEdgeMargin;
    if (axis == Axis.horizontal) {
      return clearOfIndicator;
    }
    return math.max(clearOfIndicator, sideControlsBottomClearance(size: size));
  }

  /// Where the controls sit from the right edge. Centred in an inset wide
  /// enough to hold them, so they take room the content could not use anyway.
  /// In a slimmer inset they sit just inside the display edge, over it, and the
  /// content is told to leave room for them. With no inset they float clear of
  /// the edge.
  double _rightOffset(EdgeInsets padding) {
    if (padding.right >= kSideControlsInsetWidth) {
      return (padding.right - kGlassSideThickness) / 2;
    }
    return padding.right > 0 ? kControlsInsetEdgeMargin : kControlsEdgeMargin;
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.viewModel,
    required this.observer,
    required this.axis,
    required this.mode,
    required this.alignment,
    required this.faded,
  });

  final AppControlsViewModel viewModel;
  final AppControlsObserver observer;
  final Axis axis;
  final AppControlsMode mode;

  /// Where the controls sit in the room the host gives them. The tab pill is
  /// centred along the bottom and everything else is in the right-hand corner,
  /// so the controls slide across as the pill becomes Back.
  final Alignment alignment;

  /// Fading out, out of the way of the last rows of a long table.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: faded,
      child: ExcludeSemantics(
        excluding: faded,
        child: AnimatedOpacity(
          opacity: faded ? 0 : 1,
          duration: _fadeDuration,
          curve: Curves.easeInOut,
          child: AnimatedAlign(
            alignment: alignment,
            duration: _morphDuration,
            curve: Curves.easeOutCubic,
            child: AnimatedSize(
              duration: _morphDuration,
              curve: Curves.easeOutCubic,
              alignment: alignment,
              child: AnimatedSwitcher(
                duration: _morphDuration,
                layoutBuilder: (current, previous) => Stack(
                  alignment: alignment,
                  children: [...previous, ?current],
                ),
                child: _content(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (mode) {
      case AppControlsMode.none:
        return const SizedBox.shrink(key: ValueKey('none'));
      case AppControlsMode.tabs:
        final tabs = viewModel.tabs;
        if (tabs == null) {
          return const SizedBox.shrink(key: ValueKey('none'));
        }
        return AppGlassPill(
          key: const ValueKey('tabs'),
          destinations: tabs.destinations,
          selectedIndex: tabs.selectedIndex,
          onSelected: tabs.onSelected,
          axis: axis,
        );
      case AppControlsMode.back:
        final back = AppGlassAction(
          icon: Icons.arrow_back,
          label: kBackActionLabel,
          onPressed: observer.goBack,
        );
        final pageActions = viewModel.pageActions;
        if (pageActions.isEmpty) {
          return AppGlassButton(
            key: const ValueKey('back'),
            action: back,
            size: axis == Axis.horizontal
                ? kGlassHorizontalThickness
                : kGlassSideThickness,
          );
        }
        return AppGlassGroup(
          key: const ValueKey('back-group'),
          actions: [...pageActions, back],
          axis: axis,
        );
    }
  }
}
