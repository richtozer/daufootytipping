import 'package:carousel_slider/carousel_slider.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
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

//NRL AFL gradients
var nrlAflColourGradient = const LinearGradient(
  colors: [Color(0xff04cf5d), Color(0xffe21e31)],
  stops: [0.25, 0.75],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

var nrlColourGradient = const LinearGradient(
  colors: [Color(0xff04cf5d), Color(0xffffffff)],
  stops: [0.05, 0.2],
  begin: Alignment.bottomRight,
  end: Alignment.topLeft,
);

const LinearGradient nrlWarriors = LinearGradient(
  colors: [Color(0xff252b67), Color(0xff008446)],
  stops: [0.25, 0.75],
  begin: Alignment.bottomRight,
  end: Alignment.topLeft,
);

class _GameListItemState extends State<GameListItem> {
  int _current = 0;
  final CarouselController _controller = CarouselController();
  @override
  Widget build(BuildContext context) {
    return Card(
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
                Text(textAlign: TextAlign.left, widget.game.homeTeam.name),
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
                Text(textAlign: TextAlign.left, widget.game.awayTeam.name),
              ],
            ),
          ),
        ),
        ChangeNotifierProvider<GameTipsViewModel>(
          create: (context) => GameTipsViewModel(
              widget.currentTipper, widget.currentDAUCompDBkey, widget.game),
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
                            _controller.animateToPage(entry.key);
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
        ),
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
        FutureBuilder<Tip?>(
          future: gameTipsViewModel.getLatestGameTip(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return LiveScoring(tip: snapshot.data!);
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else {
              return CircularProgressIndicator();
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
}
