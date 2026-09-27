import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_percent_tipped.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundmissingtipsstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/svg.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart';

class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final dauCompsVM = context.watch<DAUCompsViewModel>();
    final selectedComp = dauCompsVM.selectedDAUComp;
    if (selectedComp == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }

    // Bottom aligned so the rows stay within thumb reach, but a short
    // viewport -- a folded phone, landscape -- has to reach every row, so the
    // column scrolls and holds the viewport height instead of overflowing.
    return LayoutBuilder(
      builder: (context, viewport) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // No page title: the bottom navigation already names this
                // tab, and the heading only cost vertical space.
                // Keep the rows at a readable width: stretched across a tablet the
                // forward arrow drifts a long way from the label it belongs to.
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kFormContentWidth,
                  ),
                  child: Card(
                    margin: const EdgeInsets.all(4),
                    // Same treatment as the tips game card, so the backdrop
                    // reads through this surface and the rows' own cards sit
                    // opaque on top of it. Both layers at the theme default
                    // left them white on white and indistinguishable.
                    color: Colors.white70,
                    surfaceTintColor: League.nrl.colour,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: <Widget>[
                        Card(
                          margin: const EdgeInsets.all(8.0),
                          child: GestureDetector(
                            onTap: () {
                              // Navigate to the comp leaderboard
                              Navigator.push(
                                context,
                                appPageRoute(
                                  (context) => const StatCompLeaderboard(),
                                ),
                              );
                            },
                            child: const Row(
                              children: [
                                Hero(
                                  tag: 'trophy',
                                  child: Icon(Icons.emoji_events, size: 40),
                                ),
                                SizedBox(height: 64, width: 16), // Add some spacing between the icon and the text
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
                                appPageRoute(
                                  (context) => const StatRoundWinners(),
                                ),
                              );
                            },
                            child: const Row(
                              children: [
                                Hero(
                                  tag: 'person',
                                  child: Icon(Icons.person_3, size: 40),
                                ),
                                SizedBox(height: 64, width: 16), // Add some spacing between the icon and the text
                                Expanded(
                                  child: Text(
                                    'Round winners\nRound Leaderboards',
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
                              // Navigate to the percent tipped
                              Navigator.push(
                                context,
                                appPageRoute((context) => StatPercentTipped()),
                              );
                            },
                            child: Row(
                              children: [
                                Hero(
                                  tag: 'percentage',
                                  child: Icon(Icons.percent, size: 40),
                                ),
                                SizedBox(height: 64, width: 16), // Add some spacing between the icon and the text
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
                                appPageRoute(
                                  (context) => RoundMissingTipsStats(
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
                                SizedBox(height: 64, width: 16), // Add some spacing between the icon and the text
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
                                appPageRoute(
                                  (context) => const LeagueLadderPage(
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
                                const SizedBox(
                                  height: 64,
                                  width: 16,
                                ), // Added const here
                                const Expanded(
                                  // Added const here
                                  child: Text('NRL Ladder\nTeam rankings'),
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
                                appPageRoute(
                                  (context) => const LeagueLadderPage(
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
                                  child: Text('AFL Ladder\nTeam rankings'),
                                ),
                                Icon(Icons.arrow_forward),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(height: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
