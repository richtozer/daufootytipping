import 'dart:async';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter/material.dart';

class GameListBuilder extends StatefulWidget {
  const GameListBuilder({
    super.key,
    required this.currentTipper,
    required this.dauRound,
    required this.league,
    required this.tipperTipsViewModel,
    required this.dauCompsViewModel,
  });

  final Tipper currentTipper;
  final DAURound dauRound;
  final League league;
  final TipsViewModel? tipperTipsViewModel;
  final DAUCompsViewModel dauCompsViewModel;

  @override
  State<GameListBuilder> createState() => _GameListBuilderState();
}

class _GameListBuilderState extends State<GameListBuilder> {
  late Game loadingGame;

  List<Game>? games;
  Future<List<Game>?>? gamesFuture;

  @override
  void initState() {
    super.initState();

    //get all the games for this round
    Future<Map<League, List<Game>>> gamesForCombinedRoundNumber =
        widget.dauCompsViewModel.sortGamesIntoLeagues(
      widget.dauRound,
    );

    //get all the games for this round and league
    gamesFuture =
        gamesForCombinedRoundNumber.then((Map<League, List<Game>> gamesMap) {
      return gamesMap[widget.league];
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Game>?>(
      future: gamesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(color: League.afl.colour),
          );
        } else {
          games = snapshot.data;

          if (games!.isEmpty) {
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
          }

          return ListView.builder(
            padding: const EdgeInsets.all(0),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: games!.length,
            itemBuilder: (context, index) {
              var game = games![index];
              if (widget.tipperTipsViewModel == null) {
                return Center(
                    child: CircularProgressIndicator(color: League.afl.colour));
              }
              return GameListItem(
                key: ValueKey(game.dbkey),
                roundGames: games!,
                game: game,
                currentTipper: widget.currentTipper,
                currentDAUComp: widget.dauCompsViewModel.selectedDAUComp!,
                allTipsViewModel: widget.tipperTipsViewModel!,
                dauRound: widget.dauRound,
              );
            },
          );
        }
      },
    );
  }
}
