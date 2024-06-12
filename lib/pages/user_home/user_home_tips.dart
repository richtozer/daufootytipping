import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundscoresfortipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class TipsPage extends StatefulWidget {
  const TipsPage({super.key});

  @override
  TipsPageState createState() => TipsPageState();
}

class TipsPageState extends State<TipsPage> {
  final String currentDAUCompDbkey =
      di<DAUCompsViewModel>().selectedDAUComp!.dbkey!;
  late final TipsViewModel tipperTipsViewModel;
  late final Future<DAUComp> dauCompWithScoresFuture;

  late final Future<void> allTipsViewModelInitialLoadCompletedFuture;

  @override
  void initState() {
    log('TipsPageBody.constructor()');

    dauCompWithScoresFuture = di<DAUCompsViewModel>().getCompWithScores();

    tipperTipsViewModel = TipsViewModel.forTipper(
        di<TippersViewModel>(),
        currentDAUCompDbkey,
        di<GamesViewModel>(),
        di<TippersViewModel>().selectedTipper);

    allTipsViewModelInitialLoadCompletedFuture =
        tipperTipsViewModel.initialLoadCompleted;

    super.initState();
  }

  // method to scroll to the current round
  void scrollToCurrentRound() {
    log('TipsPageBody.scrollToCurrentRound()');

    int latestRoundNumber = di<DAUCompsViewModel>()
        .selectedDAUComp!
        .getHighestRoundNumberWithAllGamesPlayed();

    log('TipsPageBody.scrollToCurrentRound() latestRoundNumber: $latestRoundNumber');

    int index = (latestRoundNumber) * 4;

    di<DAUCompsViewModel>().itemScrollController.scrollTo(
          index: index,
          duration: const Duration(seconds: 1),
          curve: Curves.easeInOut,
        );
  }

  @override
  Widget build(BuildContext context) {
    log('TipsPageBody.build()');

    return ChangeNotifierProvider<DAUCompsViewModel>(
        create: (context) => di<DAUCompsViewModel>(),
        builder: (context, isAlternateMode) {
          return FutureBuilder<DAUComp>(
              future: dauCompWithScoresFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child:
                          CircularProgressIndicator(color: League.afl.colour));
                } else {
                  DAUComp? dauCompWithScores = snapshot.data;

                  //TODO enable this
                  int latestRoundNumber = dauCompWithScores!
                      .getHighestRoundNumberWithAllGamesPlayed();
                  log('TipsPageBody.build() latestRoundNumber: $latestRoundNumber');

                  return Theme(
                    data: myTheme,
                    child: ScrollablePositionedList.builder(
                      itemScrollController:
                          di<DAUCompsViewModel>().itemScrollController,
                      initialAlignment: -2, //display a few pixels of prev round
                      initialScrollIndex: (latestRoundNumber - 1) * 4,
                      itemCount: dauCompWithScores.daurounds.length * 4,
                      itemBuilder: (context, index) {
                        final roundIndex = index ~/ 4;
                        final itemIndex = index % 4;
                        final dauRound =
                            dauCompWithScores.daurounds[roundIndex];

                        if (itemIndex == 0) {
                          return roundLeagueHeaderListTile(
                              League.nrl, 50, 50, dauRound);
                        } else if (itemIndex == 1) {
                          return GameListBuilder(
                            currentTipper:
                                di<TippersViewModel>().selectedTipper!,
                            dauRound: dauRound,
                            league: League.nrl,
                            allTipsViewModel: tipperTipsViewModel,
                            selectedDAUComp: dauCompWithScores,
                          );
                        } else if (itemIndex == 2) {
                          return roundLeagueHeaderListTile(
                              League.afl, 40, 40, dauRound);
                        } else if (itemIndex == 3) {
                          return GameListBuilder(
                            currentTipper:
                                di<TippersViewModel>().selectedTipper!,
                            dauRound: dauRound,
                            league: League.afl,
                            allTipsViewModel: tipperTipsViewModel,
                            selectedDAUComp: dauCompWithScores,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  );
                }
              });
        });
  }

  Widget roundLeagueHeaderListTile(League leagueHeader, double logoWidth,
      double logoHeight, DAURound dauRound) {
    return Stack(
      children: [
        ListTile(
          onTap: scrollToCurrentRound,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SvgPicture.asset(
                leagueHeader.logo,
                width: logoWidth,
                height: logoHeight,
              ),
              Column(
                children: [
                  Text(
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      'R o u n d: ${dauRound.dAUroundNumber} ${leagueHeader.name.toUpperCase()}'),
                  dauRound.roundState != RoundState.notStarted
                      ? Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Score: ${leagueHeader == League.afl ? dauRound.roundScores!.aflScore : dauRound.roundScores!.nrlScore} / ${leagueHeader == League.afl ? dauRound.roundScores!.aflMaxScore : dauRound.roundScores!.nrlMaxScore}')
                      : const SizedBox.shrink(),
                  dauRound.roundState != RoundState.notStarted
                      ? Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Margins: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginTips : dauRound.roundScores!.nrlMarginTips} / UPS: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginUPS : dauRound.roundScores!.nrlMarginUPS}')
                      : Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Margins: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginTips : dauRound.roundScores!.nrlMarginTips} '),
                  dauRound.roundState != RoundState.notStarted
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                                'Rank: ${dauRound.roundScores!.rank}  '),
                            dauRound.roundScores!.rankChange > 0
                                ? const Icon(
                                    color: Colors.green, Icons.arrow_upward)
                                : dauRound.roundScores!.rankChange < 0
                                    ? const Icon(
                                        color: Colors.red, Icons.arrow_downward)
                                    : const Icon(
                                        color: Colors.redAccent,
                                        Icons.sync_alt),
                            Text('${dauRound.roundScores!.rankChange}'),
                          ],
                        )
                      : const SizedBox.shrink(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AppBarHeader extends StatelessWidget {
  const AppBarHeader({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.white.withOpacity(0.8),
      pinned: false,
      floating: true,
      expandedHeight: 40,
      flexibleSpace: FlexibleSpaceBar(
          expandedTitleScale: 1.5,
          centerTitle: true,
          title: ChangeNotifierProvider<ScoresViewModel>.value(
              value: di<ScoresViewModel>(),
              builder: (context, snapshot) {
                return Consumer<ScoresViewModel>(
                    builder: (context, scoresViewModelConsumer, child) {
                  CompScore compScores = scoresViewModelConsumer
                      .getTipperConsolidatedScoresForComp(
                          di<TippersViewModel>().selectedTipper!);
                  // from scoresViewModelConsumer.leaderboard list,
                  // find the tipper and record their rank
                  int tipperCompRank = scoresViewModelConsumer.leaderboard
                      .firstWhere(
                        (element) =>
                            element.tipper.dbkey ==
                            di<TippersViewModel>().selectedTipper!.dbkey,
                        orElse: () => LeaderboardEntry(
                            rank: 0,
                            tipper: di<TippersViewModel>().selectedTipper!,
                            total: 0,
                            nRL: 0,
                            aFL: 0,
                            numRoundsWon: 0,
                            aflMargins: 0,
                            aflUPS: 0,
                            nrlMargins: 0,
                            nrlUPS: 0),
                      )
                      .rank;
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => StatRoundScoresForTipper(
                                di<TippersViewModel>().selectedTipper!)),
                      );
                    },
                    child: Text(
                      'R a n k: $tipperCompRank NRL: ${compScores.nrlCompScore} AFL: ${compScores.aflCompScore}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Colors.black,
                      ),
                    ),
                  );
                });
              }),
          background: Stack(
            children: <Widget>[
              Image.asset(
                width: MediaQuery.of(context).size.width,
                'assets/teams/daulogo.jpg',
                fit: BoxFit.fitWidth,
              ),
              Container(
                color: Colors.white.withOpacity(0.5),
              ),
            ],
          )),
    );
  }
}

class GameListBuilder extends StatefulWidget {
  const GameListBuilder(
      {super.key,
      required this.currentTipper,
      required this.dauRound,
      required this.league,
      required this.allTipsViewModel,
      required this.selectedDAUComp});

  final Tipper currentTipper;
  final DAURound dauRound;
  final League league;
  final TipsViewModel allTipsViewModel;
  final DAUComp selectedDAUComp;

  @override
  State<GameListBuilder> createState() => _GameListBuilderState();
}

class _GameListBuilderState extends State<GameListBuilder> {
  late Game loadingGame;
  late DAUCompsViewModel daucompsViewModel;

  List<Game>? games;
  Future<List<Game>?>? gamesFuture;

  @override
  void initState() {
    super.initState();

    daucompsViewModel = di<DAUCompsViewModel>();

    //get all the games for this round
    Future<Map<League, List<Game>>> gamesForCombinedRoundNumber =
        daucompsViewModel.sortGamesIntoLeagues(
            widget.dauRound, di<GamesViewModel>());

    //get all the games for this round and league
    gamesFuture =
        gamesForCombinedRoundNumber.then((Map<League, List<Game>> gamesMap) {
      return gamesMap[widget.league];
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Game>?>(
        future: gamesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
                child: CircularProgressIndicator(color: League.afl.colour));
          } else {
            games = snapshot.data;

            if (games!.isEmpty) {
              return SizedBox(
                height: 75,
                child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    color: Colors.grey[300],
                    child: Center(
                        child: Text(
                            'No ${widget.league.name.toUpperCase()} games this round'))),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(0),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: games!.length,
              itemBuilder: (context, index) {
                var game = games![index];

                return GameListItem(
                  key: ValueKey(game.dbkey),
                  roundGames: games!,
                  game: game,
                  currentTipper: widget.currentTipper,
                  currentDAUComp: widget.selectedDAUComp,
                  allTipsViewModel: widget.allTipsViewModel,
                  dauRound: widget.dauRound,
                );
              },
            );
          }
        });
  }
}
