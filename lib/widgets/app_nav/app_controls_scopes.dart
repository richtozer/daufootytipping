import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:flutter/widgets.dart';
import 'package:watch_it/watch_it.dart';

/// Offers the floating controls a screen's tabs for as long as it is mounted.
class AppNavTabsScope extends StatefulWidget {
  const AppNavTabsScope({
    super.key,
    required this.tabs,
    required this.child,
    this.viewModel,
  });

  final AppNavTabs tabs;
  final Widget child;

  /// Defaults to the registered [AppControlsViewModel].
  final AppControlsViewModel? viewModel;

  @override
  State<AppNavTabsScope> createState() => _AppNavTabsScopeState();
}

class _AppNavTabsScopeState extends State<AppNavTabsScope> {
  late final AppControlsViewModel _viewModel =
      widget.viewModel ?? di<AppControlsViewModel>();

  @override
  void initState() {
    super.initState();
    _viewModel.showTabs(this, widget.tabs);
  }

  @override
  void didUpdateWidget(AppNavTabsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _viewModel.showTabs(this, widget.tabs);
  }

  @override
  void dispose() {
    _viewModel.hideTabs(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Declares the actions the floating controls show beside Back while this page
/// is the one on top, such as Add on an admin list.
class AppPageActions extends StatefulWidget {
  const AppPageActions({
    super.key,
    required this.actions,
    required this.child,
    this.viewModel,
  });

  final List<AppGlassAction> actions;
  final Widget child;

  /// Defaults to the registered [AppControlsViewModel].
  final AppControlsViewModel? viewModel;

  @override
  State<AppPageActions> createState() => _AppPageActionsState();
}

class _AppPageActionsState extends State<AppPageActions> {
  late final AppControlsViewModel _viewModel =
      widget.viewModel ?? di<AppControlsViewModel>();
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _register();
  }

  @override
  void didUpdateWidget(AppPageActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  void _register() {
    final route = _route;
    if (route != null) {
      _viewModel.setPageActions(route, widget.actions);
    }
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null) {
      _viewModel.clearPageActions(route);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// How far from the end a scroll view may be and still count as at it.
const double kScrollEndSlack = 2;

/// Fades the floating controls away while a vertical scroll view below it rests
/// at its end, so the last rows can be read, and brings them back as soon as it
/// scrolls up again.
///
/// A scroll view too short to scroll never fades them.
class AppControlsFadeAtScrollEnd extends StatefulWidget {
  const AppControlsFadeAtScrollEnd({
    super.key,
    required this.child,
    this.viewModel,
  });

  final Widget child;

  /// Defaults to the registered [AppControlsViewModel].
  final AppControlsViewModel? viewModel;

  @override
  State<AppControlsFadeAtScrollEnd> createState() =>
      _AppControlsFadeAtScrollEndState();
}

class _AppControlsFadeAtScrollEndState
    extends State<AppControlsFadeAtScrollEnd> {
  late final AppControlsViewModel _viewModel =
      widget.viewModel ?? di<AppControlsViewModel>();
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  bool _onScroll(ScrollNotification notification) {
    final route = _route;
    if (route == null || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final metrics = notification.metrics;
    final atEnd =
        metrics.maxScrollExtent > 0 && metrics.extentAfter <= kScrollEndSlack;
    _viewModel.setControlsFaded(route, atEnd);
    return false;
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null) {
      _viewModel.setControlsFaded(route, false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: widget.child,
    );
  }
}
