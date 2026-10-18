import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_percent_tipped.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundmissingtipsstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:daufootytipping/widgets/app_panel_card.dart';
import 'package:daufootytipping/widgets/app_bottom_aligned_scroll.dart';
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
    return AppBottomAlignedScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Keep the rows at a readable width: stretched across a tablet the
          // forward arrow drifts a long way from the label it belongs to.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kFormContentWidth),
            child: Column(
              children: <Widget>[
                _compHeader(selectedComp.name),
                _row(
                  context,
                  leading: const Hero(
                    tag: 'trophy',
                    child: Icon(Icons.emoji_events, size: 40),
                  ),
                  label: 'Competition Leaderboard\nWhat did others tip?',
                  onTap: () => Navigator.push(
                    context,
                    appPageRoute((context) => const StatCompLeaderboard()),
                  ),
                ),
                _row(
                  context,
                  leading: const Hero(
                    tag: 'person',
                    child: Icon(Icons.person_3, size: 40),
                  ),
                  label: 'Round winners\nRound Leaderboards',
                  onTap: () => Navigator.push(
                    context,
                    appPageRoute((context) => const StatRoundWinners()),
                  ),
                ),
                _row(
                  context,
                  leading: const Hero(
                    tag: 'percentage',
                    child: Icon(Icons.percent, size: 40),
                  ),
                  label: 'Shows percent breakdown of tips for all tippers per game.',
                  onTap: () => Navigator.push(
                    context,
                    appPageRoute((context) => StatPercentTipped()),
                  ),
                ),
                _row(
                  context,
                  leading: const Hero(
                    tag: 'magnifyingGlass',
                    child: Icon(Icons.search, size: 40),
                  ),
                  label:
                      'Missing Tips - Round ${selectedComp.firstNotEndedRoundNumber()}',
                  onTap: () => Navigator.push(
                    context,
                    appPageRoute(
                      (context) => RoundMissingTipsStats(
                        selectedComp.firstNotEndedRoundNumber(),
                      ),
                    ),
                  ),
                ),
                // The two ladders are the shortest rows here, so they pair up
                // rather than each taking a full line. That gives a vertically
                // constrained pane a row back.
                Row(
                  children: [
                    Expanded(
                      child: _row(
                        context,
                        leading: Hero(
                          tag: 'nrl_league_logo_hero',
                          child: SvgPicture.asset(
                            'assets/nrl.svg',
                            width: 30,
                            height: 40,
                          ),
                        ),
                        label: 'NRL Ladder\nTeam rankings',
                        gap: 8,
                        labelLines: 2,
                        onTap: () => Navigator.push(
                          context,
                          appPageRoute(
                            (context) =>
                                const LeagueLadderPage(league: League.nrl),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _row(
                        context,
                        leading: Hero(
                          tag: 'afl_league_logo_hero',
                          child: SvgPicture.asset(
                            'assets/afl.svg',
                            width: 30,
                            height: 40,
                          ),
                        ),
                        label: 'AFL Ladder\nTeam rankings',
                        gap: 8,
                        labelLines: 2,
                        onTap: () => Navigator.push(
                          context,
                          appPageRoute(
                            (context) =>
                                const LeagueLadderPage(league: League.afl),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The competition's name, in the same dark card as the round headers on the
  /// Tips tab.
  Widget _compHeader(String compName) {
    return AppHeaderCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              compName,
              style: AppHeaderCard.textStyle.copyWith(fontSize: 22),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          const AppIcon(size: 44, borderRadius: 10),
        ],
      ),
    );
  }

  /// One stats row, floating over the backdrop on the same tinted, see-through
  /// surface as the tips game cards.
  Widget _row(
    BuildContext context, {
    required Widget leading,
    required String label,
    required VoidCallback onTap,
    double gap = 16,
    int? labelLines,
  }) {
    return AppPanelCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            leading,
            // Holds the row's height as well as the gap beside the icon.
            SizedBox(height: 64, width: gap),
            Expanded(
              child: Text(
                label,
                maxLines: labelLines,
                overflow: labelLines == null ? null : TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_forward),
          ],
        ),
      ),
    );
  }
}
