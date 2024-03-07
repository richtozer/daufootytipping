import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gameinfo.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

class GameListItem extends StatefulWidget {
  const GameListItem({
    super.key,
    required this.roundGames,
    required this.game,
    required this.currentTipper,
    required this.currentDAUCompDBkey,
    required this.allTipsViewModel,
  });

  final List<Game> roundGames; // this is to support legacy tipping service only
  final Game game;
  final Tipper currentTipper;
  final String currentDAUCompDBkey;
  final AllTipsViewModel allTipsViewModel;

  @override
  State<GameListItem> createState() => _GameListItemState();
}

class _GameListItemState extends State<GameListItem> {
  TipGame? tipGame;
  late final GameTipsViewModel gameTipsViewModel;

  @override
  void initState() {
    gameTipsViewModel = GameTipsViewModel(widget.currentTipper,
        widget.currentDAUCompDBkey, widget.game, widget.allTipsViewModel);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameTipsViewModel>.value(
      value: gameTipsViewModel,
      child: Consumer<GameTipsViewModel>(
        builder: (context, gameTipsViewModelConsumer, child) {
          Widget card = Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
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
                        widget.game.homeTeam.name,
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
                            widget.game.homeTeam.logoURI ??
                                (widget.game.league == League.nrl
                                    ? League.nrl.logo
                                    : League.afl.logo),
                            width: 20,
                            height: 20,
                          ),
                          const Text(textAlign: TextAlign.left, ' V '),
                          SvgPicture.asset(
                            widget.game.awayTeam.logoURI ??
                                (widget.game.league == League.nrl
                                    ? League.nrl.logo
                                    : League.afl.logo),
                            width: 20,
                            height: 20,
                          ),
                        ],
                      ),
                      Text(
                          style: const TextStyle(
                            fontSize: 16.0,
                          ),
                          textAlign: TextAlign.left,
                          widget.game.awayTeam.name),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    CarouselSlider(
                      options: CarouselOptions(
                          height: 120,
                          enlargeFactor: 1.0,
                          enlargeCenterPage: true,
                          enlargeStrategy: CenterPageEnlargeStrategy.zoom,
                          enableInfiniteScroll: false,
                          onPageChanged: (index, reason) {
                            gameTipsViewModelConsumer.currentIndex = index;
                          }),
                      items: carouselItems(gameTipsViewModelConsumer),
                      carouselController: gameTipsViewModelConsumer.controller,
                    ),
                  ],
                ),
              )
            ]),
          );

          if (widget.game.gameState == GameState.notStarted) {
            return card;
          }

          String bannerMessage;
          Color bannerColor;

          switch (widget.game.gameState) {
            case GameState.resultNotKnown:
              bannerMessage = "Live";
              bannerColor = Color(0xffe21e31);
              break;
            case GameState.resultKnown:
              bannerMessage = "Result";
              bannerColor = Colors.grey;
              break;
            case GameState.notStarted:
              bannerMessage = "Not Started";
              bannerColor = Colors.grey;
              break;
          }

          return Banner(
            color: bannerColor,
            location: BannerLocation.topEnd,
            message: bannerMessage,
            child: card,
          );
        },
      ),
    );
  }

  Widget build2(BuildContext context) {
    return ChangeNotifierProvider<GameTipsViewModel>.value(
        value: gameTipsViewModel,
        child: Consumer<GameTipsViewModel>(
            builder: (context, gameTipsViewModelConsumer, child) {
          return Banner(
            color: Colors.white54,
            location: BannerLocation.topEnd,
            message: "Ended",
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
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
                          widget.game.homeTeam.name,
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
                              widget.game.homeTeam.logoURI ??
                                  (widget.game.league == League.nrl
                                      ? League.nrl.logo
                                      : League.afl.logo),
                              width: 20,
                              height: 20,
                            ),
                            const Text(textAlign: TextAlign.left, ' V '),
                            SvgPicture.asset(
                              widget.game.awayTeam.logoURI ??
                                  (widget.game.league == League.nrl
                                      ? League.nrl.logo
                                      : League.afl.logo),
                              width: 20,
                              height: 20,
                            ),
                          ],
                        ),
                        Text(
                            style: const TextStyle(
                              fontSize: 16.0,
                            ),
                            textAlign: TextAlign.left,
                            widget.game.awayTeam.name),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      CarouselSlider(
                        options: CarouselOptions(
                            height: 120,
                            enlargeFactor: 1.0,
                            enlargeCenterPage: true,
                            enlargeStrategy: CenterPageEnlargeStrategy.zoom,
                            enableInfiniteScroll: false,
                            onPageChanged: (index, reason) {
                              gameTipsViewModelConsumer.currentIndex = index;
                            }),
                        items: carouselItems(gameTipsViewModelConsumer),
                        carouselController:
                            gameTipsViewModelConsumer.controller,
                      ),
                    ],
                  ),
                )
              ]),
            ),
          );
        }));
  }

  List<Widget> carouselItems(GameTipsViewModel gameTipsViewModel) {
    if (widget.game.gameState == GameState.notStarted) {
      return [
        gameTipCard(gameTipsViewModel),
        GameInfo(widget.game, gameTipsViewModel),
      ];
    } else {
      return [
        liveScoringBuilder(
            gameTipsViewModel), // game is underway or ended - show scoring card
        gameTipCard(gameTipsViewModel),
        GameInfo(widget.game, gameTipsViewModel)
      ];
    }
  }

  FutureBuilder<dynamic> liveScoringBuilder(
      GameTipsViewModel gameTipsViewModel) {
    return FutureBuilder<TipGame?>(
      future: gameTipsViewModel.gettip(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return LiveScoring(
              tipGame: snapshot.data!, gameTipsViewModel: gameTipsViewModel);
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return const CircularProgressIndicator();
        }
      },
    );
  }

  Widget gameTipCard(GameTipsViewModel gameTipsViewModel) {
    return TipChoice(widget.roundGames,
        gameTipsViewModel); //roundGames is to support legacy tipping service only
  }
}
