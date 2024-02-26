import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gameinfo.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class GameListItem extends StatelessWidget with WatchItMixin {
  GameListItem({
    super.key,
    required this.roundGames,
    required this.game,
    required this.currentTipper,
    required this.currentDAUCompDBkey,
    required this.allTipsViewModel,
  }) {
    gameTipsViewModel = GameTipsViewModel(
        currentTipper, currentDAUCompDBkey, game, allTipsViewModel);
  }

  final List<Game> roundGames; // this is to support legacy tipping service only
  final Game game;
  final Tipper currentTipper;
  final String currentDAUCompDBkey;
  final AllTipsViewModel allTipsViewModel;

  late final GameTipsViewModel gameTipsViewModel;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: gameTipsViewModel.initialLoadCompleted,
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          } else {
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              color: Colors.grey[300],
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.all(0.0),
                  child: SizedBox(
                    width: 100,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          game.homeTeam.name,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize:
                                16.0, // Adjust this value to make the text bigger or smaller
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              game.homeTeam.logoURI ??
                                  (game.league == League.nrl
                                      ? League.nrl.logo
                                      : League.afl.logo),
                              width: 20,
                              height: 20,
                            ),
                            const Text(textAlign: TextAlign.left, ' V '),
                            SvgPicture.asset(
                              game.awayTeam.logoURI ??
                                  (game.league == League.nrl
                                      ? League.nrl.logo
                                      : League.afl.logo),
                              width: 20,
                              height: 20,
                            ),
                          ],
                        ),
                        Text(
                            style: const TextStyle(
                              fontSize:
                                  16.0, // Adjust this value to make the text bigger or smaller
                            ),
                            textAlign: TextAlign.left,
                            game.awayTeam.name),
                      ],
                    ),
                  ),
                ),
                ChangeNotifierProvider<GameTipsViewModel>(
                    create: (context) => gameTipsViewModel,
                    child: Consumer<GameTipsViewModel>(
                        builder: (context, gameTipsViewModel, child) {
                      return Expanded(
                        child: Column(
                          children: [
                            CarouselSlider(
                              options: CarouselOptions(
                                  height: 120,
                                  enlargeFactor: 1.0,
                                  enlargeCenterPage: true,
                                  enlargeStrategy:
                                      CenterPageEnlargeStrategy.height,
                                  enableInfiniteScroll: false,
                                  onPageChanged: (index, reason) {
                                    gameTipsViewModel.currentIndex = index;
                                  }),
                              items: carouselItems(gameTipsViewModel),
                              carouselController: gameTipsViewModel.controller,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: carouselItems(gameTipsViewModel)
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                return GestureDetector(
                                  onTap: () {
                                    gameTipsViewModel.controller!
                                        .animateToPage(entry.key);
                                  },
                                  child: Container(
                                    width: 6.0,
                                    height: 6.0,
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 2.0, horizontal: 2.0),
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: (Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.white
                                                : Colors.black)
                                            .withOpacity(gameTipsViewModel
                                                        .currentIndex ==
                                                    entry.key
                                                ? 0.9
                                                : 0.4)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    })),
              ]),
            );
          }
        });
  }

  List<Widget> carouselItems(GameTipsViewModel gameTipsViewModel) {
    if (game.gameState == GameState.notStarted) {
      return [
        gameTipCard(gameTipsViewModel),
        GameInfo(game, gameTipsViewModel),
      ];
    } else {
      return [
        gameTipCard(gameTipsViewModel),
        GameInfo(game, gameTipsViewModel),
      ];
    }
  }

  Widget gameTipCard(GameTipsViewModel gameTipsViewModel) {
    return TipChoice(roundGames,
        gameTipsViewModel); //roundGames is to support legacy tipping service only
  }
}
