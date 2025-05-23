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
  // LeagueLadder? _calculatedLadder; // Scoped locally to _fetchAndSetLadderRanks

  // State variables for historical data
  List<HistoricalMatchupUIData>? _historicalData;
  bool _isLoadingHistoricalData = false;
  bool _historicalDataError = false;

  // New state variables for ladder ranks
  String? _homeOrdinalRankLabel;
  String? _awayOrdinalRankLabel;
  bool _isLoadingLadderRank = false; 

  @override
  void initState() {
    super.initState();
    gameTipsViewModel = GameTipViewModel(widget.currentTipper,
        widget.currentDAUComp, widget.game, widget.allTipsViewModel);
    // DO NOT CALL _initLeagueLadder() / _fetchAndSetLadderRanks() here directly

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _homeOrdinalRankLabel == null && _awayOrdinalRankLabel == null && !_isLoadingLadderRank) {
        _fetchAndSetLadderRanks();
      }
    });
  }

  Future<void> _fetchHistoricalData() async {
    if (!mounted) return; 
    setState(() {
      _isLoadingHistoricalData = true;
      _historicalDataError = false;
    });

    try {
      final data = await gameTipsViewModel.getFormattedHistoricalMatchups();
      if (!mounted) return;
      setState(() {
        _historicalData = data;
        _isLoadingHistoricalData = false;
      });
    } catch (e) {
      log('Error fetching historical matchups: $e'); 
      if (!mounted) return;
      setState(() {
        _historicalDataError = true;
        _isLoadingHistoricalData = false;
      });
    }
  }

  Future<void> _fetchAndSetLadderRanks() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLadderRank = true;
    });

    try {
      final dauCompsViewModel = di<DAUCompsViewModel>();
      if (dauCompsViewModel.selectedDAUComp == null) {
        log('Selected DAUComp is null in _fetchAndSetLadderRanks. Cannot calculate ladder.');
        if (!mounted) return;
        setState(() { _isLoadingLadderRank = false; _homeOrdinalRankLabel = '--'; _awayOrdinalRankLabel = '--'; });
        return;
      }

      final gamesViewModel = dauCompsViewModel.gamesViewModel;
      if (gamesViewModel == null) {
        log('GamesViewModel is null in _fetchAndSetLadderRanks. Cannot calculate ladder.');
         if (!mounted) return;
        setState(() { _isLoadingLadderRank = false; _homeOrdinalRankLabel = '--'; _awayOrdinalRankLabel = '--'; });
        return;
      }
      
      await gamesViewModel.initialLoadComplete;

      final teamsViewModel = gamesViewModel.teamsViewModel;
      await teamsViewModel.initialLoadComplete;

      final ladderService = LadderCalculationService();

      List<Game> allGames = await gamesViewModel.getGames();
      List<Team> leagueTeams = teamsViewModel
              .groupedTeams[gameTipsViewModel.game.league.name.toLowerCase()]
              ?.cast<Team>() ??
          [];

      LeagueLadder? calculatedLadder = ladderService.calculateLadder(
        allGames: allGames,
        leagueTeams: leagueTeams,
        league: gameTipsViewModel.game.league,
      );

      String calculatedHomeLabel = '--';
      String calculatedAwayLabel = '--';

      if (calculatedLadder != null) {
        final homeIdx = calculatedLadder.teams.indexWhere((t) => t.dbkey == gameTipsViewModel.game.homeTeam.dbkey);
        final homeRank = (homeIdx == -1) ? null : homeIdx + 1;
        calculatedHomeLabel = homeRank != null ? LeagueLadder.ordinal(homeRank) : '--';

        final awayIdx = calculatedLadder.teams.indexWhere((t) => t.dbkey == gameTipsViewModel.game.awayTeam.dbkey);
        final awayRank = (awayIdx == -1) ? null : awayIdx + 1;
        calculatedAwayLabel = awayRank != null ? LeagueLadder.ordinal(awayRank) : '--';
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
          final String displayHomeRank = _homeOrdinalRankLabel ?? (_isLoadingLadderRank ? '' : '--');
          final String displayAwayRank = _awayOrdinalRankLabel ?? (_isLoadingLadderRank ? '' : '--');

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
                        "League Leaderboard comparison", // Updated title
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
                                        ? displayHomeRank 
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
                                        ? displayAwayRank
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
                              
                              bool isHistoricalCardEligible = 
                                  gameTipsViewModelConsumer.game.gameState == GameState.notStarted ||
                                  gameTipsViewModelConsumer.game.gameState == GameState.startingSoon;
                              int historicalCardIndex = 1; // Assuming it's the second card

                              if (isHistoricalCardEligible && index == historicalCardIndex) {
                                if (_historicalData == null && !_isLoadingHistoricalData && !_historicalDataError) {
                                  _fetchHistoricalData();
                                }
                              }
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
        _buildNewHistoricalMatchupsCard(gameTipsViewModelConsumer), // New card
        GameInfo(gameTipsViewModelConsumer.game,
            gameTipsViewModelConsumer), 
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

  Widget _buildNewHistoricalMatchupsCard(GameTipViewModel viewModel) {
    Widget content;

    if (_isLoadingHistoricalData) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0), // Add some space below heading
            child: Text('Previous matchups', style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold)),
          ),
          CircularProgressIndicator(color: League.nrl.colour),
        ],
      );
    } else if (_historicalDataError) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text('Previous matchups', style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold)),
          ),
          Text("Error loading history.", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic)),
        ],
      );
    } else if (_historicalData != null) {
      if (_historicalData!.isEmpty) {
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text('Previous matchups', style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold)),
            ),
            Text(
              "No past matchups found for these teams.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.0, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
          ],
        );
      } else {
        // Data is available and not empty, display it
        final matchups = _historicalData!;
        content = SingleChildScrollView( // Make the content scrollable if it overflows
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Make DataTable take full width
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text('Previous matchups', textAlign: TextAlign.center, style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold)),
              ),
              DataTable(
                columnSpacing: 10, 
                horizontalMargin: 8,
                headingRowHeight: 28, 
                dataRowHeight: 28, 
                headingTextStyle: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Colors.black87),
                dataTextStyle: TextStyle(fontSize: 10.5, color: Colors.black87),
                columns: const <DataColumn>[
                  DataColumn(label: Text('When')),
                  DataColumn(label: Text('Who won')),
                  DataColumn(label: Text('Where')),
                  DataColumn(label: Text('Your Tip')),
                ],
                rows: matchups.take(3).map((item) => DataRow( // Take first 3 to fit, or make table scrollable
                  cells: <DataCell>[
                    DataCell(Text(item.isCurrentYear ? item.month : "${item.month} ${item.year.substring(2)}")), // Shorten year
                    DataCell(Text(item.winningTeamName, overflow: TextOverflow.ellipsis)),
                    DataCell(Text(item.winType)),
                    DataCell(Text(item.userTipTeamName.isNotEmpty ? item.userTipTeamName : "N/A", overflow: TextOverflow.ellipsis)),
                  ],
                )).toList(),
              ),
            ],
          ),
        );
      }
    } else {
      // Default initial state (before it's active and loaded or if data is null and no error/loading)
      content = Column(
         mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text('Previous matchups', style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold)),
          ),
          Text("View history by swiping.", style: TextStyle(fontSize: 12.0, color: Colors.black54, fontStyle: FontStyle.italic)),
        ],
      );
    }

    return Card(
      elevation: 2.0, // Or 1.0 for empty/initial states if preferred
      margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Container(
        height: 100, // Overall height constraint for the card's content area
        padding: EdgeInsets.all(4.0), // Padding for the card content
        alignment: Alignment.center, // Center the content if it's smaller than the container
        child: content,
      ),
    );
  }

  // _initLeagueLadder is now _fetchAndSetLadderRanks
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
