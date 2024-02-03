import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

class TipsPage extends StatelessWidget {
  final Tipper currentTipper;
  final String currentDAUCompDBkey;

  const TipsPage(this.currentTipper, this.currentDAUCompDBkey, {super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => GamesViewModel(currentDAUCompDBkey),
      child: Consumer<GamesViewModel>(
        builder: (context, gamesViewModel, child) {
          return _TipsPageBody(
              currentTipper, gamesViewModel, currentDAUCompDBkey);
        },
      ),
    );
  }
}

class _TipsPageBody extends StatefulWidget {
  final Tipper currentTipper;
  final String currentDAUCompDBkey;
  final GamesViewModel gamesViewModel;

  const _TipsPageBody(
      this.currentTipper, this.gamesViewModel, this.currentDAUCompDBkey);

  @override
  State<_TipsPageBody> createState() => _TipsPageBodyState();
}

class _TipsPageBodyState extends State<_TipsPageBody> {
  final ScrollController controller = ScrollController();

  @override
  void initState() {
    super.initState();

    /*WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        double itemHeight = 100; // Replace with your actual item height
        int index = 5; // Replace with your actual index

        controller.animateTo(
          index * itemHeight,
          duration: const Duration(seconds: 1),
          curve: Curves.easeInOut,
        );
      }
    });
    */
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: widget.gamesViewModel.getCombinedRoundNumbers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          var combinedRoundNumbers = snapshot.data;
          return ListView.builder(
            controller: controller,
            itemCount: combinedRoundNumbers?.length,
            itemBuilder: (context, index) {
              var combinedRoundNumber = combinedRoundNumbers?[index];
              return Column(
                children: [
                  /*SliverAppBar(
                    pinned: false,
                    floating: true,
                    snap: false,
                    expandedHeight: 100.0,
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: const EdgeInsetsDirectional.only(
                          start: 150.0, bottom: 0.0),
                      //centerTitle: true,
                      background: Image.asset(
                        'assets/teams/daulogo.jpg',
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),*/
                  ListTile(
                    trailing: SvgPicture.asset(
                      League.nrl.logo,
                      width: 30,
                      height: 30,
                    ),
                    title: Container(
                      alignment: Alignment.center,
                      child: const Text('N R L'),
                    ),
                    subtitle: Container(
                      alignment: Alignment.center,
                      child: Text('DAU R o u n d: $combinedRoundNumber'),
                    ),
                  ), // Header for NRL section
                  FutureBuilder<List<Game>>(
                    future: widget.gamesViewModel
                        .getGamesForCombinedRoundNumberAndLeague(
                            combinedRoundNumber!, League.nrl),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      } else {
                        var games = snapshot.data;
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: games?.length,
                          itemBuilder: (context, index) {
                            var game = games?[index];
                            return GameListItem(
                                roundGames:
                                    games!, //pass all games for this league/round to the GameListItem  - this is to support legacy tipping only
                                game: game!,
                                currentTipper: widget.currentTipper,
                                currentDAUCompDBkey:
                                    widget.currentDAUCompDBkey);
                          },
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: SvgPicture.asset(
                      League.afl.logo,
                      width: 30,
                      height: 30,
                    ),
                    title: const Text('A F L'),
                    subtitle: Text('DAU R o u n d: $combinedRoundNumber'),
                  ),
                  FutureBuilder<List<Game>>(
                    future: widget.gamesViewModel
                        .getGamesForCombinedRoundNumberAndLeague(
                            combinedRoundNumber, League.afl),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      } else {
                        var games = snapshot.data;
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: games?.length,
                          itemBuilder: (context, index) {
                            var game = games?[index];
                            return GameListItem(
                                roundGames: games!,
                                game: game!,
                                currentTipper: widget.currentTipper,
                                currentDAUCompDBkey:
                                    widget.currentDAUCompDBkey);
                          },
                        );
                      }
                    },
                  ),
                ],
              );
            },
          );
        }
      },
    );
  }
}
