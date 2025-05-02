import 'dart:developer';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class TipChoice extends StatefulWidget {
  final GameTipViewModel gameTipViewModel;
  final bool isPercentStatsPage;

  const TipChoice(this.gameTipViewModel, this.isPercentStatsPage, {super.key});

  @override
  State<TipChoice> createState() => _TipChoiceState();
}

class _TipChoiceState extends State<TipChoice> {
  final Map<GameResult, Widget> _choiceChipCache = {};

  @override
  void initState() {
    super.initState();
    if (!widget.isPercentStatsPage) {
      _precalculateChoiceChips();
    } else {
      _precalculatePercentStatsChips();
    }
  }

  void _precalculateChoiceChips() {
    for (var result in GameResult.values) {
      _choiceChipCache[result] =
          generateChoiceChip(result, widget.gameTipViewModel, context);
    }
  }

  void _precalculatePercentStatsChips() {
    di<StatsViewModel>()
        .getGamesStatsEntry(widget.gameTipViewModel.game, false);

    for (var result in GameResult.values) {
      _choiceChipCache[result] = generatePercentStatsChip(
          result,
          widget.gameTipViewModel,
          di<StatsViewModel>().gamesStatsEntry[widget.gameTipViewModel.game],
          context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StatsViewModel>(
        builder: (context, consumerStatsViewModel, child) {
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
                !widget.isPercentStatsPage
                    ? generateChoiceChip(
                        GameResult.a, widget.gameTipViewModel, context)
                    : generatePercentStatsChip(
                        GameResult.a,
                        widget.gameTipViewModel,
                        consumerStatsViewModel
                            .gamesStatsEntry[widget.gameTipViewModel.game],
                        context),
                !widget.isPercentStatsPage
                    ? generateChoiceChip(
                        GameResult.b, widget.gameTipViewModel, context)
                    : generatePercentStatsChip(
                        GameResult.b,
                        widget.gameTipViewModel,
                        consumerStatsViewModel
                            .gamesStatsEntry[widget.gameTipViewModel.game],
                        context),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                !widget.isPercentStatsPage
                    ? generateChoiceChip(
                        GameResult.c, widget.gameTipViewModel, context)
                    : generatePercentStatsChip(
                        GameResult.c,
                        widget.gameTipViewModel,
                        consumerStatsViewModel
                            .gamesStatsEntry[widget.gameTipViewModel.game],
                        context),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                !widget.isPercentStatsPage
                    ? generateChoiceChip(
                        GameResult.d, widget.gameTipViewModel, context)
                    : generatePercentStatsChip(
                        GameResult.d,
                        widget.gameTipViewModel,
                        consumerStatsViewModel
                            .gamesStatsEntry[widget.gameTipViewModel.game],
                        context),
                !widget.isPercentStatsPage
                    ? generateChoiceChip(
                        GameResult.e, widget.gameTipViewModel, context)
                    : generatePercentStatsChip(
                        GameResult.e,
                        widget.gameTipViewModel,
                        consumerStatsViewModel
                            .gamesStatsEntry[widget.gameTipViewModel.game],
                        context),
              ],
            ),
          ],
        ),
      );
    });
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
                backgroundColor: Colors.orange,
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

  ChoiceChip generatePercentStatsChip(
      GameResult option,
      GameTipViewModel gameTipsViewModel,
      GameStatsEntry? gameStatsEntry,
      BuildContext context) {
    // Generate label based on GameResult option. Switch on option and display percentage tipped.
    String buttonText = '?';
    switch (option) {
      case GameResult.a:
        buttonText = gameStatsEntry?.percentageTippedHomeMargin != null
            ? '${(gameStatsEntry!.percentageTippedHomeMargin! * 100).toStringAsFixed(1)}%'
            : '?';
        break;
      case GameResult.b:
        buttonText = gameStatsEntry?.percentageTippedHome != null
            ? '${(gameStatsEntry!.percentageTippedHome! * 100).toStringAsFixed(1)}%'
            : '?';
        break;
      case GameResult.c:
        buttonText = gameStatsEntry?.percentageTippedDraw != null
            ? '${(gameStatsEntry!.percentageTippedDraw! * 100).toStringAsFixed(1)}%'
            : '?';
        break;
      case GameResult.d:
        buttonText = gameStatsEntry?.percentageTippedAway != null
            ? '${(gameStatsEntry!.percentageTippedAway! * 100).toStringAsFixed(1)}%'
            : '?';
        break;
      case GameResult.e:
        buttonText = gameStatsEntry?.percentageTippedAwayMargin != null
            ? '${(gameStatsEntry!.percentageTippedAwayMargin! * 100).toStringAsFixed(1)}%'
            : '?';
        break;
      case GameResult.z:
        break;
    }

    return ChoiceChip.elevated(
      avatar: gameTipsViewModel.game.scoring
                  ?.getGameResultCalculated(gameTipsViewModel.game.league) ==
              option
          ? const Icon(Icons.emoji_events, color: Colors.black)
          : null,
      label: gameStatsEntry?.percentageTippedAwayMargin == null
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
              ),
            )
          : Text(buttonText),
      tooltip: gameTipsViewModel.game.league == League.afl
          ? option.aflTooltip
          : option.nrlTooltip,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
      selectedColor: Colors.lightGreen[300],
      selected:
          gameTipsViewModel.tip != null && gameTipsViewModel.tip!.tip == option,
    );
  }
}
