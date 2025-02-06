import 'dart:developer';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_kickoffCountdown.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class TipsTab extends StatefulWidget {
  const TipsTab({super.key});

  @override
  TipsTabState createState() => TipsTabState();
}

class TipsTabState extends State<TipsTab> {
  final String? currentDAUCompDbkey =
      di<DAUCompsViewModel>().selectedDAUComp?.dbkey;

  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();
  int latestRoundNumber = 1;

  @override
  void initState() {
    log('TipsPageBody.constructor()');
    super.initState();

    if (daucompsViewModel.selectedDAUComp == null) {
      log('TipsPageBody.initState() selectedDAUComp is null');
      return;
    }

    latestRoundNumber =
        daucompsViewModel.selectedDAUComp!.highestRoundNumberInPast();
    log('TipsPageBody.initState() latestRoundNumber: $latestRoundNumber');
    if (daucompsViewModel.selectedDAUComp!.daurounds.isEmpty) {
      latestRoundNumber = 0;
      log('no rounds found. setting initial scroll position to 0');
    }
  }

  @override
  Widget build(BuildContext context) {
    log('TipsPageBody.build()');

    if (daucompsViewModel.selectedDAUComp == null) {
      return Center(
        child: SizedBox(
          height: 75,
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            color: Colors.black38,
            child: const Center(
              child: Text(
                'Nothing to see here. Contact daufootytipping@gmail.com.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DAUCompsViewModel>.value(
            value: daucompsViewModel),
        ChangeNotifierProvider<StatsViewModel?>.value(
            value: di<StatsViewModel>()),
      ],
      child: Theme(
        data: myTheme,
        child: Consumer<DAUCompsViewModel>(
            builder: (context, daucompsViewmodelConsumer, client) {
          return ScrollablePositionedList.builder(
            itemScrollController:
                daucompsViewmodelConsumer.itemScrollController,
            initialScrollIndex: (latestRoundNumber) * 4,
            initialAlignment:
                0.15, // peek at the last game in the previous round
            // calculate item count: 4 items per round
            // plus 1 card for start of competition and plus 1 card for the end of competition card
            itemCount:
                (daucompsViewmodelConsumer.selectedDAUComp!.daurounds.length *
                        4) +
                    1 +
                    1,
            itemBuilder: (context, index) {
              // insert a card at the start saying 'New here?' then 'You will find the instructions and scoring on the Profile Tab.'
              if (index == 0) {
                return SizedBox(
                  height: 200,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    color: Colors.black38,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Spacer(),
                          Spacer(),
                          Spacer(),
                          Spacer(),
                          Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Icon(Icons.sports_rugby, color: Colors.white70),
                              Text(
                                'Start of competition\n${daucompsViewmodelConsumer.selectedDAUComp!.name}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Icon(Icons.sports_rugby, color: Colors.white70),
                            ],
                          ),
                          Spacer(),
                          Text(
                            'New here? You will find instructions and scoring information in the [Help...] section on the Profile Tab.',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Spacer(),
                        ],
                      ),
                    ),
                  ),
                );
              }
              // Check if this is the last item
              if (index ==
                  (daucompsViewmodelConsumer.selectedDAUComp!.daurounds.length *
                          4) +
                      1) {
                // Return a widget indicating the end of the competition
                return SizedBox(
                  height: 75,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    color: Colors.black38,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Icon(Icons.flag, color: Colors.white70),
                        Text(
                          'End of the competition',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Icon(Icons.flag, color: Colors.white70),
                      ],
                    ),
                  ),
                );
              }

              final roundIndex = (index - 1) ~/ 4;
              final itemIndex = (index - 1) % 4;
              final dauRound = daucompsViewmodelConsumer
                  .selectedDAUComp!.daurounds[roundIndex];

              if (itemIndex == 0) {
                return Consumer<StatsViewModel?>(
                    builder: (context, scoresViewmodelConsumer, client) {
                  return roundLeagueHeaderListTile(
                      League.nrl, 50, 50, dauRound, scoresViewmodelConsumer);
                });
              } else if (itemIndex == 1) {
                return GameListBuilder(
                  currentTipper: di<TippersViewModel>().selectedTipper!,
                  dauRound: dauRound,
                  league: League.nrl,
                  tipperTipsViewModel:
                      daucompsViewmodelConsumer.selectedTipperTipsViewModel!,
                  dauCompsViewModel: daucompsViewmodelConsumer,
                );
              } else if (itemIndex == 2) {
                return Consumer<StatsViewModel?>(
                    builder: (context, scoresViewmodelConsumer, client) {
                  return roundLeagueHeaderListTile(
                      League.afl, 40, 40, dauRound, scoresViewmodelConsumer);
                });
              } else if (itemIndex == 3) {
                return GameListBuilder(
                  currentTipper: di<TippersViewModel>().selectedTipper!,
                  dauRound: dauRound,
                  league: League.afl,
                  tipperTipsViewModel:
                      daucompsViewmodelConsumer.selectedTipperTipsViewModel,
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

  Widget leagueNotTippedCountBadge(int counter) {
    return Stack(
      children: <Widget>[
        IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              // setState(() {
              //   counter = 0;
              // });
            }),
        counter != 0
            ? Positioned(
                right: 11,
                top: 11,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: League.afl.colour,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 14,
                    minHeight: 14,
                  ),
                  child: Text(
                    '$counter',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Container()
      ],
    );
  }

  Widget roundLeagueHeaderListTile(
      League leagueHeader,
      double logoWidth,
      double logoHeight,
      DAURound dauRound,
      StatsViewModel? scoresViewmodelConsumer) {
    // check for null values
    RoundStats roundStats = scoresViewmodelConsumer
                ?.allTipperRoundStats[dauRound.dAUroundNumber - 1]
            ?[di<TippersViewModel>().selectedTipper] ??
        RoundStats(
            roundNumber: 0,
            aflScore: 0,
            aflMaxScore: 0,
            aflMarginTips: 0,
            aflMarginUPS: 0,
            nrlScore: 0,
            nrlMaxScore: 0,
            nrlMarginTips: 0,
            nrlMarginUPS: 0,
            rank: 0,
            rankChange: 0);

    // Calculate the number of days until the first game starts for this league round
    List<Game> gamesForLeague = dauRound.getGamesForLeague(leagueHeader);
    DateTime? firstGameStart;
    if (gamesForLeague.isNotEmpty) {
      firstGameStart = gamesForLeague.first.startTimeUTC;
    }

    // Calculate the number of tips outstanding for this league round
    int totalGames = dauRound.getGamesForLeague(leagueHeader).length;
    int tipsSubmitted = daucompsViewModel.selectedTipperTipsViewModel!
        .numberOfTipsSubmittedForRoundAndLeague(dauRound, leagueHeader);

    int tipsOutstanding = totalGames - tipsSubmitted;

    return Card(
      color: Colors.black54,
      //shadowColor: League.nrl.colour,
      surfaceTintColor: League.nrl.colour,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text('Round',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold)),
                    Text('${dauRound.dAUroundNumber}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 30)),
                  ],
                ),
                // if the league round has no games then display an empty container, otherwise display the column of stats
                gamesForLeague.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          dauRound.roundState != RoundState.notStarted
                              ? Text(
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold),
                                  'Score: ${leagueHeader == League.afl ? roundStats.aflScore : roundStats.nrlScore} / ${leagueHeader == League.afl ? roundStats.aflMaxScore : roundStats.nrlMaxScore}')
                              : const SizedBox.shrink(),
                          dauRound.roundState != RoundState.notStarted
                              ? Text(
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold),
                                  'UPS/Margins: ${leagueHeader == League.afl ? roundStats.aflMarginUPS : roundStats.nrlMarginUPS} / ${leagueHeader == League.afl ? roundStats.aflMarginTips : roundStats.nrlMarginTips}')
                              : Column(
                                  children: [
                                    KickoffCountdown(
                                        kickoffDate: firstGameStart!),
                                    Text(
                                      'Tips Outstanding: $tipsOutstanding',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold),
                                        'Your Margins: ${leagueHeader == League.afl ? roundStats.aflMarginTips : roundStats.nrlMarginTips} '),
                                  ],
                                ),
                          dauRound.roundState != RoundState.notStarted
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold),
                                        'Rank: ${roundStats.rank}  '),
                                    roundStats.rankChange > 0
                                        ? const Icon(
                                            color: Colors.green,
                                            Icons.arrow_upward)
                                        : roundStats.rankChange < 0
                                            ? const Icon(
                                                color: Colors.red,
                                                Icons.arrow_downward)
                                            : const Icon(
                                                color: Colors.green,
                                                Icons.sync_alt),
                                    Text(
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold),
                                        '${roundStats.rankChange}'),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ],
                      ),
                SvgPicture.asset(
                  leagueHeader.logo,
                  width: logoWidth,
                  height: logoHeight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
