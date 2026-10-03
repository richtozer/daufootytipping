import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_destination.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The tab destinations a screen has handed to the floating controls.
@immutable
class AppNavTabs {
  const AppNavTabs({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
}

/// What the floating controls are showing.
enum AppControlsMode {
  /// Nothing to offer, such as on a sign-in screen.
  none,

  /// The tab pill, on a screen that owns the tabs.
  tabs,

  /// Back, with any actions the page on top declared. The tab pill has
  /// morphed into this.
  back,
}

/// What the app's floating controls should show, decided by which screens are
/// on the route stack and what they have registered.
///
/// Screens register while they are mounted and the host reads the result, so
/// the controls live once above the Navigator and can animate between modes.
class AppControlsViewModel extends ChangeNotifier {
  AppNavTabs? _tabs;
  Object? _tabsOwner;
  List<Route<dynamic>> _pageRoutes = const [];
  final Map<Route<dynamic>, List<AppGlassAction>> _actionsByRoute = {};
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Page routes on the stack, home included, dialogs and sheets excluded.
  int get pageDepth => _pageRoutes.length;

  AppNavTabs? get tabs => _tabs;

  /// The mode the controls are in: Back on any pushed page, otherwise the tabs
  /// if a screen owns them.
  AppControlsMode get mode {
    if (pageDepth > 1) {
      return AppControlsMode.back;
    }
    return _tabs == null ? AppControlsMode.none : AppControlsMode.tabs;
  }

  /// Actions the page currently on top declared, in the order they show,
  /// ahead of Back.
  List<AppGlassAction> get pageActions {
    if (_pageRoutes.isEmpty) {
      return const [];
    }
    return _actionsByRoute[_pageRoutes.last] ?? const [];
  }

  /// Hands the tabs to the controls. [owner] identifies the screen so only it
  /// can take them back, which matters while one screen replaces another.
  void showTabs(Object owner, AppNavTabs tabs) {
    _tabsOwner = owner;
    _tabs = tabs;
    _notify();
  }

  void hideTabs(Object owner) {
    if (!identical(_tabsOwner, owner)) {
      return;
    }
    _tabsOwner = null;
    _tabs = null;
    _notify();
  }

  void setPageRoutes(List<Route<dynamic>> pageRoutes) {
    _pageRoutes = List.unmodifiable(pageRoutes);
    _actionsByRoute.removeWhere((route, _) => !_pageRoutes.contains(route));
    _notify();
  }

  void setPageActions(Route<dynamic> route, List<AppGlassAction> actions) {
    _actionsByRoute[route] = List.unmodifiable(actions);
    _notify();
  }

  void clearPageActions(Route<dynamic> route) {
    if (_actionsByRoute.remove(route) != null) {
      _notify();
    }
  }

  /// Screens register from initState and build, where listeners rebuilding
  /// the host would throw, so a change landing mid-frame is announced after it.
  void _notify() {
    if (_disposed) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
