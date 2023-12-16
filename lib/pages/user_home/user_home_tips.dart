import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/appstate_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/tips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_tipchoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class TipsPage extends StatefulWidget {
  const TipsPage({super.key});

  @override
  State<TipsPage> createState() => _TipsPageState();
}

class _TipsPageState extends State<TipsPage> {
  final bucket = PageStorageBucket();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<TipsViewModel>(builder: (context, tipsViewModel, child) {
        return FutureBuilder<Map<int, List<Game>>>(
          future: tipsViewModel.gamesViewModel.nestedGames,
          builder: (context, snapshot) {
            final appStateNotifier =
                Provider.of<AppState>(context, listen: false);
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator(); // Show loading spinner while waiting for data
            } else if (snapshot.hasError) {
              return Text(
                  'Error: ${snapshot.error}'); // Show error message if something went wrong
            } else {
              var nestedGroups = snapshot.data;
              return PageStorage(
                bucket: bucket, //TODO this is not working, investigate
                child: CustomScrollView(
                  //key: const PageStorageKey<String>('myScrollableList'),
                  slivers: <Widget>[
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (BuildContext context, int index) {
                          var combinedRoundNumber =
                              nestedGroups.keys.elementAt(index);
                          var games = nestedGroups[combinedRoundNumber];

                          return ExpansionTile(
                            initiallyExpanded:
                                appStateNotifier.expandedStates[index],
                            onExpansionChanged: (bool expanded) {
                              setState(() {
                                appStateNotifier.expandedStates[index] =
                                    expanded;
                              });
                            },
                            title: FutureBuilder<int>(
                              future: tipsViewModel
                                  .countTipsOutstanding(combinedRoundNumber),
                              builder: (BuildContext context,
                                  AsyncSnapshot<int> snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const CircularProgressIndicator();
                                } else if (snapshot.hasError) {
                                  return Text('Error: ${snapshot.error}');
                                } else {
                                  return Text(
                                      'Round: $combinedRoundNumber Tipped: ${snapshot.data} / ${games!.length}');
                                }
                              },
                            ),
                            children: [
                              ExpansionTile(
                                initiallyExpanded:
                                    appStateNotifier.expandedStates[index + 1],
                                onExpansionChanged: (bool expanded) {
                                  setState(() {
                                    appStateNotifier.expandedStates[index + 1] =
                                        expanded;
                                  });
                                },
                                leading: SvgPicture.asset(
                                  League.nrl.logo,
                                  height: 20.0,
                                  width: 20.0,
                                  fit: BoxFit
                                      .contain, // This makes sure the whole SVG fits within the bounds
                                ),
                                title: const Text('N R L'),
                                children: games!
                                    .where((game) => game.league == League.nrl)
                                    .map((game) {
                                  return Column(
                                    children: [
                                      ListTile(
                                        title: Text(
                                            '${game.homeTeam.name} v ${game.awayTeam.name}'),
                                        subtitle: Text(
                                            '${DateFormat('EEE dd MMM hh:mm a').format(game.startTimeUTC.toLocal())} - ${game.location}'),
                                        // Add more properties of the game as needed
                                      ),
                                      BuildChoiceChips(tipsViewModel,
                                          game), // Add your custom widget here
                                    ],
                                  );
                                }).toList(),
                              ),
                              ExpansionTile(
                                initiallyExpanded:
                                    appStateNotifier.expandedStates[index + 2],
                                onExpansionChanged: (bool expanded) {
                                  setState(() {
                                    appStateNotifier.expandedStates[index + 2] =
                                        expanded;
                                  });
                                },
                                title: const Text('A F L'),
                                leading: SvgPicture.asset(
                                  League.afl.logo,
                                  height: 20.0,
                                  width: 20.0,
                                  fit: BoxFit
                                      .contain, // This makes sure the whole SVG fits within the bounds
                                ),
                                children: games
                                    .where((game) => game.league == League.afl)
                                    .map((game) {
                                  return Column(
                                    children: [
                                      ListTile(
                                        title: Text(
                                            '${game.homeTeam.name} v ${game.awayTeam.name}'),
                                        subtitle: Text(
                                            '${DateFormat('EEE dd MMM hh:mm a').format(game.startTimeUTC.toLocal())} - ${game.location}'),
                                        // Add more properties of the game as needed
                                      ),
                                      BuildChoiceChips(tipsViewModel,
                                          game), // Add your custom widget here
                                    ],
                                  );
                                }).toList(),
                              ),
                            ],
                          );
                        },
                        childCount: nestedGroups!.length,
                      ),
                    ),
                  ],
                ),
              );
            }
          },
        );
      }),
    );
  }
}
