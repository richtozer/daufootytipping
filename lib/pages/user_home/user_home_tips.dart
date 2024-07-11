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

class TipsPage extends StatefulWidget {
  const TipsPage({super.key});

  @override
  TipsPageState createState() => TipsPageState();
}

class TipsPageState extends State<TipsPage> {
  final String currentDAUCompDbkey =
      di<DAUCompsViewModel>().selectedDAUComp!.dbkey!;
  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();
  int latestRoundNumber = 1;

  @override
  void initState() {
    log('TipsPageBody.constructor()');
    super.initState();

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
            // Increase itemCount by 1 to account for the final "end of competition" item
            itemCount:
                daucompsViewmodelConsumer.selectedDAUComp!.daurounds.length *
                        4 +
                    1,
            itemBuilder: (context, index) {
              // Check if this is the last item
              if (index ==
                  daucompsViewmodelConsumer.selectedDAUComp!.daurounds.length *
                      4) {
                // Return a widget indicating the end of the competition
                return const Padding(
                  padding: EdgeInsets.all(10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag, color: Colors.white),
                      Text("This is the end of the competition",
                          style: TextStyle(color: Colors.white)),
                      Icon(Icons.flag, color: Colors.white),
                    ],
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
                          'Margins: ${leagueHeader == League.afl ? roundScores?.aflMarginTips : roundScores?.nrlMarginTips} / UPS: ${leagueHeader == League.afl ? roundScores?.aflMarginUPS : roundScores?.nrlMarginUPS}')
                      : Text(
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          'Margins: ${leagueHeader == League.afl ? roundScores?.aflMarginTips : roundScores?.nrlMarginTips} '),
                  dauRound.roundState != RoundState.notStarted
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                style: const TextStyle(
                                    color: Colors.white,
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
                                            color: Colors.green,
                                            Icons.sync_alt),
                            Text('${roundScores?.rankChange}'),
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
