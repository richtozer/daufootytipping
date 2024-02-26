import 'dart:developer';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:flutter/material.dart';

class TipChoice extends StatelessWidget {
  final GameTipsViewModel gameTipsViewModel;
  final List<Game> roundGames;

  const TipChoice(this.roundGames, this.gameTipsViewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              generateChoiceChip(GameResult.a, gameTipsViewModel.game,
                  gameTipsViewModel.tipGame, context),
              generateChoiceChip(GameResult.b, gameTipsViewModel.game,
                  gameTipsViewModel.tipGame, context)
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              generateChoiceChip(GameResult.c, gameTipsViewModel.game,
                  gameTipsViewModel.tipGame, context),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              generateChoiceChip(GameResult.d, gameTipsViewModel.game,
                  gameTipsViewModel.tipGame, context),
              generateChoiceChip(GameResult.e, gameTipsViewModel.game,
                  gameTipsViewModel.tipGame, context)
            ],
          )
        ],
      ),
    );
  }

  ChoiceChip generateChoiceChip(GameResult option, Game game,
      TipGame? latestGameTip, BuildContext context) {
    return ChoiceChip.elevated(
      label: Text(game.league == League.afl ? option.afl : option.nrl),
      tooltip:
          game.league == League.afl ? option.aflTooltip : option.nrlTooltip,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
      selectedColor: const Color(0xFF789697),
      selected: latestGameTip != null && latestGameTip.tip == option,
      onSelected: (bool selected) {
        try {
          if (game.gameState != GameState.notStarted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Tipping for this game has closed.'),
              ),
            );
            return;
          }
          if (latestGameTip != null && latestGameTip.tip == option) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.red,
                content: Text(
                    'Your tip [${latestGameTip.game.league == League.afl ? latestGameTip.tip.aflTooltip : latestGameTip.tip.nrlTooltip}] has already been submitted.'),
              ),
            );
          } else {
            TipGame tip = TipGame(
              tipper: gameTipsViewModel.currentTipper,
              game: gameTipsViewModel.game,
              tip: option,
              submittedTimeUTC: DateTime.now().toUtc(),
            );
            //add the tip to the realtime firebase database
            gameTipsViewModel.addTip(
                roundGames,
                tip,
                tip.game.dauRound
                    .dAUroundNumber); //roundGames is passed to support legacy tipping only
          }
        } catch (e) {
          String msg = 'Error submitting tip: $e';
          log(msg);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(msg),
            ),
          );
        }
      },
    );
  }
}
