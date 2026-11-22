import 'package:daufootytipping/pages/user_auth/auth_fade_route.dart';
import 'package:flutter/widgets.dart';

/// Takes the app back to its first screen, as after signing out: every route is
/// removed and the root page is shown again, cross-faded in.
///
/// The app itself stays. Pushing a second app as a route would leave the first
/// one running around it, with its own connection banner, floating controls and
/// lifecycle observers, so each would show or happen twice.
class AppRootNavigator {
  AppRootNavigator({
    required this.navigatorKey,
    required WidgetBuilder rootBuilder,
    VoidCallback? onReturn,
    VoidCallback? onOldRoutesGone,
  }) : _rootBuilder = rootBuilder,
       _onReturn = onReturn,
       _onOldRoutesGone = onOldRoutesGone;

  /// The key of the app's one Navigator.
  final GlobalKey<NavigatorState> navigatorKey;

  final WidgetBuilder _rootBuilder;

  /// Runs before the routes are cleared, so the app can let go of state that
  /// belonged to the signed-out user before the root page is built.
  final VoidCallback? _onReturn;

  /// Runs once the old routes have faded out and been disposed, so what they
  /// were still drawing from while fading out can be released safely.
  final VoidCallback? _onOldRoutesGone;

  void returnToRoot() {
    _onReturn?.call();
    final NavigatorState? navigator = navigatorKey.currentState;
    if (navigator == null) {
      _onOldRoutesGone?.call();
      return;
    }
    final PageRouteBuilder<void> rootRoute = authFadeRoute<void>(_rootBuilder);
    navigator.pushAndRemoveUntil(rootRoute, (Route<dynamic> route) => false);

    final Animation<double>? animation = rootRoute.animation;
    if (animation == null) {
      _releaseAfterNextFrame();
      return;
    }

    // Until the next frame the route's animation stands in as already complete,
    // so it is the change to complete that is waited for, not the status now.
    bool released = false;
    late final AnimationStatusListener onStatus;
    void release() {
      if (released) {
        return;
      }
      released = true;
      animation.removeStatusListener(onStatus);
      _releaseAfterNextFrame();
    }

    onStatus = (AnimationStatus status) {
      if (status.isCompleted) {
        release();
      }
    };
    animation.addStatusListener(onStatus);
    // A route that does not animate never reports a change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (animation.isCompleted) {
        release();
      }
    });
  }

  /// The removed routes are disposed in the frame after the new one finishes
  /// arriving, so the release waits for that frame.
  void _releaseAfterNextFrame() {
    final VoidCallback? release = _onOldRoutesGone;
    if (release == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => release());
    WidgetsBinding.instance.scheduleFrame();
  }
}
