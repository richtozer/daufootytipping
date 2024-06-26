import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
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
  late TipsViewModel tipperTipsViewModel;
  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();
  int latestRoundNumber = 1;

  @override
  void initState() {
    log('TipsPageBody.constructor()');
    super.initState();
    _fetchData();

    latestRoundNumber = daucompsViewModel.selectedDAUComp!
        .getHighestRoundNumberWithAllGamesPlayed();
    log('TipsPageBody.build() latestRoundNumber: $latestRoundNumber');
  }

  Future<void> _fetchData() async {
    tipperTipsViewModel = TipsViewModel.forTipper(
        di<TippersViewModel>(),
        currentDAUCompDbkey,
        di<GamesViewModel>(),
        di<TippersViewModel>().selectedTipper);
    await tipperTipsViewModel.initialLoadCompleted;
    return;
  }

  @override
  Widget build(BuildContext context) {
    log('TipsPageBody.build()');

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DAUCompsViewModel>.value(
            value: daucompsViewModel),
        ChangeNotifierProvider<ScoresViewModel?>.value(
            value: di<ScoresViewModel>()),
      ],
      child: Theme(
        data: myTheme,
        child: Consumer<DAUCompsViewModel>(
            builder: (context, daucompsViewmodelConsumer, client) {
          return ScrollablePositionedList.builder(
            itemScrollController:
                daucompsViewmodelConsumer.itemScrollController,
            initialScrollIndex: (latestRoundNumber) * 4,
            initialAlignment: 0.1,
            itemCount:
                daucompsViewmodelConsumer.selectedDAUComp!.daurounds.length * 4,
            itemBuilder: (context, index) {
              final roundIndex = index ~/ 4;
              final itemIndex = index % 4;
              final dauRound = daucompsViewmodelConsumer
                  .selectedDAUComp!.daurounds[roundIndex];

              if (itemIndex == 0) {
                return Consumer<ScoresViewModel?>(
                    builder: (context, scoresViewmodelConsumer, client) {
                  return roundLeagueHeaderListTile(
                      League.nrl, 50, 50, dauRound, scoresViewmodelConsumer);
                });
              } else if (itemIndex == 1) {
                return GameListBuilder(
                  currentTipper: di<TippersViewModel>().selectedTipper!,
                  dauRound: dauRound,
                  league: League.nrl,
                  allTipsViewModel: tipperTipsViewModel,
                  dauCompsViewModel: daucompsViewmodelConsumer,
                );
              } else if (itemIndex == 2) {
                return Consumer<ScoresViewModel?>(
                    builder: (context, scoresViewmodelConsumer, client) {
                  return roundLeagueHeaderListTile(
                      League.afl, 40, 40, dauRound, scoresViewmodelConsumer);
                });
              } else if (itemIndex == 3) {
                return GameListBuilder(
                  currentTipper: di<TippersViewModel>().selectedTipper!,
                  dauRound: dauRound,
                  league: League.afl,
                  allTipsViewModel: tipperTipsViewModel,
                  dauCompsViewModel: daucompsViewmodelConsumer,
                );
              }
              return const SizedBox.shrink();
            },
          );
        }),
      ),
    );
  }

  Widget roundLeagueHeaderListTile(
      League leagueHeader,
      double logoWidth,
      double logoHeight,
      DAURound dauRound,
      ScoresViewModel? scoresViewmodelConsumer) {
    RoundScores? roundScores;

    var selectedTipperScores = scoresViewmodelConsumer
        ?.allTipperRoundScores[di<TippersViewModel>().selectedTipper];

    if (selectedTipperScores != null) {
      roundScores = selectedTipperScores[dauRound.dAUroundNumber];
    } else {
      roundScores = null; // Or assign a default value if appropriate.
    }
    return Stack(
      children: [
        ListTile(
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
                          'Score: ${leagueHeader == League.afl ? roundScores?.aflScore : roundScores?.nrlScore} / ${leagueHeader == League.afl ? roundScores?.aflMaxScore : roundScores?.nrlMaxScore}')
                      : const SizedBox.shrink(),
                  dauRound.roundState != RoundState.notStarted
                      ? Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Margins: ${leagueHeader == League.afl ? dauRound.roundScores.aflMarginTips : dauRound.roundScores.nrlMarginTips} / UPS: ${leagueHeader == League.afl ? dauRound.roundScores.aflMarginUPS : dauRound.roundScores.nrlMarginUPS}')
                      : Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Margins: ${leagueHeader == League.afl ? dauRound.roundScores.aflMarginTips : dauRound.roundScores.nrlMarginTips} '),
                  dauRound.roundState != RoundState.notStarted
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                                'Rank: ${dauRound.roundScores.rank}  '),
                            dauRound.roundScores.rankChange > 0
                                ? const Icon(
                                    color: Colors.green, Icons.arrow_upward)
                                : dauRound.roundScores.rankChange < 0
                                    ? const Icon(
                                        color: Colors.red, Icons.arrow_downward)
                                    : const Icon(
                                        color: Colors.redAccent,
                                        Icons.sync_alt),
                            Text('${dauRound.roundScores.rankChange}'),
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
  const GameListBuilder({
    super.key,
    required this.currentTipper,
    required this.dauRound,
    required this.league,
    required this.allTipsViewModel,
    required this.dauCompsViewModel,
  });

  final Tipper currentTipper;
  final DAURound dauRound;
  final League league;
  final TipsViewModel allTipsViewModel;
  final DAUCompsViewModel dauCompsViewModel;

  @override
  State<GameListBuilder> createState() => _GameListBuilderState();
}

class _GameListBuilderState extends State<GameListBuilder> {
  late Game loadingGame;

  List<Game>? games;
  Future<List<Game>?>? gamesFuture;

  @override
  void initState() {
    super.initState();

    //get all the games for this round
    Future<Map<League, List<Game>>> gamesForCombinedRoundNumber =
        widget.dauCompsViewModel.sortGamesIntoLeagues(
      widget.dauRound,
      di<GamesViewModel>(),
    );

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
            child: CircularProgressIndicator(color: League.afl.colour),
          );
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
                      'No ${widget.league.name.toUpperCase()} games this round'),
                ),
              ),
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
                currentDAUComp: widget.dauCompsViewModel.selectedDAUComp!,
                allTipsViewModel: widget.allTipsViewModel,
                dauRound: widget.dauRound,
              );
            },
          );
        }
      },
    );
  }
}
