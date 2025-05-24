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
  late List<Game> leagueGames;
  Future<void>? _initialLoadCompleteFuture;

  @override
  void initState() {
    super.initState();
    _updateLeagueGames();
    _initialLoadCompleteFuture =
        widget.dauCompsViewModel.gamesViewModel?.initialLoadComplete;
  }

  @override
  void didUpdateWidget(GameListBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dauRound != oldWidget.dauRound ||
        widget.league != oldWidget.league ||
        widget.dauCompsViewModel != oldWidget.dauCompsViewModel) {
      _updateLeagueGames();
    }

    if (widget.dauCompsViewModel.gamesViewModel !=
        oldWidget.dauCompsViewModel.gamesViewModel) {
      _initialLoadCompleteFuture =
          widget.dauCompsViewModel.gamesViewModel?.initialLoadComplete;
    }
  }

  void _updateLeagueGames() {
    // Access gamesViewModel safely, potentially from the widget's dauCompsViewModel if needed for grouping
    // This assumes groupGamesIntoLeagues doesn't rely on the Consumer's latest version but the one passed in the widget.
    // If groupGamesIntoLeagues itself depends on reactive state within dauCompsViewModel that isn't just gamesViewModel,
    // then the Consumer might still be needed higher up, or groupGamesIntoLeagues needs to be callable with specific data.
    final allGames =
        widget.dauCompsViewModel.groupGamesIntoLeagues(widget.dauRound);
    leagueGames = allGames[widget.league] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    // No need to wrap with ChangeNotifierProvider.value if it's already provided by an ancestor
    // and dauCompsViewModel is passed via widget.
    // However, if GameListBuilder is meant to react to changes in dauCompsViewModel
    // that are NOT captured by didUpdateWidget (e.g. deeper changes not reflected in equality),
    // then Consumer is still useful. Assuming didUpdateWidget handles necessary updates for now.

    // The Consumer is still useful to react to changes in gamesViewModel for the FutureBuilder condition.
    return Consumer<DAUCompsViewModel>(
        builder: (context, dauCompsViewModelConsumer, child) {
      // leagueGames is now managed by initState and didUpdateWidget

      if (leagueGames.isEmpty) {
        // Use the state variable _initialLoadCompleteFuture
        if (dauCompsViewModelConsumer.gamesViewModel != null) {
          return FutureBuilder<void>(
            future: _initialLoadCompleteFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(color: League.nrl.colour));
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
                    ), // Center
                  ), // Card
                ); // SizedBox
              },
            );
            } else
            // If the gamesViewModel is null, display a progress indicator
            {
              return Center(
                  child: CircularProgressIndicator(color: League.nrl.colour));
            }
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
        }); // Consumer
    // No '},' was here, so the structure is already correct regarding this point.
  } // build
}
