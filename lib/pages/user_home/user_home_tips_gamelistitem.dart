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

class GameListItem extends StatefulWidget {
  const GameListItem({
    super.key,
    required this.game,
    required this.currentTipper,
    required this.currentDAUComp,
    required this.allTipsViewModel,
    required this.isPercentStatsPage,
  });

  final Game game;
  final Tipper currentTipper;
  final DAUComp currentDAUComp;
  final TipsViewModel allTipsViewModel;
  final bool isPercentStatsPage;

  @override
  State<GameListItem> createState() => _GameListItemState();
}

class _GameListItemState extends State<GameListItem> {
  late final GameTipViewModel gameTipsViewModel;
  LeagueLadder? _calculatedLadder;

  @override
  void initState() {
    super.initState();
    gameTipsViewModel = GameTipViewModel(widget.currentTipper,
        widget.currentDAUComp, widget.game, widget.allTipsViewModel);
    _initLeagueLadder();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameTipViewModel>.value(
      value: gameTipsViewModel,
      child: Consumer<GameTipViewModel>(
        builder: (context, gameTipsViewModelConsumer, child) {
          // Helper to get rank (1-based) for a team dbkey
          int? getTeamRank(String dbkey) {
            if (_calculatedLadder == null) return null;
            final idx =
                _calculatedLadder?.teams.indexWhere((t) => t.dbkey == dbkey);
            return (idx == null || idx == -1) ? null : idx + 1;
          }

          // For home team label
          final homeRank =
              getTeamRank(gameTipsViewModelConsumer.game.homeTeam.dbkey);
          final homeOrdinalRankLabel =
              homeRank != null ? LeagueLadder.ordinal(homeRank) : '';

          // For away team label
          final awayRank =
              getTeamRank(gameTipsViewModelConsumer.game.awayTeam.dbkey);
          final awayOrdinalRankLabel =
              awayRank != null ? LeagueLadder.ordinal(awayRank) : '';

          // Reference to the game for easier access in onTap
          final Game game = gameTipsViewModelConsumer.game;

          Widget gameDetailsCard = GestureDetector(
            // Wrapped Card with GestureDetector
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LeagueLadderPage(
                    league: game.league,
                    teamDbKeysToDisplay: [
                      game.homeTeam.dbkey,
                      game.awayTeam.dbkey
                    ],
                    customTitle:
                        "${game.league.name.toUpperCase()} Ladder comparison", // Updated title
                  ),
                ),
              );
            },
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              color: Colors.white70,
              surfaceTintColor: League.nrl.colour,
              child: Row(children: [
                gameTipsViewModelConsumer.game.gameState ==
                        GameState.startedResultNotKnown
                    ? Tooltip(
                        message: 'Click here to edit scoring for this game',
                        child: GestureDetector(
                          onTap: () => showMaterialModalBottomSheet(
                              expand: false,
                              context: context,
                              builder: (context) => LiveScoringModal(
                                  gameTipsViewModelConsumer.tip!)),
                          child: Padding(
                            padding: const EdgeInsets.all(0.0),
                            child: SizedBox(
                              width: 130,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        gameTipsViewModelConsumer
                                            .game.homeTeam.name,
                                        textAlign: TextAlign.left,
                                        style: const TextStyle(
                                          overflow: TextOverflow.ellipsis,
                                          fontSize: 16.0,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 5,
                                      ),
                                      gameTipsViewModelConsumer
                                                  .game.gameState ==
                                              GameState.startedResultNotKnown
                                          ? liveScoringHome(
                                              gameTipsViewModelConsumer.game,
                                              context)
                                          : fixtureScoringHome(
                                              gameTipsViewModelConsumer),
                                    ],
                                  ),
                                  gameTipsViewModelConsumer.game.gameState ==
                                          GameState.startedResultNotKnown
                                      ? liveScoringEdit(context)
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SvgPicture.asset(
                                              gameTipsViewModelConsumer
                                                      .game.homeTeam.logoURI ??
                                                  (gameTipsViewModelConsumer
                                                              .game.league ==
                                                          League.nrl
                                                      ? League.nrl.logo
                                                      : League.afl.logo),
                                              width: 25,
                                              height: 25,
                                            ),
                                            const Text(
                                                textAlign: TextAlign.left,
                                                ' V '),
                                            SvgPicture.asset(
                                              gameTipsViewModelConsumer
                                                      .game.awayTeam.logoURI ??
                                                  (gameTipsViewModelConsumer
                                                              .game.league ==
                                                          League.nrl
                                                      ? League.nrl.logo
                                                      : League.afl.logo),
                                              width: 25,
                                              height: 25,
                                            ),
                                          ],
                                        ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                          style: const TextStyle(
                                            overflow: TextOverflow.ellipsis,
                                            fontSize: 16.0,
                                          ),
                                          textAlign: TextAlign.left,
                                          gameTipsViewModelConsumer
                                              .game.awayTeam.name),
                                      SizedBox(
                                        width: 5,
                                      ),
                                      gameTipsViewModelConsumer
                                                  .game.gameState ==
                                              GameState.startedResultNotKnown
                                          ? liveScoringAway(
                                              gameTipsViewModelConsumer.game,
                                              context)
                                          : fixtureScoringAway(
                                              gameTipsViewModelConsumer),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(0.0),
                        child: SizedBox(
                          width: 130,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // do not show rank game result is known
                                  Text(
                                    gameTipsViewModelConsumer.game.gameState ==
                                                GameState.notStarted ||
                                            gameTipsViewModelConsumer
                                                    .game.gameState ==
                                                GameState.startingSoon
                                        ? homeOrdinalRankLabel
                                        : '',
                                    style: const TextStyle(
                                      overflow: TextOverflow.ellipsis,
                                      fontSize: 12.0,
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                  if (gameTipsViewModelConsumer
                                              .game.gameState ==
                                          GameState.notStarted ||
                                      gameTipsViewModelConsumer
                                              .game.gameState ==
                                          GameState.startingSoon)
                                    SizedBox(
                                      width: 5,
                                    )
                                  else
                                    Container(),
                                  Text(
                                    gameTipsViewModelConsumer
                                        .game.homeTeam.name,
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                      overflow: TextOverflow.ellipsis,
                                      fontSize: 16.0,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 5,
                                  ),
                                  gameTipsViewModelConsumer.game.gameState ==
                                          GameState.startedResultNotKnown
                                      ? liveScoringHome(
                                          gameTipsViewModelConsumer.game,
                                          context)
                                      : fixtureScoringHome(
                                          gameTipsViewModelConsumer),
                                ],
                              ),
                              gameTipsViewModelConsumer.game.gameState ==
                                      GameState.startedResultNotKnown
                                  ? liveScoringEdit(context)
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SvgPicture.asset(
                                          gameTipsViewModelConsumer
                                                  .game.homeTeam.logoURI ??
                                              (gameTipsViewModelConsumer
                                                          .game.league ==
                                                      League.nrl
                                                  ? League.nrl.logo
                                                  : League.afl.logo),
                                          width: 25,
                                          height: 25,
                                        ),
                                        const Text(
                                            textAlign: TextAlign.left, ' V '),
                                        SvgPicture.asset(
                                          gameTipsViewModelConsumer
                                                  .game.awayTeam.logoURI ??
                                              (gameTipsViewModelConsumer
                                                          .game.league ==
                                                      League.nrl
                                                  ? League.nrl.logo
                                                  : League.afl.logo),
                                          width: 25,
                                          height: 25,
                                        ),
                                      ],
                                    ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // do not show rank game result is known
                                  Text(
                                    gameTipsViewModelConsumer.game.gameState ==
                                                GameState.notStarted ||
                                            gameTipsViewModelConsumer
                                                    .game.gameState ==
                                                GameState.startingSoon
                                        ? awayOrdinalRankLabel
                                        : '',
                                    style: const TextStyle(
                                      overflow: TextOverflow.ellipsis,
                                      fontSize: 12.0,
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                  if (gameTipsViewModelConsumer
                                              .game.gameState ==
                                          GameState.notStarted ||
                                      gameTipsViewModelConsumer
                                              .game.gameState ==
                                          GameState.startingSoon)
                                    SizedBox(
                                      width: 5,
                                    )
                                  else
                                    Container(),
                                  Text(
                                      style: const TextStyle(
                                        overflow: TextOverflow.ellipsis,
                                        fontSize: 16.0,
                                      ),
                                      textAlign: TextAlign.left,
                                      gameTipsViewModelConsumer
                                          .game.awayTeam.name),
                                  SizedBox(
                                    width: 5,
                                  ),
                                  gameTipsViewModelConsumer.game.gameState ==
                                          GameState.startedResultNotKnown
                                      ? liveScoringAway(
                                          gameTipsViewModelConsumer.game,
                                          context)
                                      : fixtureScoringAway(
                                          gameTipsViewModelConsumer),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                Expanded(
                  child: Column(
                    children: [
                      CarouselSlider(
                        options: CarouselOptions(
                            height: 120,
                            enlargeFactor: 1.0,
                            enlargeCenterPage: true,
                            enlargeStrategy: CenterPageEnlargeStrategy.zoom,
                            enableInfiniteScroll: false,
                            onPageChanged: (index, reason) {
                              gameTipsViewModelConsumer.currentIndex = index;
                            }),
                        items: carouselItems(gameTipsViewModelConsumer,
                            widget.isPercentStatsPage),
                        carouselController:
                            gameTipsViewModelConsumer.controller,
                      ),
                    ],
                  ),
                )
              ]),
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
      GameTipViewModel gameTipsViewModelConsumer, bool isPercentStatsPage) {
    if (isPercentStatsPage) {
      return [
        gameStatsCard(gameTipsViewModelConsumer),
      ];
    }
    if (gameTipsViewModelConsumer.game.gameState == GameState.notStarted ||
        gameTipsViewModelConsumer.game.gameState == GameState.startingSoon) {
      return [
        gameTipCard(gameTipsViewModelConsumer),
        _buildHistoricalInsightsCard(gameTipsViewModelConsumer),
        GameInfo(gameTipsViewModelConsumer.game,
            gameTipsViewModelConsumer), // Corrected to pass gameTipsViewModelConsumer
      ];
    } else {
      return [
        scoringTileBuilder(
            gameTipsViewModelConsumer), // game is underway or ended - show scoring card
        gameTipCard(gameTipsViewModelConsumer),
        GameInfo(gameTipsViewModelConsumer.game, gameTipsViewModelConsumer)
      ];
    }
  }

  FutureBuilder<dynamic> scoringTileBuilder(
      GameTipViewModel gameTipsViewModelConsumer) {
    return FutureBuilder<Tip?>(
      future: gameTipsViewModelConsumer.gettip(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ScoringTile(
              tip: snapshot.data!,
              gameTipsViewModel: gameTipsViewModelConsumer,
              selectedDAUComp: widget.currentDAUComp);
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

  Widget _buildHistoricalInsightsCard(GameTipViewModel viewModel) {
    if (viewModel.historicalTotalTipsOnCombination == 0) {
      // Return a less verbose message or shrink to fit better if "No past data..." is too long
      return Card(
        elevation: 1.0, // Less prominent than other cards
        margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Padding(
          padding: EdgeInsets.all(12.0),
          child: Text(
            "No past tips by you on this matchup.",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.0,
                color: Colors.black54,
                fontStyle: FontStyle.italic),
          ),
        ),
      );
    }
    return Card(
      elevation: 2.0,
      margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Padding(
        padding: EdgeInsets.all(12.0),
        child: Text(
          viewModel.historicalInsightsString,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.0, color: Colors.black87),
        ),
      ),
    );
  }

  void _initLeagueLadder() async {
    final dauCompsViewModel = di<DAUCompsViewModel>();
    if (dauCompsViewModel.selectedDAUComp == null) {
      return;
    }

    final gamesViewModel = di<DAUCompsViewModel>().gamesViewModel;
    await gamesViewModel!.initialLoadComplete;

    final teamsViewModel = gamesViewModel.teamsViewModel;
    await teamsViewModel.initialLoadComplete;

    final ladderService = LadderCalculationService();

    List<Game> allGames = await gamesViewModel.getGames();
    List<Team> leagueTeams = teamsViewModel
            .groupedTeams[gameTipsViewModel.game.league.name.toLowerCase()]
            ?.cast<Team>() ??
        [];

    _calculatedLadder = ladderService.calculateLadder(
      allGames: allGames,
      leagueTeams: leagueTeams,
      league: gameTipsViewModel.game.league,
    );
  }
}

Widget liveScoringHome(Game consumerTipGame, BuildContext context) {
  return Text(
      style: const TextStyle(fontWeight: FontWeight.w800),
      ' ${consumerTipGame.scoring?.currentScore(ScoringTeam.home) ?? '0'}');
}

Widget liveScoringAway(Game consumerTipGame, BuildContext context) {
  return Text(
      style: const TextStyle(fontWeight: FontWeight.w800),
      '${consumerTipGame.scoring?.currentScore(ScoringTeam.away) ?? '0'} ');
}

Widget liveScoringEdit(BuildContext context) {
  return SizedBox(
    width: 30,
    child: const Icon(Icons.edit),
  );
}

Widget fixtureScoringHome(GameTipViewModel consumerTipGameViewModel) {
  return Text('${consumerTipGameViewModel.game.scoring!.homeTeamScore ?? ''}',
      style: consumerTipGameViewModel.game.scoring!.didHomeTeamWin()
          ? TextStyle(
              backgroundColor: Colors.lightGreen[200],
              fontWeight: FontWeight.w900)
          : TextStyle(fontWeight: FontWeight.w600));
}

Widget fixtureScoringAway(GameTipViewModel consumerTipGameViewModel) {
  return Text('${consumerTipGameViewModel.game.scoring!.awayTeamScore ?? ''}',
      style: consumerTipGameViewModel.game.scoring!.didAwayTeamWin()
          ? TextStyle(
              backgroundColor: Colors.lightGreen[200],
              fontWeight: FontWeight.w900)
          : TextStyle(fontWeight: FontWeight.w600));
}
