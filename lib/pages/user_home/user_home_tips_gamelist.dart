import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GameListBuilder extends StatefulWidget {
  const GameListBuilder({
    super.key,
    required this.currentTipper,
    required this.dauRound,
    required this.league,
    required this.tipperTipsViewModel,
    required this.dauCompsViewModel,
    required this.isPercentStatsPage,
  });

  final Tipper currentTipper;
  final DAURound dauRound;
  final League league;
  final TipsViewModel? tipperTipsViewModel;
  final DAUCompsViewModel dauCompsViewModel;
  final bool isPercentStatsPage;

  @override
  State<GameListBuilder> createState() => _GameListBuilderState();
}

class _GameListBuilderState extends State<GameListBuilder> {
  late List<Game>? leagueGames;
  late Map<League, List<Game>> allGames;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DAUCompsViewModel>.value(
      value: widget.dauCompsViewModel,
      builder: (context, snapshot) {
        return Consumer<DAUCompsViewModel>(
            builder: (context, dauCompsViewModelConsumer, child) {
          allGames =
              dauCompsViewModelConsumer.groupGamesIntoLeagues(widget.dauRound);
          leagueGames = allGames[widget.league];

          if (leagueGames!.isEmpty) {
            // await the initial game load to complete - gamesViewModel.initialLoadComplete - display a progress indicator until it does
            if (dauCompsViewModelConsumer.gamesViewModel != null) {
              return FutureBuilder<void>(
                future: dauCompsViewModelConsumer
                    .gamesViewModel!.initialLoadComplete,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                        child: CircularProgressIndicator(
                            color: League.nrl.colour));
                  }
                  return SizedBox(
                    height: 75,
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      color: Colors.white70,
                      child: Center(
                        child: Text(
                            'No ${widget.league.name.toUpperCase()} games this round'),
                      ),
                    ),
                  );
                },
              );
            }

            // return SizedBox(
            //   height: 75,
            //   child: Card(
            //     shape: RoundedRectangleBorder(
            //       borderRadius: BorderRadius.circular(8.0),
            //     ),
            //     color: Colors.white70,
            //     child: Center(
            //       child: Text(
            //           'No ${widget.league.name.toUpperCase()} games this round'),
            //     ),
            //   ),
            // );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(0),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leagueGames!.length,
            itemBuilder: (context, index) {
              var game = leagueGames![index];
              if (widget.tipperTipsViewModel == null) {
                return Center(
                    child: CircularProgressIndicator(color: League.nrl.colour));
              }
              return GameListItem(
                key: ValueKey(game.dbkey),
                game: game,
                currentTipper: widget.currentTipper,
                currentDAUComp: widget.dauCompsViewModel.selectedDAUComp!,
                allTipsViewModel: widget.tipperTipsViewModel!,
                isPercentStatsPage: widget.isPercentStatsPage,
              );
            },
          );
        });
      },
    );
  }
}
