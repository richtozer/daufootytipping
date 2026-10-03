import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_host.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_observer.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

/// Registers a fresh [AppControlsViewModel] for pages that hand their actions
/// to the floating controls, as main.dart does for the real app.
AppControlsViewModel registerAppControlsViewModel() {
  final viewModel = AppControlsViewModel();
  di.registerSingleton<AppControlsViewModel>(viewModel);
  return viewModel;
}

/// The app as main.dart builds it, with the floating controls above the
/// Navigator, so a test can tap Back or a page's actions.
Widget appWithControls(AppControlsViewModel viewModel, {required Widget home}) {
  final observer = AppControlsObserver(viewModel);
  return MaterialApp(
    navigatorObservers: [observer],
    builder: (context, navigator) => AppControlsHost(
      viewModel: viewModel,
      observer: observer,
      child: navigator!,
    ),
    home: home,
  );
}
