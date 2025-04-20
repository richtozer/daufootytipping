import 'dart:developer';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
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

class TipsTab2 extends StatefulWidget {
  const TipsTab2({super.key});

  @override
  TipsTab2State createState() => TipsTab2State();
}

class TipsTab2State extends State<TipsTab2> {
  DAUCompsViewModel daucompsViewModel = di<DAUCompsViewModel>();

  int latestRoundNumber = 0;
  late ScrollController scrollController;
  late FocusNode focusNode;
  int initialScrollOffset = -150;

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

    focusNode = FocusNode();

    scrollController = ScrollController(
        initialScrollOffset: daucompsViewModel.selectedDAUComp!
                .pixelHeightUpToRound(latestRoundNumber) +
            initialScrollOffset);
  }

  void _handleKeyEvent(KeyEvent event) {
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
    log('TipsPageBody.build()');

    if (daucompsViewModel.selectedDAUComp == null) {
      log('TipsPageBody.build() selectedDAUComp is null. Trying to change to active comp');
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
                  'Nothing to see here.\nContact daufootytipping@gmail.com.',
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
      onKeyEvent: _handleKeyEvent,
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
            return CustomScrollView(
              controller: scrollController,
              restorationId: 'tipsListView',
              slivers: [
                SliverVariedExtentList.builder(
                  itemExtentBuilder: (index, dimensions) {
                    if (index == 0) {
                      return WelcomeHeader.height;
                    } else if (index ==
                        (daucompsViewmodelConsumer
                                    .selectedDAUComp!.daurounds.length *
                                4) +
                            1) {
                      return EndFooter.height;
                    }
                    final roundIndex = (index - 1) ~/ 4;
                    final itemIndex = (index - 1) % 4;
                    return _getItemExtent(
                        daucompsViewmodelConsumer, roundIndex, itemIndex);
                  },
                  itemCount: (daucompsViewmodelConsumer
                              .selectedDAUComp!.daurounds.length *
                          4) +
                      1 +
                      1,
                  itemBuilder: (context, index) {
                    log('building index: $index');
                    if (index == 0) {
                      return WelcomeHeader(
                          daucompsViewmodelConsumer: daucompsViewmodelConsumer);
                    }
                    if (index ==
                        (daucompsViewmodelConsumer
                                    .selectedDAUComp!.daurounds.length *
                                4) +
                            1) {
                      return const EndFooter();
                    }

                    final roundIndex = (index - 1) ~/ 4;
                    final itemIndex = (index - 1) % 4;
                    final dauRound = daucompsViewmodelConsumer
                        .selectedDAUComp!.daurounds[roundIndex];

                    return _buildItem(
                        daucompsViewmodelConsumer, dauRound, itemIndex);
                  },
                ),
              ],
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
      DAURound dauRound, int itemIndex) {
    if (itemIndex == 0 || itemIndex == 2) {
      final league = itemIndex == 0 ? League.nrl : League.afl;
      return Consumer<StatsViewModel?>(
          builder: (context, scoresViewmodelConsumer, client) {
        return roundLeagueHeaderListTile(league, 50, 50, dauRound,
            daucompsViewmodelConsumer, scoresViewmodelConsumer);
      });
    } else if (itemIndex == 1 || itemIndex == 3) {
      final league = itemIndex == 1 ? League.nrl : League.afl;
      return GameListBuilder(
        currentTipper: di<TippersViewModel>().selectedTipper,
        dauRound: dauRound,
        league: league,
        tipperTipsViewModel:
            daucompsViewmodelConsumer.selectedTipperTipsViewModel!,
        dauCompsViewModel: daucompsViewmodelConsumer,
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

class EndFooter extends StatelessWidget {
  const EndFooter({super.key});

  static const double height = 75;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
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
}

class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({
    required this.daucompsViewmodelConsumer,
    super.key,
  });

  final DAUCompsViewModel daucompsViewmodelConsumer;

  static const double height = 200;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
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
              const Spacer(),
              const Spacer(),
              const Spacer(),
              const Spacer(),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const Icon(Icons.sports_rugby, color: Colors.white70),
                  Text(
                    'Start of competition\n${daucompsViewmodelConsumer.selectedDAUComp!.name}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Icon(Icons.sports_rugby, color: Colors.white70),
                ],
              ),
              const Spacer(),
              const Text(
                'New here? You will find instructions and scoring information in the [Help...] section on the Profile Tab.',
                style: TextStyle(color: Colors.white70),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
