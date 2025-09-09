import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/services/selection_init_coordinator.dart';

class MockGamesVM extends Mock implements GamesViewModel {}
class MockStatsVM extends Mock implements StatsViewModel {}
class MockTipsVM extends Mock implements TipsViewModel {}

void main() {
  DAUComp comp() => DAUComp(
        dbkey: 'c',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: const [],
      );

  test('initializeUser runs in expected order and returns objects', () async {
    final c = const SelectionInitCoordinator();
    final steps = <String>[];
    final selected = comp();

    final res = await c.initializeUser(
      selectedComp: selected,
      createGamesViewModel: () {
        steps.add('games');
        return MockGamesVM();
      },
      awaitTippersReady: () async {
        steps.add('tippers');
      },
      createStatsViewModel: (s, g) {
        steps.add('stats');
        return MockStatsVM();
      },
      createTipsViewModel: (g) {
        steps.add('tips');
        return MockTipsVM();
      },
    );

    expect(steps, ['games', 'tippers', 'stats', 'tips']);
    expect(res.gamesViewModel, isA<GamesViewModel>());
    expect(res.statsViewModel, isA<StatsViewModel>());
    expect(res.tipsViewModel, isA<TipsViewModel>());
  });

  test('initializeAdmin returns tips as null', () async {
    final c = const SelectionInitCoordinator();
    final selected = comp();
    final res = await c.initializeAdmin(
      selectedComp: selected,
      createGamesViewModel: () => MockGamesVM(),
      createStatsViewModel: (s, g) => MockStatsVM(),
    );
    expect(res.tipsViewModel, isNull);
  });
}
