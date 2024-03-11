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
              generateChoiceChip(
                  GameResult.a, gameTipsViewModel.tipGame, context),
              generateChoiceChip(
                  GameResult.b, gameTipsViewModel.tipGame, context)
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              generateChoiceChip(
                  GameResult.c, gameTipsViewModel.tipGame, context),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              generateChoiceChip(
                  GameResult.d, gameTipsViewModel.tipGame, context),
              generateChoiceChip(
                  GameResult.e, gameTipsViewModel.tipGame, context)
            ],
          )
        ],
      ),
    );
  }

  ChoiceChip generateChoiceChip(
      GameResult option, TipGame? latestGameTip, BuildContext context) {
    return ChoiceChip.elevated(
      label: Text(
          latestGameTip?.game.league == League.afl ? option.afl : option.nrl),
      tooltip: latestGameTip?.game.league == League.afl
          ? option.aflTooltip
          : option.nrlTooltip,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
      selectedColor:
          const Color(0xff04cf5d), //const Color.fromRGBO(152, 164, 141, 1),
      selected: latestGameTip != null && latestGameTip.tip == option,
      onSelected: (bool selected) {
        try {
          if (gameTipsViewModel.allTipsViewModel.tipperViewModel.inGodMode) {
            // show a modal dialog box to confirm they are tipping in god mode.
            // if they confirm, then submit the tip
            // if they cancel, then do nothing
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  icon: const Icon(Icons.warning),
                  iconColor: Colors.red,
                  title: const Text('Warning: God Mode'),
                  content: const Text(
                      'You are tipping in God Mode. Are you sure you want to submit this tip? You cannot undo it later.'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
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
                      },
                      child: const Text('Submit'),
                    ),
                  ],
                );
              },
            );

            return;
          }
          if (latestGameTip?.game.gameState == GameState.resultKnown ||
              latestGameTip?.game.gameState == GameState.resultNotKnown) {
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
