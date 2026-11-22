import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';

const double kTipsWelcomeHeaderHeight = 175;
const double kTipsEndFooterHeight = 100;

/// One league's games in one round: its header, which stays pinned at the top
/// while its games scroll beneath it, then a card per game.
///
/// Every extent in the tips list is fixed, so where anything sits is the sum
/// of what comes before it: the welcome header, then each section in turn.
class TipsLeagueSection {
  const TipsLeagueSection({
    required this.roundIndex,
    required this.league,
    required this.headerExtent,
    required this.bodyExtent,
    this.gameKeys = const [],
  });

  final int roundIndex;
  final League league;
  final double headerExtent;
  final double bodyExtent;

  /// The body's games, in order, so a relayout can find the reader's game.
  final List<String> gameKeys;

  /// Names the section across relayouts.
  String get sectionKey => '$roundIndex:${league.name}';
}

List<TipsLeagueSection> buildTipsLeagueSections({
  required DAUComp selectedComp,
  required double cardExtent,
  required double headerExtent,
  bool officialFixtureScoresOnly = false,
}) {
  return [
    for (final (roundIndex, dauRound) in selectedComp.daurounds.indexed)
      for (final league in const [League.nrl, League.afl])
        if (gamesForTipsLeagueSection(
              dauRound,
              league,
              officialFixtureScoresOnly: officialFixtureScoresOnly,
            )
            case final games
            when games.isNotEmpty || !officialFixtureScoresOnly)
          TipsLeagueSection(
            roundIndex: roundIndex,
            league: league,
            headerExtent: _leagueHeaderExtent(dauRound, league, headerExtent),
            bodyExtent: games.isEmpty
                ? DAURound.noGamesCardHeight
                : games.length * cardExtent,
            gameKeys: [for (final game in games) game.dbkey],
          ),
  ];
}

/// A round whose games have all ended shows one extra line of summary.
double _leagueHeaderExtent(
  DAURound dauRound,
  League league,
  double headerExtent,
) {
  if (dauRound.getGamesForLeague(league).isNotEmpty &&
      dauRound.roundState == RoundState.allGamesEnded) {
    return headerExtent +
        (DAURound.leagueHeaderEndedHeight - DAURound.leagueHeaderHeight);
  }
  return headerExtent;
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
  return games
      .where(
        (game) =>
            game.scoring?.homeTeamScore != null &&
            game.scoring?.awayTeamScore != null,
      )
      .toList();
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

/// Where the percentage page opens: the top of the latest completed round,
/// or of the last round before it that has a section, as the page lists only
/// games with a final score. 0 before any round has completed.
double latestCompletedRoundOffset({
  required DAUComp selectedComp,
  required List<TipsLeagueSection> sections,
}) {
  final latestRoundIndex = selectedComp.latestsCompletedRoundNumber() - 1;
  final lastListed = sections.lastIndexWhere(
    (section) => section.roundIndex <= latestRoundIndex,
  );
  if (lastListed < 0) {
    return 0;
  }
  final targetIndex = sections.indexWhere(
    (section) => section.roundIndex == sections[lastListed].roundIndex,
  );
  return tipsSectionHeaderTop(
    sections: sections,
    sectionIndex: targetIndex,
    leadingExtent: 0,
  );
}

/// Callback type for finding the first untipped game index within a game list.
typedef FirstUntippedGameIndexFn = int Function(List<Game> games);

/// Returns an additional scroll offset from the target round's start (see
/// [tipsSectionHeaderTop]) to its first upcoming untipped game, or the first
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

/// Where the header of the section at [sectionIndex] starts in the list,
/// after the welcome header ([leadingExtent]) and every section before it.
/// Scrolled to, it is the offset that pins that header with its first game
/// just below it.
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

/// The section whose header is pinned at [scrollOffset], or -1 while the
/// welcome header is still at the top.
int pinnedTipsSectionIndex({
  required List<TipsLeagueSection> sections,
  required double scrollOffset,
  required double leadingExtent,
}) {
  var pinnedIndex = -1;
  var headerTop = leadingExtent;
  for (var index = 0; index < sections.length; index++) {
    if (headerTop > scrollOffset) {
      break;
    }
    pinnedIndex = index;
    headerTop += sections[index].headerExtent + sections[index].bodyExtent;
  }
  return pinnedIndex;
}

/// The offset that shows the end of a finished competition: the last section
/// with its header pinned above it.
double tipsEndFooterOffset({
  required List<TipsLeagueSection> sections,
  required double leadingExtent,
}) {
  if (sections.isEmpty) {
    return 0;
  }
  final lastBodyEnd = tipsSectionHeaderTop(
    sections: sections,
    sectionIndex: sections.length,
    leadingExtent: leadingExtent,
  );
  return math.max(lastBodyEnd - sections.last.headerExtent, 0.0);
}

/// How far the list scrolls: the welcome header, the sections and the end
/// footer ([footerExtent]), less the [viewportExtent] that shows them.
double tipsMaxScrollExtent({
  required List<TipsLeagueSection> sections,
  required double leadingExtent,
  required double footerExtent,
  required double viewportExtent,
}) {
  final listExtent =
      tipsSectionHeaderTop(
        sections: sections,
        sectionIndex: sections.length,
        leadingExtent: leadingExtent,
      ) +
      footerExtent;
  return math.max(listExtent - viewportExtent, 0.0);
}

/// Whether [a] and [b] lay the list out the same way.
bool sameTipsLayout(List<TipsLeagueSection> a, List<TipsLeagueSection> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index].sectionKey != b[index].sectionKey ||
        a[index].headerExtent != b[index].headerExtent ||
        a[index].bodyExtent != b[index].bodyExtent ||
        !const ListEquality<String>().equals(
          a[index].gameKeys,
          b[index].gameKeys,
        )) {
      return false;
    }
  }
  return true;
}

typedef _TipsPiece = ({String key, String fallbackKey, double extent});

/// The list as named pieces: the welcome header, then each section's header
/// and each of its games, or its no-games card.
List<_TipsPiece> _tipsPieces(
  List<TipsLeagueSection> sections,
  double leadingExtent,
) => [
  (key: 'welcome', fallbackKey: 'welcome', extent: leadingExtent),
  for (final section in sections) ...[
    (
      key: 'header:${section.sectionKey}',
      fallbackKey: 'header:${section.sectionKey}',
      extent: section.headerExtent,
    ),
    if (section.gameKeys.isEmpty)
      (
        key: 'empty:${section.sectionKey}',
        fallbackKey: 'header:${section.sectionKey}',
        extent: section.bodyExtent,
      )
    else
      for (final gameKey in section.gameKeys)
        (
          key: 'game:$gameKey',
          fallbackKey: 'header:${section.sectionKey}',
          extent: section.bodyExtent / section.gameKeys.length,
        ),
  ],
];

/// Where [scrollOffset], laid out as [before], lands in [after]: the reader
/// keeps the game they were on, the same fraction of the way through it.
///
/// What the reader sees starts below the pinned header, or at the top while
/// the welcome header shows. That line is found in [before] -- a game, a
/// header, a no-games card -- and the same piece found in [after], so cards
/// remeasured, or games arriving or leaving elsewhere, leave it in view. A
/// piece that has gone (a game removed, a no-games card its games replaced)
/// falls back to the start of its section, its header pinned. Null when the section has gone
/// too, and the reader has nothing left to keep.
double? anchoredTipsScrollOffset({
  required List<TipsLeagueSection> before,
  required List<TipsLeagueSection> after,
  required double leadingExtent,
  required double scrollOffset,
}) {
  // An overscroll above the top is still the top.
  final offset = math.max(scrollOffset, 0.0);
  final pinned = pinnedTipsSectionIndex(
    sections: before,
    scrollOffset: offset,
    leadingExtent: leadingExtent,
  );
  final pinnedKey = pinned < 0 ? null : before[pinned].sectionKey;
  final afterTop =
      after
          .firstWhereOrNull((section) => section.sectionKey == pinnedKey)
          ?.headerExtent ??
      0.0;
  final line = offset + (pinned < 0 ? 0.0 : before[pinned].headerExtent);

  final from = _tipsPieces(before, leadingExtent);
  final to = _tipsPieces(after, leadingExtent);
  double? startOf(String key) {
    var start = 0.0;
    for (final piece in to) {
      if (piece.key == key) return start;
      start += piece.extent;
    }
    return null;
  }

  var fromStart = 0.0;
  for (final piece in from) {
    if (line < fromStart + piece.extent) {
      final fraction = (line - fromStart) / piece.extent;
      final kept = startOf(piece.key);
      final toPiece = to.firstWhereOrNull((each) => each.key == piece.key);
      if (kept != null && toPiece != null) {
        return math.max(kept + fraction * toPiece.extent - afterTop, 0.0);
      }
      final fallback = startOf(piece.fallbackKey);
      return fallback == null ? null : math.max(fallback, 0.0);
    }
    fromStart += piece.extent;
  }
  // Past the last section, in the end footer, which does not change height.
  final toEnd = to.fold(0.0, (sum, piece) => sum + piece.extent);
  return math.max(toEnd + line - fromStart - afterTop, 0.0);
}
