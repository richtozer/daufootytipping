import 'dart:async';

import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:get_it/get_it.dart';

/// Registers the view models that every signed-in screen shares: the tippers
/// and the comps view model, each kept for the whole session.
class CoreViewModelRegistration {
  CoreViewModelRegistration(this._locator);

  final GetIt _locator;
  String? _activeCompKey;
  bool _registeredForSession = false;

  /// The comp the comps view model was last told is active, if any.
  String? get activeCompKey => _activeCompKey;

  /// Registers both view models once per session. When the active comp
  /// changes, the registered comps view model switches to it.
  ///
  /// Screens keep the view models they found, so replacing either while
  /// someone is signed in would leave those screens on the old tipper or comp.
  void register({
    required String activeCompKey,
    required TippersViewModel Function() createTippers,
    required DAUCompsViewModel Function() createDauComps,
  }) {
    if (!_registeredForSession ||
        !_locator.isRegistered<TippersViewModel>() ||
        !_locator.isRegistered<DAUCompsViewModel>()) {
      _registeredForSession = true;
      _activeCompKey = activeCompKey;
      _locator
        ..registerLazySingleton<TippersViewModel>(createTippers)
        ..registerLazySingleton<DAUCompsViewModel>(createDauComps);
      return;
    }
    if (_activeCompKey == activeCompKey) {
      return;
    }
    _activeCompKey = activeCompKey;
    unawaited(_locator<DAUCompsViewModel>().changeActiveComp(activeCompKey));
  }

  /// Makes the next [register] replace both view models, so whoever signs in
  /// next does not see the last user's tipper or comp state.
  void forget() {
    _activeCompKey = null;
    _registeredForSession = false;
  }
}
