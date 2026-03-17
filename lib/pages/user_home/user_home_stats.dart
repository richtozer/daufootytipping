import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_percent_tipped.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundmissingtipsstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart';

class StatsTab extends StatelessWidget with WatchItMixin {
  StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final dauCompsVM = context.watch<DAUCompsViewModel>();
    final selectedComp = dauCompsVM.selectedDAUComp;
    if (selectedComp == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }

    Orientation orientation = MediaQuery.of(context).orientation;

    bool paidTipper = di<TippersViewModel>().selectedTipper.paidForComp(
      selectedComp,
    );

    // Listen reactively to StatsViewModel for live score changes
    final bool hasLiveScores = di.isRegistered<StatsViewModel>()
        ? watchIt<StatsViewModel>().hasLiveScoresInUse
        : false;
    final int liveScoreCount = hasLiveScores
        ? di<StatsViewModel>().liveScoreGameNames.length
        : 0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        orientation == Orientation.portrait
            ? HeaderWidget(
                // if they are a paid tipper for the active comp, then display the header as
                // 'DAU Stats' otherwise just 'Stats'
                text: paidTipper ? 'DAU Stats' : 'Stats',
                leadingIconAvatar: const Hero(
                  tag: 'stats',
                  child: Icon(Icons.auto_graph, size: 40),
                ),
              )
            : const Text('Stats'),
        if (hasLiveScores)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.amber.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.amber.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade800),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Scores are interim — using live data for '
                      '$liveScoreCount ${liveScoreCount == 1 ? 'game' : 'games'}.',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.info, color: Colors.amber.shade800),
                    tooltip: 'View live score details',
                    onPressed: () => _showLiveScoreDetails(context),
                  ),
                ],
              ),
            ),
          ),
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
                        builder: (context) => const StatCompLeaderboard(),
                      ),
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
                        width: 16,
                      ), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text(
                          'Competition Leaderboard\nWhat did others tip?',
                        ),
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
                        builder: (context) => const StatRoundWinners(),
                      ),
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
                        width: 16,
                      ), // Add some spacing between the icon and the text
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
                        builder: (context) => StatPercentTipped(),
                      ),
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
                        width: 16,
                      ), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text(
                          'Shows percent breakdown of tips for all tippers per game.',
                        ),
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
                          selectedComp.firstNotEndedRoundNumber(),
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Hero(
                        tag: 'magnifyingGlass',
                        child: Icon(Icons.search, size: 40),
                      ),
                      SizedBox(
                        height: 64,
                        width: 16,
                      ), // Add some spacing between the icon and the text
                      Expanded(
                        child: Text(
                          'Missing Tips - Round ${selectedComp.firstNotEndedRoundNumber()}',
                        ),
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
                  child: Row(
                    // Removed const here because Hero is not const
                    children: [
                      Hero(
                        // Added Hero widget
                        tag: "nrl_league_logo_hero", // Updated tag
                        child: SvgPicture.asset(
                          // Replaced Icon with SvgPicture
                          'assets/nrl.svg',
                          width: 30,
                          height: 40,
                        ),
                      ),
                      const SizedBox(height: 64, width: 16), // Added const here
                      const Expanded(
                        // Added const here
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
                        tag: "afl_league_logo_hero", // Updated tag
                        child: SvgPicture.asset(
                          'assets/afl.svg',
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
        Container(height: 25),
      ],
    );
  }

  void _showLiveScoreDetails(BuildContext context) {
    final details = di<StatsViewModel>().liveScoreDetails;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Live Scores In Use'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...details.map(
              (game) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        game.home,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '  ${game.homeScore ?? "-"} - ${game.awayScore ?? "-"}  ',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        game.away,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'To correct or finalise a score, tap the game on the Tips page.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
