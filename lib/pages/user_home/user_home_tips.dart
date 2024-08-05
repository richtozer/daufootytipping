import 'dart:developer';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
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
      log('TipsPageBody.build() selectedDAUComp is null');
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
                'Nothing to see here. Contact a DAU Admin.',
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
            initialAlignment:
                0.15, // peek at the last game in the previous round
            // Increase itemCount by 1 to account for the final "end of competition" item
            itemCount: daucompsViewmodelConsumer
                        .selectedDAUComp!.daurounds.length *
                    4 +
                1, // 4 items per round plus 1 for the end of competition card
            itemBuilder: (context, index) {
              // Check if this is the last item
              if (index ==
                  daucompsViewmodelConsumer.selectedDAUComp!.daurounds.length *
                      4) {
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
                  tipperTipsViewModel:
                      daucompsViewmodelConsumer.tipperTipsViewModel!,
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
                  tipperTipsViewModel:
                      daucompsViewmodelConsumer.tipperTipsViewModel,
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
      ScoresViewModel? scoresViewmodelConsumer) {
    RoundScores? roundScores;

    var selectedTipperScores = scoresViewmodelConsumer
        ?.allTipperRoundScores[di<TippersViewModel>().selectedTipper];

    if (selectedTipperScores != null) {
      roundScores = selectedTipperScores[dauRound.dAUroundNumber - 1];
    } else {
      roundScores = null; // Or assign a default value if appropriate.
    }
    return Card(
      color: Colors.black54,
      //shadowColor: League.nrl.colour,
      surfaceTintColor: League.nrl.colour,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                const Text('Round',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.bold)),
                Text('${dauRound.dAUroundNumber}',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 30)),
              ],
            ),
            Column(
              children: [
                dauRound.roundState != RoundState.notStarted
                    ? Text(
                        style: const TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.bold),
                        'Score: ${leagueHeader == League.afl ? roundScores?.aflScore : roundScores?.nrlScore} / ${leagueHeader == League.afl ? roundScores?.aflMaxScore : roundScores?.nrlMaxScore}')
                    : const SizedBox.shrink(),
                dauRound.roundState != RoundState.notStarted
                    ? Text(
                        style: const TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.bold),
                        'Margins/ups: ${leagueHeader == League.afl ? roundScores?.aflMarginTips : roundScores?.nrlMarginTips} / ${leagueHeader == League.afl ? roundScores?.aflMarginUPS : roundScores?.nrlMarginUPS}')
                    : Text(
                        style: const TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.bold),
                        'Margins: ${leagueHeader == League.afl ? roundScores?.aflMarginTips ?? 0 : roundScores?.nrlMarginTips ?? 0} '),
                dauRound.roundState != RoundState.notStarted
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold),
                              'Rank: ${roundScores?.rank}  '),
                          roundScores == null
                              ? const Icon(
                                  Icons.question_mark,
                                  color: Colors.grey,
                                )
                              : roundScores.rankChange > 0
                                  ? const Icon(
                                      color: Colors.green, Icons.arrow_upward)
                                  : roundScores.rankChange < 0
                                      ? const Icon(
                                          color: Colors.red,
                                          Icons.arrow_downward)
                                      : const Icon(
                                          color: Colors.green, Icons.sync_alt),
                          Text(
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold),
                              '${roundScores?.rankChange}'),
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
    );
  }
}
