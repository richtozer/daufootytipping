import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:flutter/material.dart';

class StatsPage extends StatelessWidget {
  final String currentCompDbKey;

  const StatsPage(this.currentCompDbKey, {super.key});

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(context).orientation;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          orientation == Orientation.portrait
              ? const HeaderWidget(
                  text: 'S t a t s',
                  leadingIconAvatar: Hero(
                      tag: 'stats',
                      child: Icon(Icons.auto_graph,
                          color: Colors.white, size: 40)))
              : const Text(style: TextStyle(color: Colors.white), 'Stats'),
          Expanded(
            child: Card(
              margin: const EdgeInsets.all(10),
              child: ListView(
                children: <Widget>[
                  ListTile(
                    leading: const Hero(
                        tag: 'trophy', child: Icon(Icons.emoji_events)),
                    trailing: const Icon(Icons.arrow_forward),
                    title: const Text('Comp Leaderboard'),
                    onTap: () {
                      // Navigate to the comp leaderboard
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const StatCompLeaderboard()),
                      );
                    },
                  ),
                  ListTile(
                    leading:
                        Hero(tag: 'person', child: const Icon(Icons.person_3)),
                    trailing: const Icon(Icons.arrow_forward),
                    title: const Text('Round winners & leaderboard'),
                    onTap: () {
                      // Navigate to the round winners
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const StatRoundWinners()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  //@override
  Widget build2(BuildContext context) {
    // home page for all stats
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
      ),
      body: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Stats'),
          StatCompLeaderboard(),
        ],
      ),
    );
  }
}
