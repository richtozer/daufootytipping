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

/// Where a pinned section sits: the list scrolled by [controller], and the
/// offset of its header ([tipsSectionHeaderTop]).
typedef TipsPinning = ({ScrollController controller, double sectionTop});

/// One section of the list: the league's header for the round, then its games.
///
/// [pinnedIn] pins the header at the top while the section's games scroll
/// beneath it, until the next section's header pushes it off.
Widget buildRoundLeagueSection({
  required TipsLeagueSection section,
  required TipsCardLayout layout,
  required DAUCompsViewModel dauCompsViewModel,
  required Tipper currentTipper,
  required bool isPercentStatsPage,
  TipsPinning? pinnedIn,
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
      if (pinnedIn != null)
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeaderDelegate(
            section: section,
            pinnedIn: pinnedIn,
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

/// A section's header, pinned. While it covers cards it blurs them, in the
/// same see-through colour as before: without the blur the cards ghost
/// through its text.
///
/// Headers pin to a line, which under a notch is just below the status bar.
/// The next section's header pushes this one up past that line, and the part
/// that has gone past it is clipped away: the cards scroll on up under the
/// status bar, and the header tucks under its edge.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedHeaderDelegate({
    required this.section,
    required this.pinnedIn,
    required this.header,
  });

  final TipsLeagueSection section;
  final TipsPinning pinnedIn;

  double get extent => section.headerExtent;

  /// Built with the list rather than by [build], so the frames that only
  /// scroll it reuse the same widget and do not rebuild the tile. A rebuild of
  /// the list brings a new one.
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
    final controller = pinnedIn.controller;
    final sectionEnd =
        pinnedIn.sectionTop + section.headerExtent + section.bodyExtent;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final offset = controller.hasClients ? controller.offset : 0.0;
        // How far the next header has pushed this one past the pin line.
        final pastLine = (offset + extent - sectionEnd).clamp(0.0, extent);
        return ClipRect(
          clipper: _ClipTop(pastLine),
          clipBehavior: pastLine > 0 ? Clip.hardEdge : Clip.none,
          child: child,
        );
      },
      child: _header(shrinkOffset, overlapsContent),
    );
  }

  Widget _header(double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: extent,
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kCardCornerRadius),
            child: BackdropFilter(
              // Over cards once pinned: scrolled into its section, or pinned
              // below something pinned above it, such as the status bar.
              enabled: shrinkOffset > 0 || overlapsContent,
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
      section != oldDelegate.section ||
      pinnedIn != oldDelegate.pinnedIn ||
      header != oldDelegate.header;
}

/// Clips away the top [top] of its child.
class _ClipTop extends CustomClipper<Rect> {
  const _ClipTop(this.top);

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);

  @override
  bool shouldReclip(_ClipTop oldClipper) => oldClipper.top != top;
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
