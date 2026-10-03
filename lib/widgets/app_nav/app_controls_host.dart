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

const Duration _morphDuration = Duration(milliseconds: 260);

/// Floats the app's navigation controls over the Navigator, bottom right.
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
              right: _rightOffset(media.padding, axis),
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
    final sideRoom = kGlassSideThickness + 2 * kControlsEdgeMargin;
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

  /// Centred in a right inset wide enough to hold the controls, so they sit in
  /// room the content could not use anyway.
  double _rightOffset(EdgeInsets padding, Axis axis) {
    if (axis == Axis.vertical && padding.right >= kSideControlsInsetWidth) {
      return (padding.right - kGlassSideThickness) / 2;
    }
    return padding.right + kControlsEdgeMargin;
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.viewModel,
    required this.observer,
    required this.axis,
    required this.mode,
  });

  final AppControlsViewModel viewModel;
  final AppControlsObserver observer;
  final Axis axis;
  final AppControlsMode mode;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _morphDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomRight,
      child: AnimatedSwitcher(
        duration: _morphDuration,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomRight,
          children: [...previous, ?current],
        ),
        child: _content(),
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
