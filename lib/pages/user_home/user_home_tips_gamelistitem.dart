import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
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
  });

  final List<Game> roundGames; // this is to support legacy tipping service only
  final Game game;
  final Tipper currentTipper;
  final String currentDAUCompDBkey;

  @override
  State<GameListItem> createState() => _GameListItemState();
}

class _GameListItemState extends State<GameListItem> {
  int _current = 0;
  CarouselController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = CarouselController();
  }

  @override
  Widget build(BuildContext context) {
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
                      fontSize:
                          16.0, // Adjust this value to make the text bigger or smaller
                    ),
                    textAlign: TextAlign.left,
                    widget.game.awayTeam.name),
              ],
            ),
          ),
        ),
        Consumer<DAUCompsViewModel>(builder: (context, dcvm2, child) {
          return ChangeNotifierProvider<GameTipsViewModel>(
            create: (context) => GameTipsViewModel(
                widget.currentTipper, dcvm2.selectedDAUCompDbKey, widget.game),
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
                            enlargeStrategy: CenterPageEnlargeStrategy.height,
                            enableInfiniteScroll: false,
                            onPageChanged: (index, reason) {
                              setState(() {
                                _current = index;
                              });
                            }),
                        items: carouselItems(gameTipsViewModel),
                        carouselController: _controller,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: carouselItems(gameTipsViewModel)
                            .asMap()
                            .entries
                            .map((entry) {
                          return GestureDetector(
                            onTap: () {
                              _controller!.animateToPage(entry.key);
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
                                      .withOpacity(
                                          _current == entry.key ? 0.9 : 0.4)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        })
      ]),
    );
  }

  List<Widget> carouselItems(GameTipsViewModel gameTipsViewModel) {
    if (widget.game.gameState == GameState.notStarted) {
      return [
        gameTipCard(),
        GameInfo(widget: widget, gameTipsViewModel: gameTipsViewModel),
      ];
    } else {
      return [
        FutureBuilder<TipGame?>(
          future: gameTipsViewModel.getLatestGameTip(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return LiveScoring(tipGame: snapshot.data!);
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else {
              return const Text('wait....');
              //const CircularProgressIndicator();
            }
          },
        ),
        gameTipCard(),
        GameInfo(widget: widget, gameTipsViewModel: gameTipsViewModel),
      ];
    }
  }

  Consumer<GameTipsViewModel> gameTipCard() {
    return Consumer<GameTipsViewModel>(
      builder: (context, gameTipsViewModel, child) {
        final gameTip = gameTipsViewModel.getLatestGameTip();
        // Use gameTip in your widget
        return TipChoice(widget.roundGames, gameTip,
            gameTipsViewModel); //roundGames is to support legacy tipping service only
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
