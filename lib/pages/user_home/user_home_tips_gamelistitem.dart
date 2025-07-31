import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring_modal.dart';
import 'package:daufootytipping/services/ladder_calculation_service.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gameinfo.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_scoringtile.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:flutter/material.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart'; // Added import
import 'package:flutter_svg/svg.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:developer'; // For log()

class GameListItem extends StatefulWidget {
  const GameListItem({
    super.key,
    required this.game,
    required this.currentTipper,
    required this.currentDAUComp,
    required this.allTipsViewModel,
    required this.isPercentStatsPage,
    this.gameTipViewModel, // Optional for testing
  });

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
  late final GameTipViewModel gameTipsViewModel;
  // LeagueLadder? _calculatedLadder; // Scoped locally to _fetchAndSetLadderRanks

  // New state variables for ladder ranks
  String? _homeOrdinalRankLabel;
  String? _awayOrdinalRankLabel;
  bool _isLoadingLadderRank = false;

  @override
  void initState() {
    super.initState();
    gameTipsViewModel =
        widget.gameTipViewModel ??
        GameTipViewModel(
          widget.currentTipper,
          widget.currentDAUComp,
          widget.game,
          widget.allTipsViewModel,
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _homeOrdinalRankLabel == null &&
          _awayOrdinalRankLabel == null &&
          !_isLoadingLadderRank) {
        _fetchAndSetLadderRanks();
      }
    });
  }

  Future<void> _fetchAndSetLadderRanks() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLadderRank = true;
    });

    try {
      final dauCompsViewModel = di<DAUCompsViewModel>();
      if (dauCompsViewModel.selectedDAUComp == null) {
        log(
          'Selected DAUComp is null in _fetchAndSetLadderRanks. Cannot calculate ladder.',
        );
        if (!mounted) return;
        setState(() {
          _isLoadingLadderRank = false;
          _homeOrdinalRankLabel = '--';
          _awayOrdinalRankLabel = '--';
        });
        return;
      }

      final gamesViewModel = dauCompsViewModel.gamesViewModel;
      if (gamesViewModel == null) {
        log(
          'GamesViewModel is null in _fetchAndSetLadderRanks. Cannot calculate ladder.',
        );
        if (!mounted) return;
        setState(() {
          _isLoadingLadderRank = false;
          _homeOrdinalRankLabel = '--';
          _awayOrdinalRankLabel = '--';
        });
        return;
      }

      await gamesViewModel.initialLoadComplete;

      final teamsViewModel = gamesViewModel.teamsViewModel;
      await teamsViewModel.initialLoadComplete;

      final ladderService = LadderCalculationService();

      List<Game> allGames = await gamesViewModel.getGames();
      List<Team> leagueTeams =
          teamsViewModel
              .groupedTeams[gameTipsViewModel.game.league.name.toLowerCase()]
              ?.cast<Team>() ??
          [];

      // Yield control before heavy ladder calculation
      await Future.microtask(() {});

      LeagueLadder? calculatedLadder = ladderService.calculateLadder(
        allGames: allGames,
        leagueTeams: leagueTeams,
        league: gameTipsViewModel.game.league,
      );

      String calculatedHomeLabel = '--';
      String calculatedAwayLabel = '--';

      if (calculatedLadder != null) {
        final homeIdx = calculatedLadder.teams.indexWhere(
          (t) => t.dbkey == gameTipsViewModel.game.homeTeam.dbkey,
        );
        final homeRank = (homeIdx == -1) ? null : homeIdx + 1;
        calculatedHomeLabel = homeRank != null
            ? LeagueLadder.ordinal(homeRank)
            : '--';

        final awayIdx = calculatedLadder.teams.indexWhere(
          (t) => t.dbkey == gameTipsViewModel.game.awayTeam.dbkey,
        );
        final awayRank = (awayIdx == -1) ? null : awayIdx + 1;
        calculatedAwayLabel = awayRank != null
            ? LeagueLadder.ordinal(awayRank)
            : '--';
      }

      if (!mounted) return;
      setState(() {
        _homeOrdinalRankLabel = calculatedHomeLabel;
        _awayOrdinalRankLabel = calculatedAwayLabel;
        _isLoadingLadderRank = false;
      });
    } catch (e) {
      log('Error fetching and setting ladder ranks: $e');
      if (!mounted) return;
      setState(() {
        _homeOrdinalRankLabel = 'N/A'; // Error indicator
        _awayOrdinalRankLabel = 'N/A'; // Error indicator
        _isLoadingLadderRank = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameTipViewModel>.value(
      value: gameTipsViewModel,
      child: Consumer<GameTipViewModel>(
        builder: (context, gameTipsViewModelConsumer, child) {
          // Use new state variables for rank labels
          final String displayHomeRank =
              _homeOrdinalRankLabel ?? (_isLoadingLadderRank ? '' : '--');
          final String displayAwayRank =
              _awayOrdinalRankLabel ?? (_isLoadingLadderRank ? '' : '--');

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
                        message: 'Click here to edit scoring for this game',
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

          // if game is more than 3 hours in the past, don't show any banner
          if (gameTipsViewModelConsumer.game.startTimeUTC
                  .difference(DateTime.now())
                  .inHours <
              -3) {
            return gameDetailsCard;
          }

          String bannerMessage;
          Color bannerColor;

          switch (gameTipsViewModelConsumer.game.gameState) {
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
    if (gameTipsViewModelConsumer.game.gameState ==
            GameState.startedResultNotKnown ||
        gameTipsViewModelConsumer.game.gameState ==
            GameState.startedResultKnown) {
      cards.insert(0, scoringTileBuilder(gameTipsViewModelConsumer));
    }

    return cards;
  }

  // Historical matchup card builder removed - functionality moved to team comparison page

  FutureBuilder<dynamic> scoringTileBuilder(
    GameTipViewModel gameTipsViewModelConsumer,
  ) {
    return FutureBuilder<Tip?>(
      future: gameTipsViewModelConsumer.getTip(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ScoringTile(
            tip: snapshot.data!,
            gameTipsViewModel: gameTipsViewModelConsumer,
            selectedDAUComp: widget.currentDAUComp,
          );
        } else {
          return CircularProgressIndicator(color: League.nrl.colour);
        }
      },
    );
  }

  Widget gameTipCard(GameTipViewModel gameTipsViewModelConsumer) {
    return TipChoice(gameTipsViewModelConsumer, false);
  }

  Widget gameStatsCard(GameTipViewModel gameTipsViewModelConsumer) {
    return TipChoice(gameTipsViewModelConsumer, true);
  }

  // _initLeagueLadder is now _fetchAndSetLadderRanks
  // _buildNewHistoricalMatchupsCard has been removed.
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
      mainAxisAlignment: MainAxisAlignment.start,
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
