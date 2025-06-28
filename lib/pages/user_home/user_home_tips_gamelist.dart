import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ...existing imports...

class GameListBuilder extends StatefulWidget {
  const GameListBuilder({
    super.key,
    required this.currentTipper,
    required this.roundIndex,
    required this.league,
    required this.tipperTipsViewModel,
    required this.dauCompsViewModel,
    required this.isPercentStatsPage,
  });

  final Tipper currentTipper;
  final int roundIndex;
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
    return Consumer<DAUCompsViewModel>(
      builder: (context, dauCompsViewModelConsumer, _) {
        // Defensive: If gamesViewModel is null, show loading
        if (dauCompsViewModelConsumer.gamesViewModel == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (dauCompsViewModelConsumer.isLinkingGames) {
          return const Center(child: CircularProgressIndicator());
        }

        // Get fresh round data from the view model
        final dauRound = dauCompsViewModelConsumer
            .selectedDAUComp!.daurounds[widget.roundIndex];

        // Now it's safe to group games
        final allGames =
            dauCompsViewModelConsumer.groupGamesIntoLeagues(dauRound);
        final leagueGames = allGames[widget.league];

        if (leagueGames == null || leagueGames.isEmpty) {
          // Check if games are still loading before showing "No games" message
          return FutureBuilder<void>(
            future:
                dauCompsViewModelConsumer.gamesViewModel!.initialLoadComplete,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                // Games are still loading, show spinner
                return const Center(child: CircularProgressIndicator());
              } else {
                // Games are loaded but this round/league truly has no games
                return SizedBox(
                  height: 75,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    color: Colors.white70,
                    child: Center(
                      child: Text(
                        'No ${widget.league.name.toUpperCase()} games this round',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                );
              }
            },
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(0),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leagueGames.length,
          itemBuilder: (context, index) {
            var game = leagueGames[index];
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
      },
    );
  }
}
