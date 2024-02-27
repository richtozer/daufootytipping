import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/round_comp_scoring.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:watch_it/watch_it.dart';

class TipsPage extends StatelessWidget with WatchItMixin {
  TipsPage({super.key}) {
    allTipsViewModel = AllTipsViewModel.forTipper(
        di<TippersViewModel>(),
        currentDAUComp,
        di<GamesViewModel>(),
        di<TippersViewModel>().selectedTipper);

    dauCompWithScoresFuture = di<DAUCompsViewModel>()
        .getCompWithScores(di<TippersViewModel>().selectedTipper!);

    allTipsViewModelInitialLoadCompletedFuture =
        allTipsViewModel.initialLoadCompleted;
  }

  final String currentDAUComp = di<DAUCompsViewModel>().selectedDAUCompDbKey;
  late AllTipsViewModel allTipsViewModel;
  late Future<DAUComp> dauCompWithScoresFuture;
  late Future<void> allTipsViewModelInitialLoadCompletedFuture;

  @override
  Widget build(BuildContext context) {
    return _TipsPageBody(
        dauCompWithScoresFuture,
        allTipsViewModelInitialLoadCompletedFuture,
        allTipsViewModel,
        currentDAUComp);
  }
}

class _TipsPageBody extends StatelessWidget with WatchItMixin {
  _TipsPageBody(
      this.dauCompWithScoresFuture,
      this.allTipsViewModelInitialLoadCompletedFuture,
      this.allTipsViewModel,
      this.currentDAUComp) {
    log('TipsPageBody.constructor()');
  }

  final String currentDAUComp;
  late final AllTipsViewModel allTipsViewModel;
  late final Future<DAUComp> dauCompWithScoresFuture;
  late final Future<void> allTipsViewModelInitialLoadCompletedFuture;

  @override
  Widget build(BuildContext context) {
    // final dauCompWithScores2 = watchFuture(
    //         (DAUCompsViewModel x) =>
    //             x.getCompWithScores(di<TippersViewModel>().selectedTipper!),
    //         initialValue: null)
    //     .data;
    log('TipsPageBody.build()');

    //TODO need to implement some sort of change notifier to update the UI?

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

            return FutureBuilder<void>(
                future: allTipsViewModel.getTips(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child:
                            Text('Error loading GameTip: ${snapshot.error}'));
                  } else if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  } else {
                    return CustomScrollView(
                      //controller: controller,
                      slivers: <Widget>[
                        SliverAppBar(
                          pinned: true,
                          flexibleSpace: FlexibleSpaceBar(
                            //background: compHeaderListTile(dauCompWithScores2!),
                            background: compHeaderListTile(
                                dauCompWithScores!.consolidatedCompScores,
                                dauCompWithScores.name),
                          ),
                        ),
                        //...dauCompWithScores2.daurounds!
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
                                ),
                                roundLeagueHeaderListTile(
                                    League.afl, 40, 40, dauRound),
                                GameListBuilder(
                                  currentTipper:
                                      di<TippersViewModel>().selectedTipper!,
                                  dauRound: dauRound,
                                  league: League.afl,
                                  allTipsViewModel: allTipsViewModel,
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

  Widget compHeaderListTile(CompScore? compScore, String compName) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/teams/daulogo.jpg',
            fit: BoxFit.fill,
          ),
        ),
        ListTile(
          trailing: SvgPicture.asset(League.afl.logo, width: 40, height: 40),
          leading: SvgPicture.asset(League.nrl.logo, width: 50, height: 50),
          title: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Column(
              children: [
                Text(
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    compName),
                Text(
                    'NRL: ${compScore!.nrlCompScore} / ${compScore.nrlCompMaxScore}'),
                Text(
                    'AFL: ${compScore.aflCompScore} / ${compScore.aflCompMaxScore}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget roundLeagueHeaderListTile(
      League leagueHeader, double width, double height, DAURound dauRound) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/teams/daulogo.jpg',
            fit: BoxFit.fill,
          ),
        ),
        ListTile(
          onTap: () async {
            // When the round header is clicked,
            // update the scoring for this round and tipper
            // TODO consider removing this functionality
            di<DAUCompsViewModel>().updateScoring(
                await di<DAUCompsViewModel>()
                    .getCurrentDAUComp()
                    .then((DAUComp? dauComp) {
                  return dauComp!;
                }),
                di<TippersViewModel>().selectedTipper!);
          },
          trailing: SvgPicture.asset(
            leagueHeader.logo,
            width: width,
            height: height,
          ),
          title: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Column(
              children: [
                Text(
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    'R o u n d: ${dauRound.dAUroundNumber} ${leagueHeader.name.toUpperCase()}'),
                Text(
                    'Score: ${leagueHeader == League.afl ? dauRound.roundScores!.aflScore : dauRound.roundScores!.nrlScore} / ${leagueHeader == League.afl ? dauRound.roundScores!.aflMaxScore : dauRound.roundScores!.nrlMaxScore}'),
                Text(
                    'Margins: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginTips : dauRound.roundScores!.nrlMarginTips} / UPS: ${leagueHeader == League.afl ? dauRound.roundScores!.aflMarginUPS : dauRound.roundScores!.nrlMarginUPS}'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Rank: ${dauRound.roundScores!.rank}  '),
                    dauRound.roundScores!.rankChange > 0
                        ? const Icon(color: Colors.green, Icons.arrow_upward)
                        : dauRound.roundScores!.rankChange < 0
                            ? const Icon(
                                color: Colors.red, Icons.arrow_downward)
                            : const Icon(
                                color: Colors.redAccent, Icons.sync_alt),
                    Text('${dauRound.roundScores!.rankChange}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class GameListBuilder extends StatelessWidget with WatchItMixin {
  GameListBuilder({
    super.key,
    required this.currentTipper,
    required this.dauRound,
    required this.league,
    required this.allTipsViewModel,
  }) {
    dcvm = di<DAUCompsViewModel>();
  }

  late Game loadingGame;

  List<Game>? games;

  final Tipper currentTipper;
  final DAURound dauRound;
  final League league;
  final AllTipsViewModel allTipsViewModel;
  late final DAUCompsViewModel dcvm;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Game>?>(
        future: dcvm.getGamesForCombinedRoundNumberAndLeague(
            dauRound.dAUroundNumber, league),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          } else {
            games = snapshot.data;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: games!.length,
              itemBuilder: (context, index) {
                var game = games![index];

                return GameListItem(
                  roundGames: games!,
                  game: game,
                  currentTipper: currentTipper,
                  currentDAUCompDBkey:
                      di<DAUCompsViewModel>().selectedDAUCompDbKey,
                  allTipsViewModel: allTipsViewModel,
                );
              },
            );
          }
        });
  }
}
