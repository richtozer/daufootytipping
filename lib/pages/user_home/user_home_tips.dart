import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class TipsPage extends StatelessWidget {
  final Tipper currentTipper;
  final String currentDAUCompDBkey;

  const TipsPage(this.currentTipper, this.currentDAUCompDBkey, {super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => GamesViewModel(currentDAUCompDBkey),
      child: Consumer<GamesViewModel>(
        builder: (context, tipsViewModel, child) {
          return _TipsPageBody(
              currentTipper, tipsViewModel, currentDAUCompDBkey);
        },
      ),
    );
  }
}

class _TipsPageBody extends StatelessWidget {
  final Tipper currentTipper;
  final String currentDAUCompDBkey;
  final GamesViewModel gamesViewModel;

  const _TipsPageBody(
      this.currentTipper, this.gamesViewModel, this.currentDAUCompDBkey);

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Builder(builder: (context) {
      return FutureBuilder<Map<int, List<Game>>>(
        future: gamesViewModel.getNestedGames(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child:
                    CircularProgressIndicator()); // Show loading spinner while waiting for data
          } else if (snapshot.hasError) {
            return Text(
                'Error: ${snapshot.error}'); // Show error message if something went wrong
          } else {
            var nestedGroups = snapshot.data;
            return CustomScrollView(
              slivers: nestedGroups!.entries
                  .map((entry) {
                    var roundNumber = entry.key;
                    var games = entry.value;
                    return [
                      SliverAppBar(
                        pinned: false,
                        floating: true,
                        snap: false,
                        expandedHeight: 100.0,
                        flexibleSpace: FlexibleSpaceBar(
                            titlePadding: const EdgeInsetsDirectional.only(
                                start: 180.0, bottom: 0.0),
                            //centerTitle: true,
                            background: Image.asset(
                              'assets/teams/daulogo.jpg',
                              fit: BoxFit.fill,
                            ),
                            title: Text(
                              'R o u n d : $roundNumber',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            )),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) {
                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(0.0),
                              ),
                              color: Colors.grey[300],
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  children: [
                                    ListTile(
                                      title: Text(
                                          '${games[index].homeTeam.name} v ${games[index].awayTeam.name}'),
                                      subtitle: Text(
                                          '${DateFormat('EEE dd MMM hh:mm a').format(games[index].startTimeUTC.toLocal())} - ${games[index].location}'),
                                      trailing: SvgPicture.asset(
                                        games[index].league.logo,
                                        width: 30,
                                        height: 30,
                                      ),
                                    ),
                                    ChangeNotifierProvider<GameTipsViewModel>(
                                      create: (context) => GameTipsViewModel(
                                          currentTipper,
                                          currentDAUCompDBkey,
                                          games[index]),
                                      child: Consumer<GameTipsViewModel>(
                                        builder: (context, gameTipsViewModel,
                                            child) {
                                          return BuildChoiceChips(
                                              gameTipsViewModel);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: games.length,
                        ),
                      ),
                    ];
                  })
                  .toList()
                  .expand((element) => element)
                  .toList(),
            );
          }
        },
      );
    }));
  }
}
