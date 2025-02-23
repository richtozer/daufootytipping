import 'dart:developer';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_roundLeagueHeaderListTile.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class TipsTabWeb extends StatefulWidget {
  const TipsTabWeb({super.key});

  @override
  TipsTabWebState createState() => TipsTabWebState();
}

class TipsTabWebState extends State<TipsTabWeb> {
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
      log('TipsPageBody.build() selectedDAUComp is null. Trying to change to active comp');
      // try changing to the active comp
      daucompsViewModel.changeDisplayedDAUComp(
          daucompsViewModel.activeDAUComp!, false);
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
                  'Nothing to see here.\nContact daufootytipping@gmail.com.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        );
      }
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DAUCompsViewModel>.value(
            value: daucompsViewModel),
        ChangeNotifierProvider<StatsViewModel?>.value(
            value: daucompsViewModel.statsViewModel),
      ],
      child: Theme(
        data: myTheme,
        child: Consumer<DAUCompsViewModel>(
            builder: (context, daucompsViewmodelConsumer, client) {
          return ListView.builder(
            primary: true,
            //itemScrollController:
            //    daucompsViewmodelConsumer.itemScrollController,
            //initialScrollIndex: (latestRoundNumber) * 4,
            //initialAlignment:
            //    0.15, // peek at the last game in the previous round

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
                                'WEB Start of competition\n${daucompsViewmodelConsumer.selectedDAUComp!.name}',
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
                  return roundLeagueHeaderListTile(League.nrl, 50, 50, dauRound,
                      daucompsViewmodelConsumer, scoresViewmodelConsumer);
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
                  return roundLeagueHeaderListTile(League.afl, 40, 40, dauRound,
                      daucompsViewmodelConsumer, scoresViewmodelConsumer);
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
}
