import 'package:daufootytipping/services/retired_view_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _TipperState extends ChangeNotifier {
  int disposals = 0;
  bool get disposed => disposals > 0;

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _CompState extends ChangeNotifier {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  late GetIt locator;
  late RetiredViewModels retired;

  setUp(() {
    locator = GetIt.asNewInstance()..allowReassignment = true;
    retired = RetiredViewModels(locator);
  });

  test('disposes the signed-out user\'s view models once replaced', () {
    locator
      ..registerLazySingleton<_TipperState>(_TipperState.new)
      ..registerLazySingleton<_CompState>(_CompState.new);
    final _TipperState oldTipper = locator<_TipperState>();
    final _CompState oldComp = locator<_CompState>();

    retired
      ..retire<_TipperState>()
      ..retire<_CompState>();
    locator
      ..registerLazySingleton<_TipperState>(_TipperState.new)
      ..registerLazySingleton<_CompState>(_CompState.new);
    retired.disposeRetired();

    expect(oldTipper.disposed, isTrue);
    expect(oldComp.disposed, isTrue);
    expect(locator<_TipperState>().disposed, isFalse);
  });

  test('keeps a view model the app still has registered', () {
    locator.registerLazySingleton<_TipperState>(_TipperState.new);
    final _TipperState tipper = locator<_TipperState>();

    retired.retire<_TipperState>();
    retired.disposeRetired();

    expect(tipper.disposed, isFalse);
  });

  test('retires nothing for a view model that was never created', () {
    int created = 0;
    locator.registerLazySingleton<_TipperState>(() {
      created++;
      return _TipperState();
    });

    retired.retire<_TipperState>();
    retired.disposeRetired();

    expect(created, 0);
  });

  test('disposes once when signed out twice before it is released', () {
    locator.registerLazySingleton<_TipperState>(_TipperState.new);
    final _TipperState tipper = locator<_TipperState>();

    retired
      ..retire<_TipperState>()
      ..retire<_TipperState>();
    locator.registerLazySingleton<_TipperState>(_TipperState.new);
    retired
      ..disposeRetired()
      ..disposeRetired();

    expect(tipper.disposals, 1);
  });
}
