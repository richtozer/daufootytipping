import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_kickoff_countdown.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

/// League round header card showing round number, points/countdown stats,
/// and league logo.
///
/// Converted from a bare function to a proper widget so Flutter can preserve
/// identity across rebuilds and diff efficiently during scrolling.
class RoundLeagueHeaderListTile extends StatelessWidget {
  const RoundLeagueHeaderListTile({
    required this.league,
    required this.logoWidth,
    required this.logoHeight,
    required this.dauRound,
    required this.dauCompsViewModel,
    required this.selectedTipper,
    required this.isPercentStatsPage,
    this.inlineRoundLabel = false,
    this.margin = const EdgeInsets.all(4.0),
    this.backgroundColor,
    super.key,
  });

  /// Lets 'Round' sit beside its number where the width allows, rather
  /// than always stacking. Set for the wide arrangement only, so the
  /// familiar phone header is unchanged.
  final bool inlineRoundLabel;
  final League league;
  final double logoWidth;
  final double logoHeight;
  final DAURound dauRound;
  final DAUCompsViewModel dauCompsViewModel;
  final Tipper selectedTipper;
  final bool isPercentStatsPage;
  final EdgeInsetsGeometry margin;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final List<Game> gamesForLeague = dauRound.getGamesForLeague(league);
    DateTime? firstGameStart;
    if (gamesForLeague.isNotEmpty) {
      firstGameStart = gamesForLeague.first.startTimeUTC;
    }
    // Rank is live/provisional once any game in this league has a result.
    final bool hasScoredGame = gamesForLeague.any(
      (game) => game.gameState == GameState.startedResultKnown,
    );

    if (dauCompsViewModel.selectedTipperTipsViewModel == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final int tipsOutstanding = dauCompsViewModel.selectedTipperTipsViewModel!
        .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          dauRound,
          league,
        );
    final int? currentRoundNumber = dauCompsViewModel.selectedDAUComp
        ?.firstNotEndedRoundNumber();
    final bool showOutstandingBadge =
        currentRoundNumber == dauRound.dAUroundNumber && tipsOutstanding > 0;
    const double badgeRoom = 12;
    final double renderedLogoWidth = league == League.afl
        ? logoWidth + 10
        : logoWidth;
    final double renderedLogoHeight = league == League.afl
        ? logoHeight + 10
        : logoHeight;
    final Offset badgeOffset = league == League.afl
        ? const Offset(-7, -4)
        : const Offset(4, -4);

    final int marginTipsSubmitted = dauCompsViewModel
        .selectedTipperTipsViewModel!
        .numberOfMarginTipsSubmittedForRoundAndLeague(dauRound, league);

    return Card(
      margin: margin,
      color:
          backgroundColor ??
          (!isPercentStatsPage ? Colors.black54 : Colors.white10),
      surfaceTintColor: League.nrl.colour,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardCornerRadius),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 86,
                    // A tight bound keeps the label stacked; a looser one lets
                    // it sit inline when the text size leaves room for it.
                    maxWidth: inlineRoundLabel ? 200 : 86,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text(
                        'Round',
                        style: TextStyle(
                          color: !isPercentStatsPage
                              ? Colors.white70
                              : Colors.black54,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${dauRound.dAUroundNumber}',
                        style: TextStyle(
                          color: !isPercentStatsPage
                              ? Colors.white70
                              : Colors.black54,
                          fontWeight: FontWeight.bold,
                          fontSize: 30,
                        ),
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                gamesForLeague.isEmpty
                    ? const Expanded(child: SizedBox.shrink())
                    : Expanded(
                        // Compute from live game state rather than cached
                        // roundState, which is only set during initial linking.
                        child:
                            !gamesForLeague.any(
                              (game) =>
                                  game.gameState ==
                                      GameState.startedResultNotKnown ||
                                  game.gameState ==
                                      GameState.startedResultKnown,
                            )
                            ? Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 16,
                                runSpacing: 2,
                                children: [
                                  KickoffCountdown(
                                    kickoffDate: firstGameStart!,
                                  ),
                                  Text(
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    'Your Margins: $marginTipsSubmitted',
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : Selector<StatsViewModel?, RoundStats?>(
                                selector: (_, statsViewModel) =>
                                    statsViewModel?.getScoringRoundStats(
                                      dauRound,
                                      selectedTipper,
                                    ),
                                builder: (context, roundStats, child) {
                                  if (roundStats == null) {
                                    return const SizedBox.shrink();
                                  }

                                  final String rankLabel;
                                  final String rankChangeLabel;
                                  final IconData rankChangeIcon;
                                  final Color rankChangeColor;
                                  if (!hasScoredGame) {
                                    rankLabel = '?';
                                    rankChangeLabel = '?';
                                    rankChangeIcon = Icons.sync_alt;
                                    rankChangeColor = Colors.green;
                                  } else {
                                    rankLabel = '${roundStats.rank}';
                                    rankChangeLabel =
                                        '${roundStats.rankChange}';
                                    if (roundStats.rankChange > 0) {
                                      rankChangeIcon = Icons.arrow_upward;
                                      rankChangeColor = Colors.green;
                                    } else if (roundStats.rankChange < 0) {
                                      rankChangeIcon = Icons.arrow_downward;
                                      rankChangeColor = Colors.red;
                                    } else {
                                      rankChangeIcon = Icons.sync_alt;
                                      rankChangeColor = Colors.green;
                                    }
                                  }

                                  return Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 16,
                                    runSpacing: 2,
                                    children: [
                                      Text(
                                        style: TextStyle(
                                          color: !isPercentStatsPage
                                              ? Colors.white70
                                              : Colors.black54,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        'Points: ${league == League.afl ? roundStats.aflPoints : roundStats.nrlPoints} / ${league == League.afl ? roundStats.aflMaxPoints : roundStats.nrlMaxPoints}',
                                        softWrap: true,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        style: TextStyle(
                                          color: !isPercentStatsPage
                                              ? Colors.white70
                                              : Colors.black54,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        'UPS/Margins: ${league == League.afl ? roundStats.aflMarginUPS : roundStats.nrlMarginUPS} / ${league == League.afl ? roundStats.aflMarginTips : roundStats.nrlMarginTips}',
                                        softWrap: true,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              style: TextStyle(
                                                color: !isPercentStatsPage
                                                    ? Colors.white70
                                                    : Colors.black54,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              'Rank: $rankLabel  ',
                                              softWrap: true,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Icon(
                                            rankChangeIcon,
                                            color: rankChangeColor,
                                          ),
                                          Flexible(
                                            child: Text(
                                              style: TextStyle(
                                                color: !isPercentStatsPage
                                                    ? Colors.white70
                                                    : Colors.black54,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              rankChangeLabel,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                SizedBox(
                  width: 86,
                  child: Center(
                    child: SizedBox(
                      width: renderedLogoWidth + badgeRoom,
                      height: renderedLogoHeight + badgeRoom,
                      child: showOutstandingBadge
                          ? Align(
                              alignment: Alignment.center,
                              child: Badge.count(
                                count: tipsOutstanding,
                                backgroundColor: Colors.red[800],
                                largeSize: 20,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                offset: badgeOffset,
                                textStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                child: SvgPicture.asset(
                                  league.logo,
                                  width: renderedLogoWidth,
                                  height: renderedLogoHeight,
                                ),
                              ),
                            )
                          : Align(
                              alignment: Alignment.center,
                              child: SvgPicture.asset(
                                league.logo,
                                width: renderedLogoWidth,
                                height: renderedLogoHeight,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
