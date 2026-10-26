import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

/// Holds the view models of a user who has signed out until the screens that
/// were using them are gone, then disposes them, which cancels their database
/// subscriptions.
///
/// A view model is only disposed if the app has since registered a different
/// one in its place, so one still in use is never disposed.
class RetiredViewModels {
  RetiredViewModels(this._locator);

  final GetIt _locator;
  final List<_Retired> _retired = <_Retired>[];

  /// Remembers the registered [T] for disposal, if one has been created.
  void retire<T extends ChangeNotifier>() {
    if (!_locator.isRegistered<T>() ||
        !_locator.checkLazySingletonInstanceExists<T>()) {
      return;
    }
    final T instance = _locator<T>();
    if (_retired.any((retired) => identical(retired.instance, instance))) {
      return;
    }
    _retired.add(_Retired(instance, () => _isCurrent<T>(instance)));
  }

  /// Disposes every retired view model the app no longer has registered.
  void disposeRetired() {
    final List<_Retired> pending = List<_Retired>.of(_retired);
    _retired.clear();
    for (final _Retired retired in pending) {
      if (retired.isCurrent()) {
        continue;
      }
      retired.instance.dispose();
    }
  }

  bool _isCurrent<T extends ChangeNotifier>(T instance) =>
      _locator.isRegistered<T>() &&
      _locator.checkLazySingletonInstanceExists<T>() &&
      identical(_locator<T>(), instance);
}

class _Retired {
  _Retired(this.instance, this.isCurrent);

  final ChangeNotifier instance;
  final bool Function() isCurrent;
}
