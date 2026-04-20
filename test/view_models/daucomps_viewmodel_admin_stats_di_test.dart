import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/services/selection_init_coordinator.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockStatsViewModel extends Mock implements StatsViewModel {}

class FakeSelectionInitCoordinator extends SelectionInitCoordinator {
  const FakeSelectionInitCoordinator({
    required this.gamesViewModel,
    required this.statsViewModel,
  });

  final GamesViewModel gamesViewModel;
  final StatsViewModel statsViewModel;

  @override
  Future<SelectionInitResult> initializeAdmin({
    required DAUComp selectedComp,
    required GamesViewModel Function() createGamesViewModel,
    required StatsViewModel Function(DAUComp, GamesViewModel)
    createStatsViewModel,
  }) async {
    return SelectionInitResult(
      gamesViewModel: gamesViewModel,
      statsViewModel: statsViewModel,
      tipsViewModel: null,
    );
  }
}

void main() {
  late MockGamesViewModel adminGamesViewModel;
  late MockStatsViewModel globalStatsViewModel;
  late MockStatsViewModel adminStatsViewModel;

  setUp(() async {
    await di.reset();

    adminGamesViewModel = MockGamesViewModel();
    globalStatsViewModel = MockStatsViewModel();
    adminStatsViewModel = MockStatsViewModel();

    when(() => adminGamesViewModel.addListener(any())).thenAnswer((_) {});
    when(() => adminGamesViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => adminGamesViewModel.dispose()).thenAnswer((_) {});
    when(() => globalStatsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => globalStatsViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => adminStatsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => adminStatsViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => adminStatsViewModel.dispose()).thenAnswer((_) {});

    di.registerSingleton<StatsViewModel>(globalStatsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  test('admin mode does not replace the global stats view model singleton', () async {
    final vm = DAUCompsViewModel(
      null,
      true,
      skipInit: true,
      selectionInit: FakeSelectionInitCoordinator(
        gamesViewModel: adminGamesViewModel,
        statsViewModel: adminStatsViewModel,
      ),
    );
    di.registerSingleton<DAUCompsViewModel>(vm);

    final comp = DAUComp(
      dbkey: 'comp-2024',
      name: 'DAU Footy Tipping 2024',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );

    await vm.changeDisplayedDAUComp(comp, false);

    expect(identical(di<StatsViewModel>(), globalStatsViewModel), isTrue);
    expect(identical(vm.statsViewModel, adminStatsViewModel), isTrue);
  });
}
