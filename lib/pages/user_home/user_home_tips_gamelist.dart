import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_round_leagueheader_listtile.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:flutter/material.dart';

const double kTipsWelcomeHeaderHeight = 175;
const double kTipsEndFooterHeight = 100;

class TipsLeagueSection {
  const TipsLeagueSection({
    required this.roundIndex,
    required this.league,
    required this.headerExtent,
    required this.bodyExtent,
    required this.gameCount,
  });

  final int roundIndex;
  final League league;
  final double headerExtent;
  final double bodyExtent;

  /// The games in the section's body, so a remeasure can tell a change in card
  /// height from games that arrived or left.
  final int gameCount;
}

class TipsTabItemExtentCache {
  const TipsTabItemExtentCache._();

  static List<double> buildExtents(
    DAUComp selectedComp,
    double cardExtent,
    double headerExtent,
  ) {
    final extents = <double>[kTipsWelcomeHeaderHeight];

    for (final dauRound in selectedComp.daurounds) {
      extents.add(leagueHeaderExtent(dauRound, League.nrl, headerExtent));
      extents.add(leagueGamesExtent(dauRound, League.nrl, cardExtent));
      extents.add(leagueHeaderExtent(dauRound, League.afl, headerExtent));
      extents.add(leagueGamesExtent(dauRound, League.afl, cardExtent));
    }

    extents.add(kTipsEndFooterHeight);
    return extents;
  }

  static double leagueHeaderExtent(
    DAURound dauRound,
    League league,
    double headerExtent,
  ) {
    // A round whose games have all ended shows one extra line of summary.
    if (dauRound.getGamesForLeague(league).isNotEmpty &&
        dauRound.roundState == RoundState.allGamesEnded) {
      return headerExtent +
          (DAURound.leagueHeaderEndedHeight - DAURound.leagueHeaderHeight);
    }
    return headerExtent;
  }

  static double leagueGamesExtent(
    DAURound dauRound,
    League league,
    double cardExtent,
  ) {
    final games = dauRound.getGamesForLeague(league);
    if (games.isEmpty) {
      return DAURound.noGamesCardHeight;
    }
    return games.length * cardExtent;
  }
}

List<TipsLeagueSection> buildTipsLeagueSections({
  required DAUComp selectedComp,
  required double cardExtent,
  required double headerExtent,
  int? roundCount,
  bool officialFixtureScoresOnly = false,
}) {
  final sections = <TipsLeagueSection>[];
  final totalRounds = roundCount ?? selectedComp.daurounds.length;

  for (var roundIndex = 0; roundIndex < totalRounds; roundIndex++) {
    final dauRound = selectedComp.daurounds[roundIndex];
    for (final league in const [League.nrl, League.afl]) {
      final games = gamesForTipsLeagueSection(
        dauRound,
        league,
        officialFixtureScoresOnly: officialFixtureScoresOnly,
      );
      if (officialFixtureScoresOnly && games.isEmpty) {
        continue;
      }
      sections.add(
        TipsLeagueSection(
          roundIndex: roundIndex,
          league: league,
          headerExtent: TipsTabItemExtentCache.leagueHeaderExtent(
            dauRound,
            league,
            headerExtent,
          ),
          bodyExtent: games.isEmpty
              ? DAURound.noGamesCardHeight
              : games.length * cardExtent,
          gameCount: games.length,
        ),
      );
    }
  }

  return sections;
}

List<Game> gamesForTipsLeagueSection(
  DAURound dauRound,
  League league, {
  bool officialFixtureScoresOnly = false,
}) {
  final games = dauRound.getGamesForLeague(league);
  if (!officialFixtureScoresOnly) {
    return games;
  }
  return games.where(_hasOfficialFixtureScore).toList();
}

bool _hasOfficialFixtureScore(Game game) {
  return game.scoring?.homeTeamScore != null &&
      game.scoring?.awayTeamScore != null;
}

/// Returns the section index for the round the tips page should initially
/// scroll to. Prefers the highest started round; otherwise falls back to the
/// first round that has not fully ended yet.
int targetStartupSectionIndex(
  DAUComp selectedComp,
  List<TipsLeagueSection> sections,
) {
  if (sections.isEmpty) {
    return 0;
  }

  final activeRoundNumber = selectedComp
      .latestRoundWithGamesCompletedOrUnderway();
  final hasStartedRound =
      activeRoundNumber > 0 &&
      activeRoundNumber <= selectedComp.daurounds.length &&
      selectedComp.daurounds[activeRoundNumber - 1].roundState ==
          RoundState.started;
  final targetRoundNumber = hasStartedRound
      ? activeRoundNumber
      : selectedComp.firstNotEndedRoundNumber();

  // Round numbers are 1-based; section roundIndex is 0-based.
  // When no round is active (0), clamp keeps it at index 0.
  final targetRoundIndex = (targetRoundNumber > 0 ? targetRoundNumber - 1 : 0)
      .clamp(0, selectedComp.daurounds.length - 1);
  final targetSectionIndex = sections.indexWhere(
    (section) =>
        section.roundIndex == targetRoundIndex && section.league == League.nrl,
  );
  return targetSectionIndex == -1 ? 0 : targetSectionIndex;
}

/// Callback type for finding the first untipped game index within a game list.
typedef FirstUntippedGameIndexFn = int Function(List<Game> games);

/// Returns an additional scroll offset from the target round's start (see
/// [tipsSectionStartOffset]) to its first upcoming untipped game, or the first
/// live game ([GameState.startedResultNotKnown]) if there are no upcoming
/// untipped games. Returns 0 if neither condition applies.
double intraRoundScrollRefinement({
  required DAUComp selectedComp,
  required List<TipsLeagueSection> sections,
  required int targetSectionIndex,
  required FirstUntippedGameIndexFn firstUntippedGameIndex,
  required double cardExtent,
}) {
  final section = sections[targetSectionIndex];
  final dauRound = selectedComp.daurounds[section.roundIndex];
  final nrlGames = dauRound.getGamesForLeague(League.nrl);
  final aflGames = dauRound.getGamesForLeague(League.afl);

  // Find the AFL section for this round (immediately follows the NRL section).
  final aflSectionIndex = sections.indexWhere(
    (s) => s.roundIndex == section.roundIndex && s.league == League.afl,
  );

  // First pass: find the first upcoming untipped game across NRL then AFL.
  // Missing tips for games already underway are no longer actionable hints.
  final nrlUntippedIndex = _firstUpcomingUntippedGameIndex(
    nrlGames,
    firstUntippedGameIndex,
  );
  if (nrlUntippedIndex >= 0) {
    return nrlUntippedIndex * cardExtent;
  }

  final aflUntippedIndex = _firstUpcomingUntippedGameIndex(
    aflGames,
    firstUntippedGameIndex,
  );
  if (aflUntippedIndex >= 0 && aflSectionIndex >= 0) {
    return section.headerExtent +
        section.bodyExtent +
        aflUntippedIndex * cardExtent;
  }

  // Second pass: find the first live game across NRL then AFL, regardless of
  // whether the tipper submitted a tip for it.
  final allGames = [...nrlGames, ...aflGames];
  for (var i = 0; i < allGames.length; i++) {
    if (allGames[i].gameState == GameState.startedResultNotKnown) {
      if (i < nrlGames.length) {
        return i * cardExtent;
      }
      if (aflSectionIndex >= 0) {
        return section.headerExtent +
            section.bodyExtent +
            (i - nrlGames.length) * cardExtent;
      }
    }
  }

  return 0;
}

int _firstUpcomingUntippedGameIndex(
  List<Game> games,
  FirstUntippedGameIndexFn firstUntippedGameIndex,
) {
  final upcomingGames = <Game>[];
  final originalIndexes = <int>[];
  for (var i = 0; i < games.length; i++) {
    final gameState = games[i].gameState;
    if (gameState != GameState.startedResultNotKnown &&
        gameState != GameState.startedResultKnown) {
      upcomingGames.add(games[i]);
      originalIndexes.add(i);
    }
  }

  final upcomingIndex = firstUntippedGameIndex(upcomingGames);
  if (upcomingIndex < 0 || upcomingIndex >= originalIndexes.length) {
    return -1;
  }
  return originalIndexes[upcomingIndex];
}

/// Where the header of the section at [sectionIndex] starts in the list: the
/// welcome header ([leadingExtent], its inset included), then every section
/// before it, header and games. Every section keeps its header's space, with
/// the sticky header showing over it, so this holds wherever the list is.
double tipsSectionHeaderTop({
  required List<TipsLeagueSection> sections,
  required int sectionIndex,
  required double leadingExtent,
}) {
  var top = leadingExtent;
  for (var index = 0; index < sectionIndex; index++) {
    top += sections[index].headerExtent + sections[index].bodyExtent;
  }
  return top;
}

/// The section the sticky header shows: the last whose header has reached the
/// line it is pinned to, [topSafeInset] below the top of the list's viewport.
int activeStickyTipsLeagueSectionIndex({
  required List<TipsLeagueSection> sections,
  required double scrollOffset,
  required double leadingExtent,
  required double topSafeInset,
}) {
  final pinnedLine = scrollOffset + topSafeInset;
  var activeIndex = 0;
  var headerTop = leadingExtent;
  for (var index = 0; index < sections.length; index++) {
    if (headerTop > pinnedLine) {
      break;
    }
    activeIndex = index;
    headerTop += sections[index].headerExtent + sections[index].bodyExtent;
  }
  return activeIndex;
}

/// The offset that puts the header of the section at [targetSectionIndex] on
/// the sticky header's line, so its first game shows just below the sticky
/// header. The same for every section, the first included.
double tipsSectionStartOffset({
  required List<TipsLeagueSection> sections,
  required int targetSectionIndex,
  required double leadingExtent,
  required double topSafeInset,
}) {
  final headerTop = tipsSectionHeaderTop(
    sections: sections,
    sectionIndex: targetSectionIndex,
    leadingExtent: leadingExtent,
  );
  return math.max(headerTop - topSafeInset, 0.0);
}

/// The offset that shows the end of a finished competition: the last section
/// with its header pinned above it.
double tipsEndFooterOffset({
  required List<TipsLeagueSection> sections,
  required double leadingExtent,
  required double topSafeInset,
}) {
  if (sections.isEmpty) {
    return 0;
  }
  final lastBodyEnd = tipsSectionHeaderTop(
    sections: sections,
    sectionIndex: sections.length,
    leadingExtent: leadingExtent,
  );
  final stickyOverlayExtent = sections.last.headerExtent + topSafeInset;
  return math.max(lastBodyEnd - stickyOverlayExtent, 0.0);
}

/// Where [scrollOffset], measured against [before] and [beforeTopSafeInset],
/// lands in [after] with [afterTopSafeInset]: the same piece of the list, the
/// same fraction of the way through it.
///
/// Remeasuring the cards moves every section while the offset stays put in
/// pixels, which leaves a different game on screen. The list is the inset, the
/// welcome header ([welcomeHeaderExtent]), then each section's header and
/// games. A card's share of its section is the same in both, so the reader
/// keeps their game and their place in it.
///
/// What the reader sees starts below the sticky header, which is pinned the
/// inset below the offset and shows once the welcome header has gone; above
/// that, it starts at the inset. That line is carried across, and the new
/// inset and sticky header taken off again: the header does not grow with the
/// cards, so carrying the offset itself would move the reader by the header's
/// share. A list resting at the top stays there. Null when the two lists do
/// not describe the same sections holding the same games: games that arrived
/// or left are no fraction of what was there.
double? anchoredTipsScrollOffset({
  required List<TipsLeagueSection> before,
  required List<TipsLeagueSection> after,
  required double welcomeHeaderExtent,
  required double beforeTopSafeInset,
  required double afterTopSafeInset,
  required double scrollOffset,
}) {
  if (before.length != after.length) {
    return null;
  }
  for (var index = 0; index < before.length; index++) {
    if (before[index].roundIndex != after[index].roundIndex ||
        before[index].league != after[index].league ||
        before[index].gameCount != after[index].gameCount) {
      return null;
    }
  }
  List<double> pieces(List<TipsLeagueSection> sections, double inset) => [
    inset,
    welcomeHeaderExtent,
    for (final section in sections) ...[
      section.headerExtent,
      section.bodyExtent,
    ],
  ];
  final from = pieces(before, beforeTopSafeInset);
  final to = pieces(after, afterTopSafeInset);
  // An overscroll above the top is still the top.
  final offset = math.max(scrollOffset, 0.0);
  final stickyIndex = offset < welcomeHeaderExtent || before.isEmpty
      ? null
      : activeStickyTipsLeagueSectionIndex(
          sections: before,
          scrollOffset: offset,
          leadingExtent: welcomeHeaderExtent + beforeTopSafeInset,
          topSafeInset: beforeTopSafeInset,
        );
  final beforeTop =
      beforeTopSafeInset +
      (stickyIndex == null ? 0.0 : before[stickyIndex].headerExtent);
  final afterTop =
      afterTopSafeInset +
      (stickyIndex == null ? 0.0 : after[stickyIndex].headerExtent);
  final line = offset + beforeTop;
  var fromStart = 0.0;
  var toStart = 0.0;
  for (var index = 0; index < from.length; index++) {
    if (line < fromStart + from[index]) {
      final fraction = (line - fromStart) / from[index];
      return math.max(toStart + fraction * to[index] - afterTop, 0.0);
    }
    fromStart += from[index];
    toStart += to[index];
  }
  // Past the last section, in the end footer, which does not change height.
  return math.max(toStart + line - fromStart - afterTop, 0.0);
}

List<Widget> buildRoundLeagueSectionSlivers({
  required TipsLeagueSection section,
  required TipsCardLayout layout,
  required int roundIndex,
  required League league,
  required DAUCompsViewModel dauCompsViewModel,
  required Tipper currentTipper,
  required bool isPercentStatsPage,
  required bool hideInlineHeaderVisual,
}) {
  final selectedComp = dauCompsViewModel.selectedDAUComp!;
  final dauRound = selectedComp.daurounds[roundIndex];
  final leagueGames = gamesForTipsLeagueSection(
    dauRound,
    league,
    officialFixtureScoresOnly: isPercentStatsPage,
  );
  final tipsViewModel = dauCompsViewModel.selectedTipperTipsViewModel;
  final bodyExtent = section.bodyExtent;

  return [
    SliverToBoxAdapter(
      child: IgnorePointer(
        ignoring: hideInlineHeaderVisual,
        child: SizedBox(
          height: section.headerExtent,
          child: Visibility(
            visible: !hideInlineHeaderVisual,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: RepaintBoundary(
              child: RoundLeagueHeaderListTile(
                inlineRoundLabel: layout.inlineRoundLabel,
                league: league,
                logoWidth: 50,
                logoHeight: 50,
                dauRound: dauRound,
                dauCompsViewModel: dauCompsViewModel,
                selectedTipper: currentTipper,
              ),
            ),
          ),
        ),
      ),
    ),
    if (dauCompsViewModel.gamesViewModel == null ||
        dauCompsViewModel.isLinkingGames ||
        tipsViewModel == null)
      SliverToBoxAdapter(
        child: SizedBox(
          height: bodyExtent,
          child: Center(child: CircularProgressIndicator(color: league.colour)),
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
  ];
}

class TipsStickyHeader extends StatelessWidget {
  const TipsStickyHeader({
    required this.section,
    required this.dauCompsViewModel,
    required this.currentTipper,
    this.inlineRoundLabel = false,
    this.topPadding = 0,
    super.key,
  });

  final TipsLeagueSection section;
  final DAUCompsViewModel dauCompsViewModel;
  final Tipper currentTipper;
  final bool inlineRoundLabel;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final dauRound =
        dauCompsViewModel.selectedDAUComp!.daurounds[section.roundIndex];

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: SizedBox(
        height: section.headerExtent,
        child: RepaintBoundary(
          // The same see-through colour as the headers that scroll with the
          // list. This is the one with cards passing beneath it, so what is
          // behind it is blurred: without that the cards ghost through the text.
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kCardCornerRadius),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: kGlassBlurSigma,
                  sigmaY: kGlassBlurSigma,
                ),
                child: RoundLeagueHeaderListTile(
                  inlineRoundLabel: inlineRoundLabel,
                  league: section.league,
                  logoWidth: 50,
                  logoHeight: 50,
                  dauRound: dauRound,
                  dauCompsViewModel: dauCompsViewModel,
                  selectedTipper: currentTipper,
                  margin: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
