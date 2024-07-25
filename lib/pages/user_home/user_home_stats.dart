import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:flutter/material.dart';

class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(context).orientation;
    return Column(
      children: <Widget>[
        orientation == Orientation.portrait
            ? const HeaderWidget(
                text: 'S t a t s',
                leadingIconAvatar: Hero(
                    tag: 'stats',
                    child: Icon(Icons.auto_graph,
                        color: Colors.black54, size: 40)))
            : const Text(style: TextStyle(color: Colors.white), 'Stats'),
        Card(
          margin: const EdgeInsets.all(4),
          child: Column(
            children: <Widget>[
              Card(
                margin: const EdgeInsets.all(8.0),
                child: ListTile(
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
              ),
              Card(
                margin: const EdgeInsets.all(8.0),
                child: ListTile(
                  leading:
                      const Hero(tag: 'person', child: Icon(Icons.person_3)),
                  trailing: const Icon(Icons.arrow_forward),
                  title: const Text('Round winners & leaderboards'),
                  onTap: () {
                    // Navigate to the round winners
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const StatRoundWinners()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
