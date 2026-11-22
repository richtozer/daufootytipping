import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:flutter/widgets.dart';

/// Tells [AppControlsViewModel] which pages are on the stack, so the floating
/// controls know whether to offer the tabs or Back, and whether a dialog or
/// sheet is on top, so they can step aside for it.
///
/// Only opaque page routes count as pages. A dialog or bottom sheet is not
/// somewhere Back should appear, even one built on a see-through page route.
class AppControlsObserver extends NavigatorObserver {
  AppControlsObserver(this._viewModel);

  final AppControlsViewModel _viewModel;

  /// Every route on the stack, bottom first, pages and overlays alike.
  final List<Route<dynamic>> _routes = [];

  /// Pops the page on top, as the floating Back does.
  Future<bool> goBack() async => await navigator?.maybePop() ?? false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routes.remove(route)) {
      _publish();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routes.remove(route)) {
      _publish();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      _routes.removeAt(index);
    }
    if (newRoute != null) {
      _routes.insert(index >= 0 ? index : _routes.length, newRoute);
    }
    _publish();
  }

  bool _isPage(Route<dynamic> route) => route is PageRoute && route.opaque;

  void _publish() {
    _viewModel.setPageRoutes(_routes.where(_isPage).toList());
    _viewModel.setOverlayOnTop(_routes.isNotEmpty && !_isPage(_routes.last));
  }
}
