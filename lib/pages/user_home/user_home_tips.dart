import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundscoresfortipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TipsPage extends StatefulWidget with WatchItStatefulWidgetMixin {
  TipsPage({super.key});

  @override
  TipsPageState createState() => TipsPageState();
}

class TipsPageState extends State<TipsPage> {
  final String currentDAUCompDbkey =
      di<DAUCompsViewModel>().selectedDAUCompDbKey;
  late final AllTipsViewModel allTipsViewModel;
  late final Future<DAUComp> dauCompWithScoresFuture;
  //late final CompScore compScores;
  late final Future<void> allTipsViewModelInitialLoadCompletedFuture;
  final ScrollController controller = ScrollController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    log('TipsPageBody.constructor()');

    dauCompWithScoresFuture = di<DAUCompsViewModel>().getCompWithScores();

    allTipsViewModel = AllTipsViewModel.forTipper(
        di<TippersViewModel>(),
        currentDAUCompDbkey,
        di<GamesViewModel>(),
        di<TippersViewModel>().selectedTipper);

    allTipsViewModelInitialLoadCompletedFuture =
        allTipsViewModel.initialLoadCompleted;
  }

  @override
  Widget build(BuildContext context) {
    log('TipsPageBody.build()');

/*     double gameCardHeight = 128.0; 
    double leagueHeaderHeight = 66;
    double emptyRoundHeight = 75;
    int gameCount = 27; 
    int roundCount = 3; 
    double scrollPosition =
        (gameCardHeight * gameCount) + (leagueHeaderHeight * 2 * roundCount); */

    Widget scrollView = FutureBuilder<DAUComp>(
        future: dauCompWithScoresFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text(
                    'Error loading dauCompWithScores: ${snapshot.stackTrace}'));
          } else if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          } else {
            DAUComp? dauCompWithScores = snapshot.data;

            return FutureBuilder<void>(
                future: allTipsViewModel.getAllTips(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child:
                            Text('Error loading GameTip: ${snapshot.error}'));
                  } else if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  } else {
                    WidgetsBinding.instance
                        .addPostFrameCallback((timeStamp) async {
                      if (controller.hasClients) {
                        controller.position.isScrollingNotifier.addListener(() {
                          if (_debounceTimer?.isActive ?? false) {
                            _debounceTimer!.cancel();
                          }
                          _debounceTimer =
                              Timer(const Duration(milliseconds: 500), () {
                            log('scrolling stopped');
                            SharedPreferences.getInstance().then((prefs) async {
                              await prefs.setDouble(
                                  'scrollPosition', controller.offset);
                            });
                          });
                        });

                        SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                        double initialScrollPosition =
                            prefs.getDouble('scrollPosition') ?? 0.0;
                        controller.jumpTo(initialScrollPosition);
                      } else {
                        log('controller has no clients');
                      }
                    });

                    return CustomScrollView(
                      controller: controller,
                      cacheExtent: 10000,
                      slivers: <Widget>[
                        SliverAppBar(
                          backgroundColor: Colors.white.withOpacity(0.8),
                          pinned: true,
                          floating: true,
                          expandedHeight: 50,
                          flexibleSpace: FlexibleSpaceBar(
                              expandedTitleScale: 1.5,
                              centerTitle: true,
                              title: ChangeNotifierProvider<
                                      AllScoresViewModel>.value(
                                  value: di<AllScoresViewModel>(),
                                  builder: (context, snapshot) {
                                    return Consumer<AllScoresViewModel>(builder:
                                        (context, allScoresViewModelConsumer,
                                            child) {
                                      CompScore compScores =
                                          allScoresViewModelConsumer
                                              .getTipperConsolidatedScoresForComp(
                                                  di<TippersViewModel>()
                                                      .selectedTipper!);
                                      // from allScoresViewModelConsumer.leaderboard list,
                                      // find the tipper and record their rank
                                      int tipperCompRank =
                                          allScoresViewModelConsumer.leaderboard
                                              .firstWhere((element) =>
                                                  element.tipper ==
                                                  di<TippersViewModel>()
                                                      .selectedTipper!)
                                              .rank;
                                      return GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (context) =>
                                                    StatRoundScoresForTipper(
                                                        di<TippersViewModel>()
                                                            .selectedTipper!)),
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
                              )
                              //background: compHeaderListTile(
                              //    dauCompWithScores!.consolidatedCompScores,
                              //    dauCompWithScores.name),
                              ),
                        ),
                        ...dauCompWithScores!.daurounds!
                            .asMap()
                            .entries
                            .map((entry) {
                          DAURound dauRound = entry.value;
                          return SliverList(
                            delegate: SliverChildListDelegate(
                              [
                                roundLeagueHeaderListTile(
                                    League.nrl, 50, 50, dauRound),
                                GameListBuilder(
                                  currentTipper:
                                      di<TippersViewModel>().selectedTipper!,
                                  dauRound: dauRound,
                                  league: League.nrl,
                                  allTipsViewModel: allTipsViewModel,
                                  selectedDAUComp: dauCompWithScores,
                                ),
                                roundLeagueHeaderListTile(
                                    League.afl, 40, 40, dauRound),
                                GameListBuilder(
                                  currentTipper:
                                      di<TippersViewModel>().selectedTipper!,
                                  dauRound: dauRound,
                                  league: League.afl,
                                  allTipsViewModel: allTipsViewModel,
                                  selectedDAUComp: dauCompWithScores,
                                )
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  }
                });
          }
        });

    return scrollView;
  }

  Widget roundLeagueHeaderListTile(
      League leagueHeader, double width, double height, DAURound dauRound) {
    return Stack(
      children: [
        ListTile(
          onTap: () async {
            // When the round header is clicked,
            // update the scoring for this round and tipper
            // TODO consider removing this functionality
            // di<DAUCompsViewModel>().updateScoring(
            //     await di<DAUCompsViewModel>()
            //         .getCurrentDAUComp()
            //         .then((DAUComp? dauComp) {
            //       return dauComp!;
            //     }),
            //     di<TippersViewModel>().selectedTipper!,
            //     dauRound);
          },
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SvgPicture.asset(
                leagueHeader.logo,
                width: width,
                height: height,
              ),
              Column(
                children: [
                  Text(
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      'R o u n d: ${dauRound.dAUroundNumber} ${leagueHeader.name.toUpperCase()}'),
                  dauRound.roundStarted
                      ? Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Score: ${leagueHeader == League.afl ? dauRound.roundScores!.aflScore : dauRound.roundScores!.nrlScore} / ${leagueHeader == League.afl ? dauRound.roundScores!.aflMaxScore : dauRound.roundScores!.nrlMaxScore}')
                      : const SizedBox.shrink(),
                  dauRound.roundStarted
                      ? Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Margins: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginTips : dauRound.roundScores!.nrlMarginTips} / UPS: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginUPS : dauRound.roundScores!.nrlMarginUPS}')
                      : Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Margins: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginTips : dauRound.roundScores!.nrlMarginTips} '),
                  dauRound.roundStarted
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
  final AllTipsViewModel allTipsViewModel;
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
        daucompsViewModel
            .getGamesForCombinedRoundNumber(widget.dauRound.dAUroundNumber);

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
            return const Center(child: CircularProgressIndicator());
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

                return Theme(
                  data: myTheme, // override the flex theme for this widget
                  child: GameListItem(
                    roundGames: games!,
                    game: game,
                    currentTipper: widget.currentTipper,
                    currentDAUComp: widget.selectedDAUComp,
                    allTipsViewModel: widget.allTipsViewModel,
                  ),
                );
              },
            );
          }
        });
  }
}
