import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:flutter/widgets.dart';

/// Tells [AppControlsViewModel] which pages are on the stack, so the floating
/// controls know whether to offer the tabs or Back.
///
/// Only opaque page routes count. A dialog or bottom sheet is not somewhere
/// Back should appear, even one built on a see-through page route.
class AppControlsObserver extends NavigatorObserver {
  AppControlsObserver(this._viewModel);

  final AppControlsViewModel _viewModel;
  final List<Route<dynamic>> _pages = [];

  /// Pops the page on top, as the floating Back does.
  Future<bool> goBack() async => await navigator?.maybePop() ?? false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPage(route)) {
      _pages.add(route);
      _publish();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pages.remove(route)) {
      _publish();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pages.remove(route)) {
      _publish();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (index >= 0) {
      _pages.removeAt(index);
    }
    if (newRoute != null && _isPage(newRoute)) {
      _pages.insert(index >= 0 ? index : _pages.length, newRoute);
    }
    _publish();
  }

  bool _isPage(Route<dynamic> route) => route is PageRoute && route.opaque;

  void _publish() => _viewModel.setPageRoutes(_pages);
}
