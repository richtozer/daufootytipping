import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_kickoff_countdown.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:watch_it/watch_it.dart';

Widget roundLeagueHeaderListTile(
    League leagueHeader,
    double logoWidth,
    double logoHeight,
    DAURound dauRound,
    DAUCompsViewModel daucompsViewModel,
    StatsViewModel? scoresViewmodelConsumer) {
  // check for null values
  RoundStats roundStats =
      scoresViewmodelConsumer?.allTipperRoundStats[dauRound.dAUroundNumber - 1]
              ?[di<TippersViewModel>().selectedTipper] ??
          RoundStats(
              roundNumber: 0,
              aflScore: 0,
              aflMaxScore: 0,
              aflMarginTips: 0,
              aflMarginUPS: 0,
              nrlScore: 0,
              nrlMaxScore: 0,
              nrlMarginTips: 0,
              nrlMarginUPS: 0,
              rank: 0,
              rankChange: 0,
              nrlTipsOutstanding: 0,
              aflTipsOutstanding: 0);

  // Calculate the number of days until the first game starts for this league round
  List<Game> gamesForLeague = dauRound.getGamesForLeague(leagueHeader);
  DateTime? firstGameStart;
  if (gamesForLeague.isNotEmpty) {
    firstGameStart = gamesForLeague.first.startTimeUTC;
  }

  int tipsOutstanding = daucompsViewModel.selectedTipperTipsViewModel!
      .numberOfOutstandingTipsForRoundAndLeague(dauRound, leagueHeader);

  // get a current count of margin tips submitted for this league round
  int marginTipsSubmitted = daucompsViewModel.selectedTipperTipsViewModel!
      .numberOfMarginTipsSubmittedForRoundAndLeague(dauRound, leagueHeader);

  return Card(
    color: Colors.black54,
    surfaceTintColor: League.nrl.colour,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8.0),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(15.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text('Round',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.bold)),
                  Text('${dauRound.dAUroundNumber}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 30)),
                ],
              ),
              // if the league round has no games then display an empty container, otherwise display the column of stats
              gamesForLeague.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        dauRound.roundState != RoundState.notStarted
                            ? Text(
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.bold),
                                'Score: ${leagueHeader == League.afl ? roundStats.aflScore : roundStats.nrlScore} / ${leagueHeader == League.afl ? roundStats.aflMaxScore : roundStats.nrlMaxScore}')
                            : const SizedBox.shrink(),
                        dauRound.roundState != RoundState.notStarted
                            ? Text(
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.bold),
                                'UPS/Margins: ${leagueHeader == League.afl ? roundStats.aflMarginUPS : roundStats.nrlMarginUPS} / ${leagueHeader == League.afl ? roundStats.aflMarginTips : roundStats.nrlMarginTips}')
                            : Column(
                                children: [
                                  KickoffCountdown(
                                      kickoffDate: firstGameStart!),
                                  Text(
                                    'Tips Outstanding: $tipsOutstanding',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold),
                                      'Your Margins: $marginTipsSubmitted'),
                                ],
                              ),
                        dauRound.roundState != RoundState.notStarted
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold),
                                      'Rank: ${roundStats.rank}  '),
                                  roundStats.rankChange > 0
                                      ? const Icon(
                                          color: Colors.green,
                                          Icons.arrow_upward)
                                      : roundStats.rankChange < 0
                                          ? const Icon(
                                              color: Colors.red,
                                              Icons.arrow_downward)
                                          : const Icon(
                                              color: Colors.green,
                                              Icons.sync_alt),
                                  Text(
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold),
                                      '${roundStats.rankChange}'),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ],
                    ),
              SvgPicture.asset(
                leagueHeader.logo,
                width: logoWidth,
                height: logoHeight,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
