import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:get_it/get_it.dart';

/// Registers the view models that every signed-in screen shares: the tippers,
/// kept for the whole session, and the comps view model of the active comp.
class CoreViewModelRegistration {
  CoreViewModelRegistration(this._locator);

  final GetIt _locator;
  String? _activeCompKey;
  bool _tippersRegisteredForSession = false;

  /// The comp the registered comps view model was made for, if any.
  String? get activeCompKey => _activeCompKey;

  /// Registers a tippers view model once per session, and a comps view model
  /// whenever the active comp changes.
  ///
  /// The tippers view model holds the signed-in tipper, which the sign-in page
  /// sets once, so replacing it while someone is signed in would leave the
  /// screens with no tipper.
  void register({
    required String activeCompKey,
    required TippersViewModel Function() createTippers,
    required DAUCompsViewModel Function() createDauComps,
  }) {
    if (!_tippersRegisteredForSession ||
        !_locator.isRegistered<TippersViewModel>()) {
      _tippersRegisteredForSession = true;
      _locator.registerLazySingleton<TippersViewModel>(createTippers);
    }
    if (_activeCompKey != activeCompKey ||
        !_locator.isRegistered<DAUCompsViewModel>()) {
      _activeCompKey = activeCompKey;
      _locator.registerLazySingleton<DAUCompsViewModel>(createDauComps);
    }
  }

  /// Makes the next [register] replace both view models, so whoever signs in
  /// next does not see the last user's tipper or comp state.
  void forget() {
    _activeCompKey = null;
    _tippersRegisteredForSession = false;
  }
}
