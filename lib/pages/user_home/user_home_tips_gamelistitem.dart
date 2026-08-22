import 'dart:developer'; // For log()
import 'dart:math' as math;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring_modal.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gameinfo.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_scoringtile.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:daufootytipping/services/percent_stats_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart'; // Added import
import 'package:flutter_svg/svg.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class GameListItem extends StatefulWidget {
  const GameListItem({
    super.key,
    required this.game,
    required this.currentTipper,
    required this.currentDAUComp,
    required this.allTipsViewModel,
    required this.isPercentStatsPage,
    this.sectionGameIndex,
    this.gameTipViewModel, // Optional for testing
  });

  final Game game;
  final Tipper currentTipper;
  final DAUComp currentDAUComp;
  final TipsViewModel allTipsViewModel;
  final bool isPercentStatsPage;
  final int? sectionGameIndex;
  final GameTipViewModel? gameTipViewModel; // Optional for testing

  @override
  State<GameListItem> createState() => _GameListItemState();
}

class _GameListItemState extends State<GameListItem> {
  static const String _loadingRankLabel = '--';
  static const String _noRankLabel = '';

  GameTipViewModel? _ownedGameTipsViewModel;
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
    _recordCardLifecycle('game-card.init');
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

    if (widget.isPercentStatsPage &&
        (!identical(oldWidget.game, widget.game) ||
            oldWidget.gameTipViewModel != widget.gameTipViewModel ||
            oldWidget.sectionGameIndex != widget.sectionGameIndex)) {
      PercentStatsDiagnostics.record(
        'game-card.did-update-widget',
        gameKey: widget.game.dbkey,
        details: <String, Object?>{
          'competitionKey': widget.currentDAUComp.dbkey,
          'sectionGameIndex': widget.sectionGameIndex,
          'oldWidgetGameIdentity': identityHashCode(oldWidget.game),
          'newWidgetGameIdentity': identityHashCode(widget.game),
          'sameWidgetGameObject': identical(oldWidget.game, widget.game),
          'oldWidgetGameKey': PercentStatsDiagnostics.keyFingerprint(
            oldWidget.game.dbkey,
          ),
          'newWidgetGameKey': PercentStatsDiagnostics.keyFingerprint(
            widget.game.dbkey,
          ),
          'gameTipViewModelIdentity': identityHashCode(gameTipsViewModel),
          'gameTipViewModelGameIdentity': identityHashCode(
            gameTipsViewModel.game,
          ),
        },
      );
    }
  }

  void _recordCardLifecycle(String stage) {
    if (!widget.isPercentStatsPage) {
      return;
    }
    PercentStatsDiagnostics.record(
      stage,
      gameKey: widget.game.dbkey,
      details: <String, Object?>{
        'competitionKey': widget.currentDAUComp.dbkey,
        'league': widget.game.league.name,
        'fixtureRoundNumber': widget.game.fixtureRoundNumber,
        'fixtureMatchNumber': widget.game.fixtureMatchNumber,
        'sectionGameIndex': widget.sectionGameIndex,
        'widgetGameIdentity': identityHashCode(widget.game),
        'gameTipViewModelIdentity': identityHashCode(gameTipsViewModel),
        'gameTipViewModelGameIdentity': identityHashCode(
          gameTipsViewModel.game,
        ),
      },
    );
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
          // Use new state variables for rank labels
          final String displayHomeRank = _isLoadingLadderRank
              ? _loadingRankLabel
              : (_homeOrdinalRankLabel ?? _noRankLabel);
          final String displayAwayRank = _isLoadingLadderRank
              ? _loadingRankLabel
              : (_awayOrdinalRankLabel ?? _noRankLabel);

          // Reference to the game for easier access in onTap
          final Game game = gameTipsViewModelConsumer.game;

          Widget gameDetailsCard = Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            color: Colors.white70,
            surfaceTintColor: League.nrl.colour,
            child: Row(
              children: [
                gameTipsViewModelConsumer.game.gameState ==
                        GameState.startedResultNotKnown
                    ? Tooltip(
                        message: 'Tap here to edit scoring for this game',
                        child: GestureDetector(
                          onTap: () => showMaterialModalBottomSheet(
                            expand: false,
                            context: context,
                            builder: (context) => LiveScoringModal(
                              gameTipsViewModelConsumer.tip!,
                            ),
                          ),
                          child: SizedBox(
                            width: Game.teamVersusTeamWidth,
                            child: _TeamVersusDisplay(
                              gameTipsViewModelConsumer:
                                  gameTipsViewModelConsumer,
                              displayHomeRank: '', // No rank in this branch
                              displayAwayRank: '', // No rank in this branch
                              homeTeamScoreWidget: liveScoringHome(
                                gameTipsViewModelConsumer.game,
                                context,
                              ),
                              awayTeamScoreWidget: liveScoringAway(
                                gameTipsViewModelConsumer.game,
                                context,
                              ),
                              middleRowWidget: liveScoringEdit(context),
                              teamNameTextStyle: Theme.of(
                                context,
                              ).textTheme.titleMedium!,
                              rankTextStyle: Theme.of(
                                context,
                              ).textTheme.labelSmall!,
                            ),
                          ),
                        ),
                      )
                    : SizedBox(
                        width: Game.teamVersusTeamWidth,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LeagueLadderPage(
                                  league: game.league,
                                  teamDbKeysToDisplay: [
                                    game.homeTeam.dbkey,
                                    game.awayTeam.dbkey,
                                  ],
                                  customTitle:
                                      "League Leaderboard comparison.", // Updated title
                                ),
                              ),
                            );
                          },
                          child: _TeamVersusDisplay(
                            gameTipsViewModelConsumer:
                                gameTipsViewModelConsumer,
                            displayHomeRank: displayHomeRank,
                            displayAwayRank: displayAwayRank,
                            homeTeamScoreWidget: fixtureScoringHome(
                              gameTipsViewModelConsumer,
                            ),
                            awayTeamScoreWidget: fixtureScoringAway(
                              gameTipsViewModelConsumer,
                            ),
                            middleRowWidget: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Hero(
                                  tag:
                                      "team_icon_${gameTipsViewModelConsumer.game.homeTeam.dbkey}",
                                  child: SvgPicture.asset(
                                    gameTipsViewModelConsumer
                                            .game
                                            .homeTeam
                                            .logoURI ??
                                        (gameTipsViewModelConsumer
                                                    .game
                                                    .league ==
                                                League.nrl
                                            ? League.nrl.logo
                                            : League.afl.logo),
                                    width: 25,
                                    height: 25,
                                  ),
                                ),
                                const Text(textAlign: TextAlign.left, ' V '),
                                Hero(
                                  tag:
                                      "team_icon_${gameTipsViewModelConsumer.game.awayTeam.dbkey}",
                                  child: SvgPicture.asset(
                                    gameTipsViewModelConsumer
                                            .game
                                            .awayTeam
                                            .logoURI ??
                                        (gameTipsViewModelConsumer
                                                    .game
                                                    .league ==
                                                League.nrl
                                            ? League.nrl.logo
                                            : League.afl.logo),
                                    width: 25,
                                    height: 25,
                                  ),
                                ),
                              ],
                            ),
                            teamNameTextStyle: Theme.of(
                              context,
                            ).textTheme.titleMedium!,
                            rankTextStyle: Theme.of(
                              context,
                            ).textTheme.labelSmall!,
                          ),
                        ),
                      ),
                Expanded(
                  child: Column(
                    children: [
                      CarouselSlider(
                        options: CarouselOptions(
                          height: Game.gameCardHeight - 8,
                          enlargeFactor: 1.0,
                          enlargeCenterPage: true,
                          enlargeStrategy: CenterPageEnlargeStrategy.zoom,
                          enableInfiniteScroll: false,
                          // Removed historical data fetching
                          onPageChanged: (index, reason) {}, // No longer needed
                        ),
                        items: carouselItems(
                          gameTipsViewModelConsumer,
                          widget.isPercentStatsPage,
                        ),
                        carouselController:
                            gameTipsViewModelConsumer.controller,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final scoring = game.scoring;
          final hasCrowdSourcedScore =
              scoring?.crowdSourcedScores?.isNotEmpty ?? false;
          final hasFinalFixtureScore =
              scoring?.homeTeamScore != null && scoring?.awayTeamScore != null;

          if (hasCrowdSourcedScore && !hasFinalFixtureScore) {
            return _buildInterimScoreBanner(context, gameDetailsCard);
          }

          // if game is more than 3 hours in the past, don't show any banner
          if (game.startTimeUTC.difference(DateTime.now()).inHours < -3) {
            return gameDetailsCard;
          }

          String bannerMessage;
          Color bannerColor;

          switch (game.gameState) {
            case GameState.startingSoon:
              bannerMessage = "Game today";
              bannerColor = Colors.orange;
              break;
            case GameState.startedResultNotKnown:
              bannerMessage = "Live";
              bannerColor = League.afl.colour;
              break;
            case GameState.startedResultKnown:
              // return standard gameDetailsCard with no banner overlay
              return gameDetailsCard;
            case GameState.notStarted:
              // return standard gameDetailsCard with no banner overlay
              return gameDetailsCard;
          }

          // return gameDetailsCard with banner overlay
          return Banner(
            color: bannerColor,
            location: BannerLocation.topEnd,
            message: bannerMessage,
            child: gameDetailsCard,
          );
        },
      ),
    );
  }

  Widget _buildInterimScoreBanner(BuildContext context, Widget child) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Banner(
          color: Colors.grey.shade600,
          location: BannerLocation.topEnd,
          message: '* Interim',
          child: child,
        ),
        Positioned(
          top: 0,
          right: 0,
          width: 78,
          height: 78,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Tooltip(
              message: 'Scores are based on interim live score data.',
              child: Semantics(
                button: true,
                label: 'Interim score warning',
                child: InkWell(
                  onTap: () =>
                      LiveScoresWarningCard.showLiveScoreDetails(context),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> carouselItems(
    GameTipViewModel gameTipsViewModelConsumer,
    bool isPercentStatsPage,
  ) {
    if (isPercentStatsPage) {
      return [gameStatsCard(gameTipsViewModelConsumer)];
    }

    // Always add the base cards for the game
    List<Widget> cards = [
      gameTipCard(gameTipsViewModelConsumer), // Tip Choice card
      GameInfo(
        gameTipsViewModelConsumer.game,
        gameTipsViewModelConsumer,
      ), // Game Info card
    ];

    // Historical matchup cards removed - now available in team comparison page

    // For games underway or ended, add scoring tile at the start
    if ((gameTipsViewModelConsumer.game.gameState ==
                GameState.startedResultNotKnown ||
            gameTipsViewModelConsumer.game.gameState ==
                GameState.startedResultKnown) &&
        gameTipsViewModelConsumer.tip != null) {
      cards.insert(0, scoringTileBuilder(gameTipsViewModelConsumer));
    }

    return cards;
  }

  // Historical matchup card builder removed - functionality moved to team comparison page

  Widget scoringTileBuilder(GameTipViewModel gameTipsViewModelConsumer) {
    return ScoringTile(
      tip: gameTipsViewModelConsumer.tip!,
      gameTipsViewModel: gameTipsViewModelConsumer,
      selectedDAUComp: widget.currentDAUComp,
    );
  }

  Widget gameTipCard(GameTipViewModel gameTipsViewModelConsumer) {
    return TipChoice(gameTipsViewModelConsumer, false);
  }

  Widget gameStatsCard(GameTipViewModel gameTipsViewModelConsumer) {
    return Selector<StatsViewModel?,
        ({StatsViewModel? viewModel, GameStatsEntry? entry})>(
      selector: (_, statsViewModel) {
        final game = gameTipsViewModelConsumer.game;
        final entry = statsViewModel?.gameStatsEntryFor(game);
        PercentStatsDiagnostics.record(
          'selector.select',
          gameKey: game.dbkey,
          details: <String, Object?>{
            'competitionKey': widget.currentDAUComp.dbkey,
            'sectionGameIndex': widget.sectionGameIndex,
            'gameIdentity': identityHashCode(game),
            'gameTipViewModelIdentity': identityHashCode(
              gameTipsViewModelConsumer,
            ),
            'statsViewModelIdentity': statsViewModel == null
                ? null
                : identityHashCode(statsViewModel),
            'bulkMapContainsKey':
                statsViewModel?.gamesStatsEntry.containsKey(game.dbkey),
            'bulkMapKeyCount': statsViewModel?.gamesStatsEntry.length,
            'selectedEntryPresent': entry != null,
            'selectedEntryComplete': entry?.hasCompleteStats,
          },
        );
        return (viewModel: statsViewModel, entry: entry);
      },
      builder: (context, statsSelection, child) {
        final game = gameTipsViewModelConsumer.game;
        PercentStatsDiagnostics.record(
          'selector.build',
          gameKey: game.dbkey,
          details: <String, Object?>{
            'competitionKey': widget.currentDAUComp.dbkey,
            'sectionGameIndex': widget.sectionGameIndex,
            'gameIdentity': identityHashCode(game),
            'gameTipViewModelIdentity': identityHashCode(
              gameTipsViewModelConsumer,
            ),
            'statsViewModelIdentity': statsSelection.viewModel == null
                ? null
                : identityHashCode(statsSelection.viewModel!),
            'selectedEntryPresent': statsSelection.entry != null,
            'selectedEntryComplete': statsSelection.entry?.hasCompleteStats,
          },
        );
        return _PercentStatsTipChoice(
          gameTipViewModel: gameTipsViewModelConsumer,
          listGame: widget.game,
          statsViewModel: statsSelection.viewModel,
          gameStatsEntry: statsSelection.entry,
          competitionKey: widget.currentDAUComp.dbkey,
          sectionGameIndex: widget.sectionGameIndex,
        );
      },
    );
  }

  // _initLeagueLadder is now _fetchAndSetLadderRanks
  // _buildNewHistoricalMatchupsCard has been removed.
}

class _PercentStatsTipChoice extends StatefulWidget {
  const _PercentStatsTipChoice({
    required this.gameTipViewModel,
    required this.listGame,
    required this.statsViewModel,
    required this.competitionKey,
    required this.sectionGameIndex,
    this.gameStatsEntry,
  });

  final GameTipViewModel gameTipViewModel;
  final Game listGame;
  final StatsViewModel? statsViewModel;
  final GameStatsEntry? gameStatsEntry;
  final String? competitionKey;
  final int? sectionGameIndex;

  @override
  State<_PercentStatsTipChoice> createState() => _PercentStatsTipChoiceState();
}

class _PercentStatsTipChoiceState extends State<_PercentStatsTipChoice> {
  Future<GameStatsEntry?>? _gameStatsLoad;
  String? _lastRecordedRenderState;

  @override
  void initState() {
    super.initState();
    _recordWidgetState('percent-widget.init');
    _requestPercentStatsIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _PercentStatsTipChoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool gameChanged =
        oldWidget.gameTipViewModel.game.dbkey !=
        widget.gameTipViewModel.game.dbkey;
    final bool statsViewModelChanged =
        oldWidget.statsViewModel != widget.statsViewModel;

    if (!identical(oldWidget.listGame, widget.listGame) ||
        !identical(
          oldWidget.gameTipViewModel.game,
          widget.gameTipViewModel.game,
        ) ||
        statsViewModelChanged ||
        oldWidget.gameStatsEntry != widget.gameStatsEntry) {
      _recordWidgetState(
        'percent-widget.did-update',
        extra: <String, Object?>{
          'oldListGameIdentity': identityHashCode(oldWidget.listGame),
          'newListGameIdentity': identityHashCode(widget.listGame),
          'oldStatsViewModelIdentity': oldWidget.statsViewModel == null
              ? null
              : identityHashCode(oldWidget.statsViewModel!),
          'newStatsViewModelIdentity': widget.statsViewModel == null
              ? null
              : identityHashCode(widget.statsViewModel!),
          'oldEntryPresent': oldWidget.gameStatsEntry != null,
          'newEntryPresent': widget.gameStatsEntry != null,
        },
      );
    }

    if (gameChanged || statsViewModelChanged) {
      _requestPercentStatsIfNeeded();
    }
  }

  void _requestPercentStatsIfNeeded() {
    final statsViewModel = widget.statsViewModel;
    if (statsViewModel == null) {
      _gameStatsLoad = null;
      _recordWidgetState('direct-request.skipped-no-view-model');
      return;
    }

    if (widget.gameStatsEntry?.hasCompleteStats == true) {
      _gameStatsLoad = Future<GameStatsEntry?>.value(widget.gameStatsEntry);
      _recordWidgetState('direct-request.skipped-bulk-entry-present');
      return;
    }

    final game = widget.gameTipViewModel.game;
    _recordWidgetState('direct-request.created');
    _gameStatsLoad = _loadPercentStats(statsViewModel, game);
  }

  Future<GameStatsEntry?> _loadPercentStats(
    StatsViewModel statsViewModel,
    Game game,
  ) async {
    try {
      final entry = await statsViewModel.loadGamesStatsEntry(game, false);
      PercentStatsDiagnostics.record(
        'direct-request.future-complete',
        gameKey: game.dbkey,
        details: <String, Object?>{
          'competitionKey': widget.competitionKey,
          'sectionGameIndex': widget.sectionGameIndex,
          'gameIdentity': identityHashCode(game),
          'gameTipViewModelIdentity': identityHashCode(
            widget.gameTipViewModel,
          ),
          'statsViewModelIdentity': identityHashCode(statsViewModel),
          'entryPresent': entry != null,
          'entryComplete': entry?.hasCompleteStats,
          'bulkMapContainsKey': statsViewModel.gamesStatsEntry.containsKey(
            game.dbkey,
          ),
          'bulkMapKeyCount': statsViewModel.gamesStatsEntry.length,
        },
      );
      return entry;
    } catch (error) {
      PercentStatsDiagnostics.record(
        'direct-request.future-error',
        gameKey: game.dbkey,
        details: <String, Object?>{
          'competitionKey': widget.competitionKey,
          'sectionGameIndex': widget.sectionGameIndex,
          'gameIdentity': identityHashCode(game),
          'gameTipViewModelIdentity': identityHashCode(
            widget.gameTipViewModel,
          ),
          'statsViewModelIdentity': identityHashCode(statsViewModel),
          'errorType': error.runtimeType.toString(),
        },
      );
      rethrow;
    }
  }

  void _recordWidgetState(
    String stage, {
    Map<String, Object?> extra = const {},
  }) {
    final game = widget.gameTipViewModel.game;
    final statsViewModel = widget.statsViewModel;
    PercentStatsDiagnostics.record(
      stage,
      gameKey: game.dbkey,
      details: <String, Object?>{
        'competitionKey': widget.competitionKey,
        'league': game.league.name,
        'fixtureRoundNumber': game.fixtureRoundNumber,
        'fixtureMatchNumber': game.fixtureMatchNumber,
        'sectionGameIndex': widget.sectionGameIndex,
        'listGameIdentity': identityHashCode(widget.listGame),
        'gameIdentity': identityHashCode(game),
        'gameTipViewModelIdentity': identityHashCode(
          widget.gameTipViewModel,
        ),
        'statsViewModelIdentity': statsViewModel == null
            ? null
            : identityHashCode(statsViewModel),
        'listenerEntryPresent': widget.gameStatsEntry != null,
        'listenerEntryComplete': widget.gameStatsEntry?.hasCompleteStats,
        'bulkMapContainsKey': statsViewModel?.gamesStatsEntry.containsKey(
          game.dbkey,
        ),
        'bulkMapKeyCount': statsViewModel?.gamesStatsEntry.length,
        ...extra,
      },
    );
  }

  void _recordRenderState(
    String renderState, {
    required bool renderedEntryPresent,
  }) {
    if (_lastRecordedRenderState == renderState) {
      return;
    }
    _lastRecordedRenderState = renderState;
    _recordWidgetState(
      'percent-widget.render',
      extra: <String, Object?>{
        'renderState': renderState,
        'renderedEntryPresent': renderedEntryPresent,
      },
    );
  }

  Future<void> _showDiagnostics() async {
    final game = widget.gameTipViewModel.game;
    final statsViewModel = widget.statsViewModel;
    final bulkKeys = statsViewModel?.gamesStatsEntry.keys ?? const <String>[];
    PercentStatsDiagnostics.record(
      'diagnostics.opened',
      gameKey: game.dbkey,
      details: <String, Object?>{
        'competitionKey': widget.competitionKey,
        'sectionGameIndex': widget.sectionGameIndex,
        'statsViewModelIdentity': statsViewModel == null
            ? null
            : identityHashCode(statsViewModel),
        'bulkMapContainsKey': statsViewModel?.gamesStatsEntry.containsKey(
          game.dbkey,
        ),
        'bulkMapKeyCount': statsViewModel?.gamesStatsEntry.length,
      },
    );
    final report = PercentStatsDiagnostics.buildReport(
      gameKey: game.dbkey,
      currentState: <String, Object?>{
        'platform': defaultTargetPlatform.name,
        'buildMode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'competitionKey': widget.competitionKey,
        'league': game.league.name,
        'fixtureRoundNumber': game.fixtureRoundNumber,
        'fixtureMatchNumber': game.fixtureMatchNumber,
        'sectionGameIndex': widget.sectionGameIndex,
        'listGameIdentity': identityHashCode(widget.listGame),
        'gameIdentity': identityHashCode(game),
        'sameListAndViewModelGame': identical(widget.listGame, game),
        'gameTipViewModelIdentity': identityHashCode(
          widget.gameTipViewModel,
        ),
        'statsViewModelIdentity': statsViewModel == null
            ? null
            : identityHashCode(statsViewModel),
        'listenerEntryPresent': widget.gameStatsEntry != null,
        'listenerEntryComplete': widget.gameStatsEntry?.hasCompleteStats,
        'bulkMapContainsKey': statsViewModel?.gamesStatsEntry.containsKey(
          game.dbkey,
        ),
        'bulkMapKeyCount': statsViewModel?.gamesStatsEntry.length,
        'nearMatchingBulkKeys':
            PercentStatsDiagnostics.nearMatchingKeyFingerprints(
              game.dbkey,
              bulkKeys,
            ),
      },
    );
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('% tipped diagnostics'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                report,
                key: const ValueKey('percent-stats-diagnostics-report'),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              key: const ValueKey('copy-percent-stats-diagnostics'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Diagnostics copied')),
                );
              },
              child: const Text('Copy diagnostics'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenerEntry = widget.gameStatsEntry;
    if (listenerEntry?.hasCompleteStats == true) {
      _recordRenderState('listener-entry', renderedEntryPresent: true);
      return TipChoice(
        widget.gameTipViewModel,
        true,
        gameStatsEntry: listenerEntry,
        percentStatsLoadComplete: true,
        onPercentStatsDiagnosticsRequested: _showDiagnostics,
      );
    }

    return FutureBuilder<GameStatsEntry?>(
      future: _gameStatsLoad,
      builder: (context, snapshot) {
        _recordRenderState(
          'future-${snapshot.connectionState.name}-${snapshot.data != null}',
          renderedEntryPresent: snapshot.data != null,
        );
        return TipChoice(
          widget.gameTipViewModel,
          true,
          gameStatsEntry: snapshot.data,
          percentStatsLoadComplete:
              snapshot.connectionState == ConnectionState.done,
          onPercentStatsDiagnosticsRequested: _showDiagnostics,
        );
      },
    );
  }
}

class _TeamDisplayRow extends StatelessWidget {
  const _TeamDisplayRow({
    required this.teamName,
    this.teamRank,
    required this.scoreWidget,
    required this.gameState,
    required this.textStyle,
    required this.rankTextStyle,
  });

  final String teamName;
  final String? teamRank;
  final Widget scoreWidget;
  final GameState gameState;
  final TextStyle textStyle;
  final TextStyle rankTextStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (teamRank != null &&
            teamRank!.isNotEmpty &&
            (gameState == GameState.notStarted ||
                gameState == GameState.startingSoon)) ...[
          Text(
            teamRank!,
            style: rankTextStyle,
            textScaler: const TextScaler.linear(0.9),
            textAlign: TextAlign.left,
            softWrap: true,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            teamName,
            style: textStyle,
            textAlign: TextAlign.left,
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
        ),
        const SizedBox(width: 5),
        scoreWidget,
      ],
    );
  }
}

class _TeamVersusDisplay extends StatelessWidget {
  const _TeamVersusDisplay({
    required this.gameTipsViewModelConsumer,
    required this.displayHomeRank,
    required this.displayAwayRank,
    required this.homeTeamScoreWidget,
    required this.awayTeamScoreWidget,
    required this.middleRowWidget,
    required this.teamNameTextStyle,
    required this.rankTextStyle,
  });

  final GameTipViewModel gameTipsViewModelConsumer;
  final String displayHomeRank;
  final String displayAwayRank;
  final Widget homeTeamScoreWidget;
  final Widget awayTeamScoreWidget;
  final Widget middleRowWidget;
  final TextStyle teamNameTextStyle;
  final TextStyle rankTextStyle;

  @override
  Widget build(BuildContext context) {
    final bool showExtra = shouldShowTextTeamInfo(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TeamDisplayRow(
          teamName: gameTipsViewModelConsumer.game.homeTeam.name,
          teamRank: showExtra ? displayHomeRank : null,
          scoreWidget: showExtra
              ? homeTeamScoreWidget
              : const SizedBox.shrink(),
          gameState: gameTipsViewModelConsumer.game.gameState,
          textStyle: teamNameTextStyle,
          rankTextStyle: rankTextStyle,
        ),
        // Always show middleRowWidget to ensure Hero widgets are present for animation
        // but make it invisible when showExtra is false
        showExtra
            ? middleRowWidget
            : Opacity(
                opacity: 0.0,
                child: SizedBox(
                  height: 0,
                  child: IgnorePointer(child: middleRowWidget),
                ),
              ),
        _TeamDisplayRow(
          teamName: gameTipsViewModelConsumer.game.awayTeam.name,
          teamRank: showExtra ? displayAwayRank : null,
          scoreWidget: showExtra
              ? awayTeamScoreWidget
              : const SizedBox.shrink(),
          gameState: gameTipsViewModelConsumer.game.gameState,
          textStyle: teamNameTextStyle,
          rankTextStyle: rankTextStyle,
        ),
      ],
    );
  }
}

bool shouldShowTextTeamInfo(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  final textScaler = MediaQuery.of(context).textScaler;
  // Hide if width is less than 340 or text scale is large
  return width > 340 && (textScaler.scale(1.0) < 1.3);
}

Widget liveScoringHome(Game consumerTipGame, BuildContext context) {
  return Text(
    style: const TextStyle(fontWeight: FontWeight.w800),
    ' ${consumerTipGame.scoring?.currentScore(ScoringTeam.home) ?? '0'}',
  );
}

Widget liveScoringAway(Game consumerTipGame, BuildContext context) {
  return Text(
    style: const TextStyle(fontWeight: FontWeight.w800),
    '${consumerTipGame.scoring?.currentScore(ScoringTeam.away) ?? '0'} ',
  );
}

Widget liveScoringEdit(BuildContext context) {
  return SizedBox(width: 30, child: const Icon(Icons.edit));
}

Widget fixtureScoringHome(GameTipViewModel consumerTipGameViewModel) {
  return Text(
    '${consumerTipGameViewModel.game.scoring!.homeTeamScore ?? ''}',
    style: consumerTipGameViewModel.game.scoring!.didHomeTeamWin()
        ? TextStyle(
            backgroundColor: Colors.lightGreen[200],
            fontWeight: FontWeight.w900,
          )
        : TextStyle(fontWeight: FontWeight.w600),
  );
}

Widget fixtureScoringAway(GameTipViewModel consumerTipGameViewModel) {
  return Text(
    '${consumerTipGameViewModel.game.scoring!.awayTeamScore ?? ''}',
    style: consumerTipGameViewModel.game.scoring!.didAwayTeamWin()
        ? TextStyle(
            backgroundColor: Colors.lightGreen[200],
            fontWeight: FontWeight.w900,
          )
        : TextStyle(fontWeight: FontWeight.w600),
  );
}
