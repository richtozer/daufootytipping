import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(context).orientation;

    bool paidTipper = di<TippersViewModel>()
        .selectedTipper!
        .paidForComp(di<DAUCompsViewModel>().activeDAUComp);

    return Column(
      children: <Widget>[
        orientation == Orientation.portrait
            ? HeaderWidget(
                // if they are a paid tipper for the active comp, then display the header as
                // 'DAU Stats' otherwise just 'Stats'
                text: paidTipper ? 'DAU Stats' : 'Stats',
                leadingIconAvatar: const Hero(
                    tag: 'stats', child: Icon(Icons.auto_graph, size: 40)))
            : const Text('Stats'),
        Card(
          margin: const EdgeInsets.all(4),
          child: Column(
            children: <Widget>[
              Card(
                margin: const EdgeInsets.all(8.0),
                child: GestureDetector(
                  onTap: () {
                    // Navigate to the comp leaderboard
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const StatCompLeaderboard()),
                    );
                  },
                  child: const Row(
                    children: [
                      Hero(
                        tag: 'trophy',
                        child: Icon(Icons.emoji_events, size: 40),
                      ),
                      SizedBox(
                          width:
                              16), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text('Comp Leaderboard'),
                      ),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
                ),
              ),
              Card(
                margin: const EdgeInsets.all(8.0),
                child: GestureDetector(
                  onTap: () {
                    // Navigate to the round winners
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const StatRoundWinners()),
                    );
                  },
                  child: const Row(
                    children: [
                      Hero(
                        tag: 'person',
                        child: Icon(Icons.person_3, size: 40),
                      ),
                      SizedBox(
                          width:
                              16), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text('Round winners & leaderboards'),
                      ),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
