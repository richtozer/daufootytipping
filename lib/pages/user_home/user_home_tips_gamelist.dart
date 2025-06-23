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
        value: Provider.of<DAUCompsViewModel>(context, listen: false),
        child: Consumer<DAUCompsViewModel>(
          builder: (context, dauCompsViewModelConsumer, _) {
            // Defensive: If gamesViewModel is null, show loading
            if (dauCompsViewModelConsumer.gamesViewModel == null) {
              return const Center(child: CircularProgressIndicator());
            }

            // Use FutureBuilder to wait for initialLoadComplete
            return FutureBuilder<void>(
                future: dauCompsViewModelConsumer
                    .gamesViewModel!.initialLoadComplete,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting || dauCompsViewModelConsumer.gamesViewModel == null) {
                    // Show loading indicator if still waiting for initial load or if gamesViewModel is unexpectedly null
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Ensure gamesViewModel is not null after waiting, though FutureBuilder should handle this.
                  // This is an extra defensive check.
                  if (dauCompsViewModelConsumer.gamesViewModel == null) {
                     return const Center(
                        child: Text(
                          'Error: Game data is unavailable. Please try again later.',
                          textAlign: TextAlign.center,
                        ),
                      );
                  }

                  // Now it's safe to group games
                  // Ensure gamesViewModel is ready (though covered by FutureBuilder)
                  // then group games using the method from dauCompsViewModelConsumer
                  final allGames = dauCompsViewModelConsumer.groupGamesIntoLeagues(widget.dauRound);
                  final leagueGames = allGames[widget.league];

                  if (leagueGames == null || leagueGames.isEmpty) {
                    return SizedBox(
                      height: 100, // Increased height for better visibility
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        color: Colors.grey[200], // Slightly different color for empty state
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              'No ${widget.league.name.toUpperCase()} games scheduled for this round, or data is still loading.',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black54),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
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
                            child: CircularProgressIndicator(
                                color: League.nrl.colour));
                      }
                      return GameListItem(
                        key: ValueKey(game.dbkey),
                        game: game,
                        currentTipper: widget.currentTipper,
                        currentDAUComp:
                            widget.dauCompsViewModel.selectedDAUComp!,
                        allTipsViewModel: widget.tipperTipsViewModel!,
                        isPercentStatsPage: widget.isPercentStatsPage,
                      );
                    },
                  );
                });
          },
        ));
  }
}
