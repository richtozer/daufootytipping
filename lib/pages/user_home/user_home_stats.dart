import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_percent_tipped.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundmissingtipsstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_bottom_aligned_scroll.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/svg.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart';
import 'package:daufootytipping/theme_data.dart';

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
    return AppBottomAlignedScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // No page title: the bottom navigation already names this
          // tab, and the heading only cost vertical space.
          // Keep the rows at a readable width: stretched across a tablet the
          // forward arrow drifts a long way from the label it belongs to.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kFormContentWidth),
            child: Card(
              margin: const EdgeInsets.all(4),
              // Same treatment as the tips game card, so the backdrop
              // reads through this surface and the rows' own cards sit
              // opaque on top of it. Both layers at the theme default
              // left them white on white and indistinguishable.
              color: Colors.white70,
              surfaceTintColor: League.nrl.colour,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kCardCornerRadius),
              ),
              child: Column(
                children: <Widget>[
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 3.0,
                    ),
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
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 3.0,
                    ),
                    child: GestureDetector(
                      onTap: () {
                        // Navigate to missing tips
                        Navigator.push(
                          context,
                          appPageRoute((context) => const StatRoundWinners()),
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
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 3.0,
                    ),
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
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 3.0,
                    ),
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
                  // The two ladders are the shortest rows here, so
                  // they pair up rather than each taking a full line.
                  // That gives a vertically constrained pane a row back.
                  Row(
                    children: [
                      Expanded(
                        child: _ladderCard(
                          context,
                          league: League.nrl,
                          asset: 'assets/nrl.svg',
                          heroTag: 'nrl_league_logo_hero',
                          label: 'NRL Ladder\nTeam rankings',
                        ),
                      ),
                      Expanded(
                        child: _ladderCard(
                          context,
                          league: League.afl,
                          asset: 'assets/afl.svg',
                          heroTag: 'afl_league_logo_hero',
                          label: 'AFL Ladder\nTeam rankings',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One league ladder row. Half width, so it carries a tighter gap than the
  /// full-width rows and holds its label to two lines rather than pushing a
  /// third past the row height.
  Widget _ladderCard(
    BuildContext context, {
    required League league,
    required String asset,
    required String heroTag,
    required String label,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            appPageRoute((context) => LeagueLadderPage(league: league)),
          );
        },
        child: Row(
          children: [
            Hero(
              tag: heroTag,
              child: SvgPicture.asset(asset, width: 30, height: 40),
            ),
            const SizedBox(height: 64, width: 8),
            Expanded(
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_forward),
          ],
        ),
      ),
    );
  }
}
