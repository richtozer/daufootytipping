import 'dart:ui' as ui;

import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_geometry.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_round_leagueheader_listtile.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:flutter/material.dart';

/// One section of the list: the league's header for the round, then its games.
///
/// With [pinHeader] the header stays at the top while the section's games
/// scroll beneath it, until the next section's header pushes it off.
Widget buildRoundLeagueSection({
  required TipsLeagueSection section,
  required TipsCardLayout layout,
  required DAUCompsViewModel dauCompsViewModel,
  required Tipper currentTipper,
  required bool isPercentStatsPage,
  required bool pinHeader,
}) {
  final selectedComp = dauCompsViewModel.selectedDAUComp!;
  final dauRound = selectedComp.daurounds[section.roundIndex];
  final league = section.league;
  final leagueGames = gamesForTipsLeagueSection(
    dauRound,
    league,
    officialFixtureScoresOnly: isPercentStatsPage,
  );
  final tipsViewModel = dauCompsViewModel.selectedTipperTipsViewModel;
  final header = RoundLeagueHeaderListTile(
    inlineRoundLabel: layout.inlineRoundLabel,
    league: league,
    logoWidth: 50,
    logoHeight: 50,
    dauRound: dauRound,
    dauCompsViewModel: dauCompsViewModel,
    selectedTipper: currentTipper,
    margin: EdgeInsets.zero,
  );

  return SliverMainAxisGroup(
    slivers: [
      if (pinHeader)
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeaderDelegate(
            extent: section.headerExtent,
            header: header,
          ),
        )
      else
        SliverToBoxAdapter(
          child: SizedBox(
            height: section.headerExtent,
            child: Padding(padding: const EdgeInsets.all(4), child: header),
          ),
        ),
      if (dauCompsViewModel.gamesViewModel == null ||
          dauCompsViewModel.isLinkingGames ||
          tipsViewModel == null)
        SliverToBoxAdapter(
          child: SizedBox(
            height: section.bodyExtent,
            child: Center(
              child: CircularProgressIndicator(color: league.colour),
            ),
          ),
        )
      else if (leagueGames.isEmpty)
        SliverToBoxAdapter(
          child: _NoGamesCard(
            league: league,
            gamesLoadComplete:
                dauCompsViewModel.gamesViewModel!.initialLoadComplete,
          ),
        )
      else
        SliverFixedExtentList(
          itemExtent: layout.cardExtent,
          delegate: SliverChildBuilderDelegate((context, index) {
            final game = leagueGames[index];
            return RepaintBoundary(
              child: GameListItem(
                key: ValueKey(game.dbkey),
                layout: layout,
                game: game,
                currentTipper: currentTipper,
                currentDAUComp: selectedComp,
                allTipsViewModel: tipsViewModel,
                isPercentStatsPage: isPercentStatsPage,
              ),
            );
          }, childCount: leagueGames.length),
        ),
    ],
  );
}

/// A section's header, pinned. Once it is pinned over the section's cards it
/// blurs them, in the same see-through colour as before: without the blur the
/// cards ghost through its text.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedHeaderDelegate({required this.extent, required this.header});

  final double extent;

  /// Built once per section, so the frames that move it do not rebuild it.
  final Widget header;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: extent,
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kCardCornerRadius),
            child: BackdropFilter(
              enabled: shrinkOffset > 0,
              filter: ui.ImageFilter.blur(
                sigmaX: kGlassBlurSigma,
                sigmaY: kGlassBlurSigma,
              ),
              child: header,
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedHeaderDelegate oldDelegate) =>
      extent != oldDelegate.extent || header != oldDelegate.header;
}

class _NoGamesCard extends StatelessWidget {
  const _NoGamesCard({required this.league, required this.gamesLoadComplete});

  final League league;
  final Future<void> gamesLoadComplete;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: gamesLoadComplete,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: DAURound.noGamesCardHeight,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return SizedBox(
          height: DAURound.noGamesCardHeight,
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kCardCornerRadius),
            ),
            color: appPanelColor(context),
            child: Center(
              child: Text(
                'No ${league.name.toUpperCase()} games this round',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: appPanelTextColor(context)),
              ),
            ),
          ),
        );
      },
    );
  }
}
