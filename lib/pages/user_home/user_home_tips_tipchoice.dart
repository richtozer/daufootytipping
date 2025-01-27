import 'dart:developer';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:flutter/material.dart';

class TipChoice extends StatefulWidget {
  final GameTipViewModel gameTipsViewModel;

  const TipChoice(this.gameTipsViewModel, {super.key});

  @override
  State<TipChoice> createState() => _TipChoiceState();
}

class _TipChoiceState extends State<TipChoice> {
  final Map<GameResult, Widget> _choiceChipCache = {};

  @override
  void initState() {
    super.initState();
    _precalculateChoiceChips();
  }

  void _precalculateChoiceChips() {
    for (var result in GameResult.values) {
      _choiceChipCache[result] =
          generateChoiceChip(result, widget.gameTipsViewModel, context);
    }
  }

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
                  GameResult.a, widget.gameTipsViewModel, context),
              generateChoiceChip(
                  GameResult.b, widget.gameTipsViewModel, context)
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              generateChoiceChip(
                  GameResult.c, widget.gameTipsViewModel, context),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              generateChoiceChip(
                  GameResult.d, widget.gameTipsViewModel, context),
              generateChoiceChip(
                  GameResult.e, widget.gameTipsViewModel, context)
            ],
          )
        ],
      ),
    );
  }

  ChoiceChip generateChoiceChip(GameResult option,
      GameTipViewModel gameTipsViewModel, BuildContext context) {
    return ChoiceChip.elevated(
      label: Text(gameTipsViewModel.game.league == League.afl
          ? option.afl
          : option.nrl),
      tooltip: gameTipsViewModel.game.league == League.afl
          ? option.aflTooltip
          : option.nrlTooltip,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
      selectedColor: Colors.lightGreen[500],
      selected:
          gameTipsViewModel.tip != null && gameTipsViewModel.tip!.tip == option,
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
                      'You are tipping in God Mode. Are you sure you want to submit this tip? You cannot revert back to no tip, but you can change this tip later if needed.'),
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
                        Tip tip = Tip(
                          tipper: gameTipsViewModel.currentTipper,
                          game: gameTipsViewModel.game,
                          tip: option,
                          submittedTimeUTC: DateTime.now().toUtc(),
                        );
                        //add the god mode tip to the realtime firebase database
                        gameTipsViewModel.addTip(tip);
                      },
                      child: const Text('Submit'),
                    ),
                  ],
                );
              },
            );

            return;
          }

          // process a normal user tip
          if (gameTipsViewModel.game.gameState ==
                  GameState.startedResultKnown ||
              gameTipsViewModel.game.gameState ==
                  GameState.startedResultNotKnown) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Tipping for this game has closed.'),
              ),
            );
            return;
          }
          if (gameTipsViewModel.tip != null &&
              gameTipsViewModel.tip!.tip == option) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.red,
                content: Text(
                    'Your tip [${gameTipsViewModel.game.league == League.afl ? gameTipsViewModel.tip!.tip.aflTooltip : gameTipsViewModel.tip!.tip.nrlTooltip}] has already been submitted.'),
              ),
            );
          } else {
            Tip tip = Tip(
              tipper: gameTipsViewModel.currentTipper,
              game: gameTipsViewModel.game,
              tip: option,
              submittedTimeUTC: DateTime.now().toUtc(),
            );
            //add the tip to the realtime firebase database
            gameTipsViewModel.addTip(tip);
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
