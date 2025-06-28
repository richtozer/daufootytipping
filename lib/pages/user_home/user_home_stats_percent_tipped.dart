import 'dart:developer';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_round_leagueheader_listtile.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class StatPercentTipped extends StatefulWidget {
  const StatPercentTipped({super.key});

  @override
  StatPercentTippedState createState() => StatPercentTippedState();
}

class StatPercentTippedState extends State<StatPercentTipped> {
  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();

  int latestRoundNumber = 0;
  late ScrollController scrollController;
  late FocusNode focusNode;
  int initialScrollOffset = -150;

  @override
  void initState() {
    log('StatPercentTipped.constructor()');
    super.initState();

    if (daucompsViewModel.selectedDAUComp == null) {
      log('StatPercentTipped.initState() selectedDAUComp is null');
      return;
    }

    latestRoundNumber =
        daucompsViewModel.selectedDAUComp!.highestRoundNumberInPast();
    log('StatPercentTipped.initState() latestRoundNumber: $latestRoundNumber');

    focusNode = FocusNode();

    scrollController = ScrollController(
        initialScrollOffset: daucompsViewModel.selectedDAUComp!
                .pixelHeightUpToRound(latestRoundNumber) +
            initialScrollOffset);
  }

  void _handleKeyEvent(KeyEvent event, BuildContext context) {
    if (event is KeyDownEvent) {
      final double viewportHeight = MediaQuery.of(context).size.height;

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _scrollBy(100);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _scrollBy(-100);
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        _scrollBy(300);
      } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
        _scrollBy(viewportHeight);
      } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
        _scrollBy(-viewportHeight);
      }
    }
  }

  void _scrollBy(double offset) {
    scrollController.animateTo(
      scrollController.offset + offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    log('StatPercentTipped.build()');

    Orientation orientation = MediaQuery.of(context).orientation;

    if (daucompsViewModel.selectedDAUComp == null) {
      log('StatPercentTipped.build() selectedDAUComp is null. Trying to change to active comp');
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
              child: Center(
                child: Text(
                  'Nothing to see here.\nContact support: https://interview.coach/tipping.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        );
      }
    }

    return KeyboardListener(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: (event) => _handleKeyEvent(event, context),
      child: MultiProvider(
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
            return Scaffold(
              floatingActionButton: FloatingActionButton(
                backgroundColor: Colors.lightGreen[200],
                foregroundColor: Colors.white70,
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Icon(Icons.arrow_back),
              ),
              body: Column(mainAxisSize: MainAxisSize.min, children: [
                orientation == Orientation.portrait
                    ? const HeaderWidget(
                        text: 'Percentage Tipped',
                        leadingIconAvatar: Hero(
                          tag: 'percentage',
                          child: Icon(Icons.percent, size: 40),
                        ),
                      )
                    : Container(),
                orientation == Orientation.portrait
                    ? Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: Text(
                            'This is a breakdown of how people tipped previous games. Each % represents the number of people who tipped this outcome. Legend: 🟩 = Your tip, 🏆 = Game result.',
                            style: const TextStyle(
                              fontSize: 14,
                            )),
                      )
                    : Container(), //
                Expanded(
                  child: CustomScrollView(
                    controller: scrollController,
                    restorationId: 'statsPercentTippedView',
                    slivers: [
                      SliverVariedExtentList.builder(
                        itemExtentBuilder: (index, dimensions) {
                          final roundIndex = (index) ~/ 4;
                          final itemIndex = (index) % 4;
                          return _getItemExtent(
                              daucompsViewmodelConsumer, roundIndex, itemIndex);
                        },
                        itemCount: (latestRoundNumber * 4),
                        itemBuilder: (context, index) {
                          log('StatPercentTipped building index: $index');
                          final roundIndex = (index) ~/ 4;
                          final itemIndex = (index) % 4;

                          return _buildItem(
                              daucompsViewmodelConsumer, roundIndex, itemIndex);
                        },
                      ),
                    ],
                  ),
                ),
              ]),
            );
          }),
        ),
      ),
    );
  }

  double? _getItemExtent(DAUCompsViewModel daucompsViewmodelConsumer,
      int roundIndex, int itemIndex) {
    if (itemIndex == 0 || itemIndex == 2) {
      final league = itemIndex == 0 ? League.nrl : League.afl;
      final games = daucompsViewmodelConsumer
          .selectedDAUComp!.daurounds[roundIndex]
          .getGamesForLeague(league);
      if (games.isEmpty) {
        return DAURound.leagueHeaderHeight;
      } else if (daucompsViewmodelConsumer
              .selectedDAUComp!.daurounds[roundIndex].roundState ==
          RoundState.allGamesEnded) {
        return DAURound.leagueHeaderEndedHeight;
      }
      return DAURound.leagueHeaderHeight;
    } else if (itemIndex == 1 || itemIndex == 3) {
      final league = itemIndex == 1 ? League.nrl : League.afl;
      final games = daucompsViewmodelConsumer
          .selectedDAUComp!.daurounds[roundIndex]
          .getGamesForLeague(league);
      if (games.isEmpty) {
        return DAURound.noGamesCardheight;
      }
      return games.length * Game.gameCardHeight;
    }
    return null;
  }

  Widget _buildItem(DAUCompsViewModel daucompsViewmodelConsumer,
      int roundIndex, int itemIndex) {
    final dauRound = daucompsViewmodelConsumer.selectedDAUComp!.daurounds[roundIndex];
    
    if (itemIndex == 0 || itemIndex == 2) {
      final league = itemIndex == 0 ? League.nrl : League.afl;
      return roundLeagueHeaderListTile(
          league,
          50,
          50,
          dauRound,
          daucompsViewmodelConsumer,
          di<TippersViewModel>().selectedTipper,
          true);
    } else if (itemIndex == 1 || itemIndex == 3) {
      final league = itemIndex == 1 ? League.nrl : League.afl;
      return GameListBuilder(
        currentTipper: di<TippersViewModel>().selectedTipper,
        roundIndex: roundIndex,
        league: league,
        tipperTipsViewModel:
            daucompsViewmodelConsumer.selectedTipperTipsViewModel!,
        dauCompsViewModel: daucompsViewmodelConsumer,
        isPercentStatsPage: true,
      );
    }
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
