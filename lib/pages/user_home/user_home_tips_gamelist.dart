import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_round_leagueheader_listtile.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';

const double kTipsWelcomeHeaderHeight = 175;
const double kTipsEndFooterHeight = 100;

class TipsLeagueSection {
  const TipsLeagueSection({
    required this.roundIndex,
    required this.league,
    required this.headerExtent,
    required this.bodyExtent,
  });

  final int roundIndex;
  final League league;
  final double headerExtent;
  final double bodyExtent;
}

class TipsTabItemExtentCache {
  const TipsTabItemExtentCache._();

  static List<double> buildExtents(DAUComp selectedComp) {
    final extents = <double>[kTipsWelcomeHeaderHeight];

    for (final dauRound in selectedComp.daurounds) {
      extents.add(leagueHeaderExtent(dauRound, League.nrl));
      extents.add(leagueGamesExtent(dauRound, League.nrl));
      extents.add(leagueHeaderExtent(dauRound, League.afl));
      extents.add(leagueGamesExtent(dauRound, League.afl));
    }

    extents.add(kTipsEndFooterHeight);
    return extents;
  }

  static double leagueHeaderExtent(DAURound dauRound, League league) {
    final games = dauRound.getGamesForLeague(league);
    if (games.isEmpty) {
      return DAURound.leagueHeaderHeight;
    }
    if (dauRound.roundState == RoundState.allGamesEnded) {
      return DAURound.leagueHeaderEndedHeight;
    }
    return DAURound.leagueHeaderHeight;
  }

  static double leagueGamesExtent(DAURound dauRound, League league) {
    final games = dauRound.getGamesForLeague(league);
    if (games.isEmpty) {
      return DAURound.noGamesCardHeight;
    }
    return games.length * Game.gameCardHeight;
  }
}

List<TipsLeagueSection> buildTipsLeagueSections({
  required DAUComp selectedComp,
  int? roundCount,
}) {
  final sections = <TipsLeagueSection>[];
  final totalRounds = roundCount ?? selectedComp.daurounds.length;

  for (var roundIndex = 0; roundIndex < totalRounds; roundIndex++) {
    final dauRound = selectedComp.daurounds[roundIndex];
    for (final league in const [League.nrl, League.afl]) {
      sections.add(
        TipsLeagueSection(
          roundIndex: roundIndex,
          league: league,
          headerExtent: TipsTabItemExtentCache.leagueHeaderExtent(
            dauRound,
            league,
          ),
          bodyExtent: TipsTabItemExtentCache.leagueGamesExtent(
            dauRound,
            league,
          ),
        ),
      );
    }
  }

  return sections;
}

int activeTipsLeagueSectionIndex({
  required List<TipsLeagueSection> sections,
  required double scrollOffset,
  required double leadingExtent,
}) {
  if (sections.isEmpty) {
    return 0;
  }

  var cursor = leadingExtent;
  for (var index = 0; index < sections.length; index++) {
    final section = sections[index];
    final nextCursor = cursor + section.headerExtent + section.bodyExtent;
    if (scrollOffset < nextCursor) {
      return index;
    }
    cursor = nextCursor;
  }

  return sections.length - 1;
}

List<Widget> buildRoundLeagueSectionSlivers({
  required TipsLeagueSection section,
  required int roundIndex,
  required League league,
  required DAUCompsViewModel dauCompsViewModel,
  required Tipper currentTipper,
  required bool isPercentStatsPage,
  required bool showInlineHeader,
  required bool hideInlineHeaderVisual,
}) {
  final selectedComp = dauCompsViewModel.selectedDAUComp!;
  final dauRound = selectedComp.daurounds[roundIndex];
  final leagueGames = dauRound.getGamesForLeague(league);
  final tipsViewModel = dauCompsViewModel.selectedTipperTipsViewModel;
  final bodyExtent = section.bodyExtent;

  return [
    if (showInlineHeader)
      SliverToBoxAdapter(
        child: IgnorePointer(
          ignoring: hideInlineHeaderVisual,
          child: SizedBox(
            height: section.headerExtent,
            child: Opacity(
              opacity: hideInlineHeaderVisual ? 0 : 1,
              child: roundLeagueHeaderListTile(
                league,
                50,
                50,
                dauRound,
                dauCompsViewModel,
                currentTipper,
                isPercentStatsPage,
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
        itemExtent: Game.gameCardHeight,
        delegate: SliverChildBuilderDelegate((context, index) {
          final game = leagueGames[index];
          return GameListItem(
            key: ValueKey(game.dbkey),
            game: game,
            currentTipper: currentTipper,
            currentDAUComp: selectedComp,
            allTipsViewModel: tipsViewModel,
            isPercentStatsPage: isPercentStatsPage,
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
    required this.isPercentStatsPage,
    this.topPadding = 0,
    this.backgroundColor,
    super.key,
  });

  final TipsLeagueSection section;
  final DAUCompsViewModel dauCompsViewModel;
  final Tipper currentTipper;
  final bool isPercentStatsPage;
  final double topPadding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final dauRound =
        dauCompsViewModel.selectedDAUComp!.daurounds[section.roundIndex];

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: SizedBox(
        height: section.headerExtent,
        child: roundLeagueHeaderListTile(
          section.league,
          50,
          50,
          dauRound,
          dauCompsViewModel,
          currentTipper,
          isPercentStatsPage,
          backgroundColor:
              backgroundColor ??
              (isPercentStatsPage
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.62)),
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
              borderRadius: BorderRadius.circular(8.0),
            ),
            color: Colors.white70,
            child: Center(
              child: Text(
                'No ${league.name.toUpperCase()} games this round',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        );
      },
    );
  }
}
