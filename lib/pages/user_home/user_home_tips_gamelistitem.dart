import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/gametips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gameinfo.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

class GameListItem extends StatefulWidget {
  const GameListItem(
      {super.key,
      required this.roundGames,
      required this.game,
      required this.currentTipper,
      required this.currentDAUComp,
      required this.allTipsViewModel,
      required this.dauRound});

  final List<Game> roundGames; // this is to support legacy tipping service only
  final Game game;
  final Tipper currentTipper;
  final DAUComp currentDAUComp;
  final TipsViewModel allTipsViewModel;
  final DAURound dauRound;

  @override
  State<GameListItem> createState() => _GameListItemState();
}

class _GameListItemState extends State<GameListItem> {
  TipGame? tipGame;
  late final GameTipsViewModel gameTipsViewModel;

  @override
  void initState() {
    super.initState();
    gameTipsViewModel = GameTipsViewModel(
        widget.currentTipper,
        widget.currentDAUComp.dbkey!,
        widget.game,
        widget.allTipsViewModel,
        widget.dauRound);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameTipsViewModel>.value(
      value: gameTipsViewModel,
      child: Consumer<GameTipsViewModel>(
        builder: (context, gameTipsViewModelConsumer, child) {
          Widget gameDetailsCard = Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            color: Colors.lightGreen[100],
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

          if (gameTipsViewModelConsumer.game.gameState ==
                  GameState.notStarted ||
              gameTipsViewModelConsumer.game.gameState ==
                  GameState.startedResultKnown) {
            return gameDetailsCard;
          }

          String bannerMessage;
          Color bannerColor;

          switch (gameTipsViewModelConsumer.game.gameState) {
            case GameState.startingSoon:
              bannerMessage = "Game today";
              bannerColor = Colors.deepOrangeAccent;
              break;
            case GameState.startedResultNotKnown:
              bannerMessage = "Live";
              bannerColor = const Color(0xffe21e31);
              break;
            case GameState.startedResultKnown:
              bannerMessage = "result";
              bannerColor = Colors.transparent;
              break;
            case GameState.notStarted:
              bannerMessage = "not used";
              bannerColor = Colors.purple;
              break;
          }

          // return gameDetailsCard with banner overlay
          return Banner(
            color: bannerColor,
            location: BannerLocation.topEnd,
            message: bannerMessage,
            child: gameDetailsCard,
          );
        },
      ),
    );
  }

  List<Widget> carouselItems(GameTipsViewModel gameTipsViewModelConsumer) {
    if (gameTipsViewModelConsumer.game.gameState == GameState.notStarted ||
        gameTipsViewModelConsumer.game.gameState == GameState.startingSoon) {
      return [
        gameTipCard(gameTipsViewModel),
        GameInfo(gameTipsViewModelConsumer.game, gameTipsViewModel),
      ];
    } else {
      return [
        liveScoringBuilder(
            gameTipsViewModelConsumer), // game is underway or ended - show scoring card
        gameTipCard(gameTipsViewModel),
        GameInfo(gameTipsViewModelConsumer.game, gameTipsViewModel)
      ];
    }
  }

  FutureBuilder<dynamic> liveScoringBuilder(
      GameTipsViewModel gameTipsViewModelConsumer) {
    return FutureBuilder<TipGame?>(
      future: gameTipsViewModelConsumer.gettip(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return LiveScoring(
              tipGame: snapshot.data!,
              gameTipsViewModel: gameTipsViewModelConsumer,
              selectedDAUComp: widget.currentDAUComp);
        } else {
          return CircularProgressIndicator(color: League.afl.colour);
        }
      },
    );
  }

  Widget gameTipCard(GameTipsViewModel gameTipsViewModelConsumer) {
    return TipChoice(widget.roundGames,
        gameTipsViewModel); //roundGames is to support legacy tipping service only
  }
}
