import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/tips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class TipsPage extends StatefulWidget {
  final Tipper currentTipper;

  const TipsPage(this.currentTipper, {super.key}); // Remove the extra argument.

  @override
  State<TipsPage> createState() => _TipsPageState();
}

class _TipsPageState extends State<TipsPage>
    with AutomaticKeepAliveClientMixin<TipsPage> {
  @override
  bool get wantKeepAlive => true;

  Tipper getCurrentTipper() {
    return widget.currentTipper;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Consumer<TipsViewModel>(builder: (context, tipsViewModel, child) {
        return FutureBuilder<Map<int, List<Game>>>(
          future: tipsViewModel.gamesViewModel.getNestedGames(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator(); // Show loading spinner while waiting for data
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              )),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (BuildContext context, int index) {
                              return Card(
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
                                      BuildChoiceChips(tipsViewModel,
                                          games[index], getCurrentTipper()),
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
      }),
    );
  }
}
