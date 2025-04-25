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
    Tipper selectedTipper) {
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
                  : Consumer<StatsViewModel>(
                      builder: (context, statsViewModel, child) {
                      RoundStats roundStats = statsViewModel
                          .getScoringRoundStats(dauRound, selectedTipper);
                      int countStats =
                          statsViewModel.allTipperRoundStats.length;

                      return Column(
                        children: [
                          Text(
                            'count stats: $countStats',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Text('selected tipper: ${selectedTipper.name}',
                              style: const TextStyle(
                                color: Colors.white70,
                              )),
                        ],
                      );
                    }),
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
