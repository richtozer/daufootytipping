import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundmissingtipsstats.dart';
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
        .selectedTipper
        .paidForComp(di<DAUCompsViewModel>().selectedDAUComp);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
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
                          height: 64,
                          width:
                              16), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text(
                            'Competition Leaderboard\nWhat did others tip?'),
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
                          height: 64,
                          width:
                              16), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text('Round winners\nRound Leaderboards'),
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
                          builder: (context) => RoundMissingTipsStats(
                              di<DAUCompsViewModel>()
                                  .selectedDAUComp!
                                  .lowestRoundNumberNotEnded())),
                    );
                  },
                  child: Row(
                    children: [
                      Hero(
                        tag: 'magifyingglass',
                        child: Icon(Icons.search, size: 40),
                      ),
                      SizedBox(
                          width:
                              16), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text(
                            'Missing Tips - Round ${di<DAUCompsViewModel>().selectedDAUComp!.lowestRoundNumberNotEnded()}'),
                      ),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
                ),
              ),
              // add some help text here
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  '* You need to submit at least 1 tip to appear in the stats.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 25,
        ),
      ],
    );
  }
}
