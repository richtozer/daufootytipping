import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_kickoff_countdown.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

Widget roundLeagueHeaderListTile(
  League leagueHeader,
  double logoWidth,
  double logoHeight,
  DAURound dauRound,
  DAUCompsViewModel daucompsViewModel,
  Tipper selectedTipper,
  bool isPercentStatsPage,
) {
  // Calculate the number of days until the first game starts for this league round
  List<Game> gamesForLeague = dauRound.getGamesForLeague(leagueHeader);
  DateTime? firstGameStart;
  if (gamesForLeague.isNotEmpty) {
    firstGameStart = gamesForLeague.first.startTimeUTC;
  }

  // tipsOutstanding = daucompsViewModel.selectedTipperTipsViewModel is null return
  // a progress indicator
  if (daucompsViewModel.selectedTipperTipsViewModel == null) {
    return const Center(child: CircularProgressIndicator());
  }

  int tipsOutstanding = daucompsViewModel.selectedTipperTipsViewModel!
      .numberOfOutstandingTipsForRoundAndLeague(dauRound, leagueHeader);

  // get a current count of margin tips submitted for this league round
  int marginTipsSubmitted = daucompsViewModel.selectedTipperTipsViewModel!
      .numberOfMarginTipsSubmittedForRoundAndLeague(dauRound, leagueHeader);

  return Card(
    color: !isPercentStatsPage ? Colors.black54 : Colors.white10,
    surfaceTintColor: !isPercentStatsPage
        ? League.nrl.colour
        : League.nrl.colour,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Flexible(
                flex: 1,
                child: Column(
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
              // if the league round has no games then display an empty container, otherwise display the column of stats
              gamesForLeague.isEmpty
                  ? const SizedBox.shrink()
                  : Flexible(
                      flex: 2,
                      child: Consumer<StatsViewModel?>(
                        builder: (context, statsViewModel, child) {
                          if (statsViewModel == null) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          RoundStats roundStats = statsViewModel
                              .getScoringRoundStats(dauRound, selectedTipper);

                          return Column(
                            children: [
                              dauRound.roundState != RoundState.notStarted
                                  ? Text(
                                      style: TextStyle(
                                        color: !isPercentStatsPage
                                            ? Colors.white70
                                            : Colors.black54,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      'Score: ${leagueHeader == League.afl ? roundStats.aflScore : roundStats.nrlScore} / ${leagueHeader == League.afl ? roundStats.aflMaxScore : roundStats.nrlMaxScore}',
                                      softWrap: true,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    )
                                  : const SizedBox.shrink(),
                              dauRound.roundState != RoundState.notStarted
                                  ? Text(
                                      style: TextStyle(
                                        color: !isPercentStatsPage
                                            ? Colors.white70
                                            : Colors.black54,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      'UPS/Margins: ${leagueHeader == League.afl ? roundStats.aflMarginUPS : roundStats.nrlMarginUPS} / ${leagueHeader == League.afl ? roundStats.aflMarginTips : roundStats.nrlMarginTips}',
                                      softWrap: true,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    )
                                  : Column(
                                      children: [
                                        KickoffCountdown(
                                          kickoffDate: firstGameStart!,
                                        ),
                                        Text(
                                          'Tips Outstanding: $tipsOutstanding',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
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
                                    ),
                              dauRound.roundState != RoundState.notStarted
                                  ? Row(
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
                                            'Rank: ${roundStats.rank}  ',
                                            softWrap: true,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        roundStats.rankChange > 0
                                            ? const Icon(
                                                color: Colors.green,
                                                Icons.arrow_upward,
                                              )
                                            : roundStats.rankChange < 0
                                            ? const Icon(
                                                color: Colors.red,
                                                Icons.arrow_downward,
                                              )
                                            : const Icon(
                                                color: Colors.green,
                                                Icons.sync_alt,
                                              ),
                                        Flexible(
                                          child: Text(
                                            style: TextStyle(
                                              color: !isPercentStatsPage
                                                  ? Colors.white70
                                                  : Colors.black54,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            '${roundStats.rankChange}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ],
                          );
                        },
                      ),
                    ),
              Flexible(
                flex: 1,
                child: SvgPicture.asset(
                  leagueHeader.logo,
                  width: logoWidth,
                  height: logoHeight,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
