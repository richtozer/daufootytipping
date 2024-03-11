import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:watch_it/watch_it.dart';

class TipsPage extends StatefulWidget with WatchItStatefulWidgetMixin {
  TipsPage({super.key});

  @override
  State<TipsPage> createState() => _TipsPageState();
}

class _TipsPageState extends State<TipsPage> {
  final String currentDAUCompDbkey =
      di<DAUCompsViewModel>().selectedDAUCompDbKey;

  @override
  Widget build(BuildContext context) {
    return _TipsPageBody(currentDAUCompDbkey);
  }
}

class _TipsPageBody extends StatelessWidget with WatchItMixin {
  _TipsPageBody(this.currentDAUCompDbkey) {
    log('TipsPageBody.constructor()');

    dauCompWithScoresFuture = di<DAUCompsViewModel>()
        .getCompWithScores(di<TippersViewModel>().selectedTipper!);

    allTipsViewModel = AllTipsViewModel.forTipper(
        di<TippersViewModel>(),
        currentDAUCompDbkey,
        di<GamesViewModel>(),
        di<TippersViewModel>().selectedTipper);

    allTipsViewModelInitialLoadCompletedFuture =
        allTipsViewModel.initialLoadCompleted;
  }

  final String currentDAUCompDbkey;
  late final AllTipsViewModel allTipsViewModel;
  late final Future<DAUComp> dauCompWithScoresFuture;
  late final Future<void> allTipsViewModelInitialLoadCompletedFuture;
  final ScrollController controller = ScrollController();

  @override
  Widget build(BuildContext context) {
    log('TipsPageBody.build()');

    double gameCardHeight = 128.0; // Replace with your actual item height
    double leagueHeaderHeight = 66;
    double emptyRoundHeight = 75;
    int gameCount = 247; // Replace with your actual index
    int roundCount = 16; // Replace with your actual index
    double scrollPosition =
        (gameCardHeight * gameCount) + (leagueHeaderHeight * 2 * roundCount);

// Use the controller to scroll to the desired position

    return FutureBuilder<DAUComp>(
        future: dauCompWithScoresFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child:
                    Text('Error loading dauCompWithScores: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          } else {
            DAUComp? dauCompWithScores = snapshot.data;
            int aflScore =
                dauCompWithScores!.consolidatedCompScores!.aflCompScore;
            int nrlScore =
                dauCompWithScores.consolidatedCompScores!.nrlCompScore;

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
                    return CustomScrollView(
                      controller: controller,
                      cacheExtent: 10000,
                      slivers: <Widget>[
                        SliverAppBar(
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.arrow_downward),
                              onPressed: () {
                                // controller.jumpTo(scrollPosition);
                                controller.animateTo(scrollPosition,
                                    duration: const Duration(seconds: 1),
                                    curve: Curves.easeInOut);
                              },
                            ),
                          ],
                          backgroundColor: Colors.white.withOpacity(0.8),
                          pinned: true,
                          floating: true,
                          expandedHeight: 50,
                          flexibleSpace: FlexibleSpaceBar(
                              expandedTitleScale: 1.5,
                              centerTitle: true,
                              title: Text(
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.black,
                                  ),
                                  'Rank X▲ NRL: $nrlScore AFL: $aflScore'),
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
                        ...dauCompWithScores.daurounds!
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
  GameListBuilder(
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

    gamesFuture = daucompsViewModel.getGamesForCombinedRoundNumberAndLeague(
        widget.dauRound.dAUroundNumber, widget.league);
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
