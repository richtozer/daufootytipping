import 'dart:developer'; // For log()

import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring_modal.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_submit.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart'; // Added import
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class GameListItem extends StatefulWidget {
  const GameListItem({
    super.key,
    required this.layout,
    required this.game,
    required this.currentTipper,
    required this.currentDAUComp,
    required this.allTipsViewModel,
    required this.isPercentStatsPage,
    this.gameTipViewModel, // Optional for testing
  });

  final TipsCardLayout layout;
  final Game game;
  final Tipper currentTipper;
  final DAUComp currentDAUComp;
  final TipsViewModel allTipsViewModel;
  final bool isPercentStatsPage;
  final GameTipViewModel? gameTipViewModel; // Optional for testing

  @override
  State<GameListItem> createState() => _GameListItemState();
}

class _GameListItemState extends State<GameListItem> {
  static const String _loadingRankLabel = '--';
  static const String _noRankLabel = '';

  GameTipViewModel? _ownedGameTipsViewModel;

  /// Remembered by identity, not index: the result panel is inserted
  /// ahead of the others once a game starts.
  TipsPanel? _activePanel;
  GameTipViewModel get gameTipsViewModel =>
      widget.gameTipViewModel ?? _ownedGameTipsViewModel!;

  // New state variables for ladder ranks
  String? _homeOrdinalRankLabel;
  String? _awayOrdinalRankLabel;
  bool _isLoadingLadderRank = false;
  int _ladderRequestVersion = 0;
  late final ValueListenable<int> _leagueLadderRevision;

  @override
  void initState() {
    super.initState();
    _leagueLadderRevision = di<DAUCompsViewModel>().leagueLadderRevision;
    _leagueLadderRevision.addListener(_leagueLadderUpdated);
    _syncGameTipViewModel();
    _scheduleLadderRankFetch();
  }

  void _leagueLadderUpdated() {
    _resetLadderRanks();
    _scheduleLadderRankFetch();
  }

  @override
  void didUpdateWidget(covariant GameListItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool compChanged = widget.currentDAUComp != oldWidget.currentDAUComp;
    final bool gameChanged = widget.game.dbkey != oldWidget.game.dbkey;
    final bool tipperChanged = widget.currentTipper != oldWidget.currentTipper;
    final bool tipsViewModelChanged =
        widget.allTipsViewModel != oldWidget.allTipsViewModel;
    final bool injectedViewModelChanged =
        widget.gameTipViewModel != oldWidget.gameTipViewModel;

    if (compChanged ||
        gameChanged ||
        tipperChanged ||
        tipsViewModelChanged ||
        injectedViewModelChanged) {
      _syncGameTipViewModel(
        recreateOwned:
            compChanged ||
            gameChanged ||
            tipperChanged ||
            tipsViewModelChanged ||
            injectedViewModelChanged,
      );
    }

    if (compChanged || gameChanged || injectedViewModelChanged) {
      _resetLadderRanks();
      _scheduleLadderRankFetch();
    }
  }

  Future<void> _fetchAndSetLadderRanks() async {
    if (!mounted) return;
    final int requestVersion = ++_ladderRequestVersion;
    setState(() {
      _isLoadingLadderRank = true;
    });

    try {
      final calculatedLadder = await di<DAUCompsViewModel>()
          .getOrCalculateLeagueLadder(gameTipsViewModel.game.league);

      String calculatedHomeLabel = _noRankLabel;
      String calculatedAwayLabel = _noRankLabel;

      if (calculatedLadder != null) {
        final homeIdx = calculatedLadder.teams.indexWhere(
          (t) => t.dbkey == gameTipsViewModel.game.homeTeam.dbkey,
        );
        final homeRank = (homeIdx == -1) ? null : homeIdx + 1;
        calculatedHomeLabel = homeRank != null
            ? LeagueLadder.ordinal(homeRank)
            : _noRankLabel;

        final awayIdx = calculatedLadder.teams.indexWhere(
          (t) => t.dbkey == gameTipsViewModel.game.awayTeam.dbkey,
        );
        final awayRank = (awayIdx == -1) ? null : awayIdx + 1;
        calculatedAwayLabel = awayRank != null
            ? LeagueLadder.ordinal(awayRank)
            : _noRankLabel;
      }

      if (!mounted || requestVersion != _ladderRequestVersion) return;
      setState(() {
        _homeOrdinalRankLabel = calculatedHomeLabel;
        _awayOrdinalRankLabel = calculatedAwayLabel;
        _isLoadingLadderRank = false;
      });
    } catch (e) {
      log('Error fetching and setting ladder ranks: $e');
      if (!mounted || requestVersion != _ladderRequestVersion) return;
      setState(() {
        _homeOrdinalRankLabel = 'N/A'; // Error indicator
        _awayOrdinalRankLabel = 'N/A'; // Error indicator
        _isLoadingLadderRank = false;
      });
    }
  }

  void _syncGameTipViewModel({bool recreateOwned = false}) {
    if (widget.gameTipViewModel != null) {
      _disposeOwnedGameTipViewModel();
      return;
    }

    if (_ownedGameTipsViewModel == null || recreateOwned) {
      _disposeOwnedGameTipViewModel();
      _ownedGameTipsViewModel = GameTipViewModel(
        widget.currentTipper,
        widget.currentDAUComp,
        widget.game,
        widget.allTipsViewModel,
      );
    }
  }

  void _scheduleLadderRankFetch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _homeOrdinalRankLabel == null &&
          _awayOrdinalRankLabel == null &&
          !_isLoadingLadderRank) {
        _fetchAndSetLadderRanks();
      }
    });
  }

  void _resetLadderRanks() {
    _ladderRequestVersion++;
    if (!mounted) {
      _homeOrdinalRankLabel = null;
      _awayOrdinalRankLabel = null;
      _isLoadingLadderRank = false;
      return;
    }
    setState(() {
      _homeOrdinalRankLabel = null;
      _awayOrdinalRankLabel = null;
      _isLoadingLadderRank = false;
    });
  }

  void _disposeOwnedGameTipViewModel() {
    _ownedGameTipsViewModel?.dispose();
    _ownedGameTipsViewModel = null;
  }

  @override
  void dispose() {
    _ladderRequestVersion++;
    _leagueLadderRevision.removeListener(_leagueLadderUpdated);
    _disposeOwnedGameTipViewModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameTipViewModel>.value(
      value: gameTipsViewModel,
      child: Consumer<GameTipViewModel>(
        builder: (context, gameTipsViewModelConsumer, child) {
          if (!widget.isPercentStatsPage) {
            return _card(context, gameTipsViewModelConsumer);
          }
          return Selector<
            StatsViewModel?,
            ({
              StatsViewModel? viewModel,
              GameStatsEntry? entry,
              GameStatsLoadState loadState,
            })
          >(
            selector: (_, statsViewModel) {
              final game = gameTipsViewModelConsumer.game;
              return (
                viewModel: statsViewModel,
                entry: statsViewModel?.gameStatsEntryFor(game),
                loadState:
                    statsViewModel?.gameStatsLoadStateFor(game) ??
                    GameStatsLoadState.notRequested,
              );
            },
            builder: (context, statsSelection, child) => _PercentStatsRequest(
              gameTipViewModel: gameTipsViewModelConsumer,
              statsViewModel: statsSelection.viewModel,
              gameStatsEntry: statsSelection.entry,
              builder: (entry, loading) => _card(
                context,
                gameTipsViewModelConsumer,
                gameStatsEntry: entry,
                percentStatsLoading: loading,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(
    BuildContext context,
    GameTipViewModel gameTipsViewModelConsumer, {
    GameStatsEntry? gameStatsEntry,
    bool percentStatsLoading = false,
  }) {
    final String displayHomeRank = _isLoadingLadderRank
        ? _loadingRankLabel
        : (_homeOrdinalRankLabel ?? _noRankLabel);
    final String displayAwayRank = _isLoadingLadderRank
        ? _loadingRankLabel
        : (_awayOrdinalRankLabel ?? _noRankLabel);

    final data = tipsCardDisplayFor(
      gameTipViewModel: gameTipsViewModelConsumer,
      homeRank: displayHomeRank,
      awayRank: displayAwayRank,
      gameStatsEntry: gameStatsEntry,
      percentStatsLoading: percentStatsLoading,
      // Permission is checked when a tip is submitted, as it always has been:
      // the buttons stay live and explain themselves rather than going flat.
      canTip: true,
    );
    _recordGamePresentation(gameTipsViewModelConsumer.game, data.status.name);

    final panels = widget.isPercentStatsPage
        ? const [TipsPanel.percentages]
        : [
            if (data.hasResult) TipsPanel.result,
            TipsPanel.tips,
            TipsPanel.info,
          ];
    final active = _activePanel != null && panels.contains(_activePanel)
        ? _activePanel!
        : panels.first;

    return AdaptiveTipsCard(
      data: data,
      layout: widget.layout,
      percentStats: widget.isPercentStatsPage,
      activePanel: active,
      onPanelChanged: (panel) => _activePanel = panel,
      onTip: widget.isPercentStatsPage
          ? null
          : (option) => submitTip(context, gameTipsViewModelConsumer, option),
      onMatchup: () => _openMatchup(context, gameTipsViewModelConsumer),
    );
  }

  void _openMatchup(
    BuildContext context,
    GameTipViewModel gameTipsViewModelConsumer,
  ) {
    final game = gameTipsViewModelConsumer.game;
    if (game.gameState == GameState.startedResultNotKnown &&
        gameTipsViewModelConsumer.tip != null) {
      showMaterialModalBottomSheet(
        expand: false,
        context: context,
        builder: (context) => LiveScoringModal(gameTipsViewModelConsumer.tip!),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeagueLadderPage(
          league: game.league,
          teamDbKeysToDisplay: [game.homeTeam.dbkey, game.awayTeam.dbkey],
          customTitle: "League Leaderboard comparison.",
        ),
      ),
    );
  }

  void _recordGamePresentation(Game game, String presentation) {
    if (!AppResumeDiagnostics.enabled) {
      return;
    }
    AppResumeDiagnostics.recordGamePresentation(
      gameKey: game.dbkey,
      presentation: presentation,
      gameState: game.gameState.name,
      officialHomeScore: game.scoring?.homeTeamScore,
      officialAwayScore: game.scoring?.awayTeamScore,
      displayedHomeScore: game.scoring?.currentScore(ScoringTeam.home),
      displayedAwayScore: game.scoring?.currentScore(ScoringTeam.away),
      liveScoreCount: game.scoring?.crowdSourcedScores?.length ?? 0,
    );
  }

  // _initLeagueLadder is now _fetchAndSetLadderRanks
  // _buildNewHistoricalMatchupsCard has been removed.
}

/// Keeps the percentage request lifecycle the stats tab has always had, and
/// hands the loaded entry to the caller rather than rendering it.
class _PercentStatsRequest extends StatefulWidget {
  const _PercentStatsRequest({
    required this.gameTipViewModel,
    required this.statsViewModel,
    required this.gameStatsEntry,
    required this.builder,
  });

  final GameTipViewModel gameTipViewModel;
  final StatsViewModel? statsViewModel;
  final GameStatsEntry? gameStatsEntry;
  final Widget Function(GameStatsEntry? entry, bool loading) builder;

  @override
  State<_PercentStatsRequest> createState() => _PercentStatsRequestState();
}

class _PercentStatsRequestState extends State<_PercentStatsRequest> {
  @override
  void initState() {
    super.initState();
    _requestPercentStatsIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _PercentStatsRequest oldWidget) {
    super.didUpdateWidget(oldWidget);
    final gameChanged =
        oldWidget.gameTipViewModel.game.dbkey !=
        widget.gameTipViewModel.game.dbkey;
    final statsViewModelChanged =
        oldWidget.statsViewModel != widget.statsViewModel;
    if (gameChanged || statsViewModelChanged) {
      _requestPercentStatsIfNeeded();
    }
  }

  void _requestPercentStatsIfNeeded() {
    final statsViewModel = widget.statsViewModel;
    if (statsViewModel == null) {
      return;
    }
    if (widget.gameStatsEntry?.hasCompleteStats == true) {
      return;
    }
    statsViewModel.getGamesStatsEntry(widget.gameTipViewModel.game, false);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.gameStatsEntry;
    final complete = entry?.hasCompleteStats == true;
    final loadState = widget.statsViewModel?.gameStatsLoadStateFor(
      widget.gameTipViewModel.game,
    );
    return widget.builder(
      complete ? entry : null,
      !complete && loadState == GameStatsLoadState.loading,
    );
  }
}
