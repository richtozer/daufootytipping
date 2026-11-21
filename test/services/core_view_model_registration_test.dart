import 'package:daufootytipping/services/core_view_model_registration.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTippersViewModel extends Mock implements TippersViewModel {}

class _MockDauCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  late GetIt locator;
  late CoreViewModelRegistration registration;
  late int tippersCreated;
  late List<String> compsCreatedFor;

  void register(String activeCompKey) {
    registration.register(
      activeCompKey: activeCompKey,
      createTippers: () {
        tippersCreated++;
        return _MockTippersViewModel();
      },
      createDauComps: () {
        compsCreatedFor.add(activeCompKey);
        return _MockDauCompsViewModel();
      },
    );
  }

  setUp(() {
    locator = GetIt.asNewInstance()..allowReassignment = true;
    registration = CoreViewModelRegistration(locator);
    tippersCreated = 0;
    compsCreatedFor = <String>[];
  });

  test('a change of active comp replaces the comps view model but keeps the '
      'tippers view model, which holds the signed-in tipper', () {
    register('comp-2026');
    final TippersViewModel tippers = locator<TippersViewModel>();
    final DAUCompsViewModel comps2026 = locator<DAUCompsViewModel>();

    register('comp-2027');

    expect(locator<TippersViewModel>(), same(tippers));
    expect(tippersCreated, 1);
    expect(locator<DAUCompsViewModel>(), isNot(same(comps2026)));
    expect(compsCreatedFor, <String>['comp-2026', 'comp-2027']);
    expect(registration.activeCompKey, 'comp-2027');
  });

  test('the same active comp registers nothing new', () {
    register('comp-2026');
    final DAUCompsViewModel comps = locator<DAUCompsViewModel>();
    locator<TippersViewModel>();

    register('comp-2026');

    expect(locator<DAUCompsViewModel>(), same(comps));
    expect(compsCreatedFor, <String>['comp-2026']);
    expect(tippersCreated, 1);
  });

  test('after forget, the next sign-in gets fresh view models', () {
    register('comp-2026');
    final TippersViewModel tippers = locator<TippersViewModel>();
    final DAUCompsViewModel comps = locator<DAUCompsViewModel>();

    registration.forget();
    register('comp-2026');

    expect(locator<TippersViewModel>(), isNot(same(tippers)));
    expect(locator<DAUCompsViewModel>(), isNot(same(comps)));
  });
}
