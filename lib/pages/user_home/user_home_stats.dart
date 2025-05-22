import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_percent_tipped.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundmissingtipsstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart';

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
                    // Navigate to missing tips
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
                    // Navigate to the percent tipped
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => StatPercentTipped()),
                    );
                  },
                  child: Row(
                    children: [
                      Hero(
                        tag: 'percentage',
                        child: Icon(Icons.percent, size: 40),
                      ),
                      SizedBox(
                          height: 64,
                          width:
                              16), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text(
                            'Shows percent breakdown of tips for all tippers per game.'),
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
                          height: 64,
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
              Card(
                margin: const EdgeInsets.all(8.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LeagueLadderPage(
                          league: League.nrl, // Pass League.nrl
                        ),
                      ),
                    );
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.list_alt,
                          size: 40), // Consider a different icon
                      SizedBox(height: 64, width: 16),
                      Expanded(
                        child: Text('NRL Ladder\nView current standings'),
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LeagueLadderPage(
                          league: League.afl, // Pass League.afl
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      // Replace the Icon with the AFL SVG logo in black and white
                      Hero(
                        tag: 'afl_logo',
                        child: SvgPicture.asset(
                          'assets/teams/afl.svg',
                          width: 30,
                          height: 40,
                        ),
                      ),
                      SizedBox(height: 64, width: 16),
                      Expanded(
                        child: Text('AFL Ladder\nView current standings'),
                      ),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
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
