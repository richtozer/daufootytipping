import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';

class SelectionInitResult {
  final GamesViewModel gamesViewModel;
  final StatsViewModel statsViewModel;
  final TipsViewModel? tipsViewModel; // null in admin mode

  const SelectionInitResult({
    required this.gamesViewModel,
    required this.statsViewModel,
    required this.tipsViewModel,
  });
}

class SelectionInitCoordinator {
  const SelectionInitCoordinator();

  Future<SelectionInitResult> initializeUser({
    required DAUComp selectedComp,
    required GamesViewModel Function() createGamesViewModel,
    required Future<void> Function() awaitTippersReady,
    required StatsViewModel Function(DAUComp, GamesViewModel) createStatsViewModel,
    required TipsViewModel Function(GamesViewModel) createTipsViewModel,
  }) async {
    // Create Games first (matches previous behavior)
    final gamesVM = createGamesViewModel();

    // Await tippers init + linkage
    await awaitTippersReady();

    // Create Stats
    final statsVM = createStatsViewModel(selectedComp, gamesVM);

    // Create Tips for selected tipper
    final tipsVM = createTipsViewModel(gamesVM);

    return SelectionInitResult(
      gamesViewModel: gamesVM,
      statsViewModel: statsVM,
      tipsViewModel: tipsVM,
    );
  }

  Future<SelectionInitResult> initializeAdmin({
    required DAUComp selectedComp,
    required GamesViewModel Function() createGamesViewModel,
    required StatsViewModel Function(DAUComp, GamesViewModel) createStatsViewModel,
  }) async {
    final gamesVM = createGamesViewModel();
    final statsVM = createStatsViewModel(selectedComp, gamesVM);
    return SelectionInitResult(
      gamesViewModel: gamesVM,
      statsViewModel: statsVM,
      tipsViewModel: null,
    );
  }
}
