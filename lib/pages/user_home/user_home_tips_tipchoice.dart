import 'dart:developer';

import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:flutter/material.dart';

class TipChoice extends StatelessWidget {
  const TipChoice(
    this.gameTipViewModel,
    this.isPercentStatsPage, {
    super.key,
    this.gameStatsEntry,
  });

  final GameTipViewModel gameTipViewModel;
  final bool isPercentStatsPage;
  final GameStatsEntry? gameStatsEntry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    !isPercentStatsPage
                        ? generateChoiceChip(
                            GameResult.a,
                            gameTipViewModel,
                            context,
                          )
                        : generatePercentStatsChip(
                            GameResult.a,
                            gameTipViewModel,
                            gameStatsEntry,
                            context,
                          ),
                    const SizedBox(width: 8),
                    !isPercentStatsPage
                        ? generateChoiceChip(
                            GameResult.b,
                            gameTipViewModel,
                            context,
                          )
                        : generatePercentStatsChip(
                            GameResult.b,
                            gameTipViewModel,
                            gameStatsEntry,
                            context,
                          ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  !isPercentStatsPage
                      ? generateChoiceChip(
                          GameResult.c,
                          gameTipViewModel,
                          context,
                        )
                      : generatePercentStatsChip(
                          GameResult.c,
                          gameTipViewModel,
                          gameStatsEntry,
                          context,
                        ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  !isPercentStatsPage
                      ? generateChoiceChip(
                          GameResult.d,
                          gameTipViewModel,
                          context,
                        )
                      : generatePercentStatsChip(
                          GameResult.d,
                          gameTipViewModel,
                          gameStatsEntry,
                          context,
                        ),
                  const SizedBox(width: 8),
                  !isPercentStatsPage
                      ? generateChoiceChip(
                          GameResult.e,
                          gameTipViewModel,
                          context,
                        )
                      : generatePercentStatsChip(
                          GameResult.e,
                          gameTipViewModel,
                          gameStatsEntry,
                          context,
                        ),
                ],
              ),
            ],
          ),
        ),
        if (gameTipViewModel.savingTip)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.0,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  ChoiceChip generateChoiceChip(
    GameResult option,
    GameTipViewModel gameTipsViewModel,
    BuildContext context,
  ) {
    return ChoiceChip.elevated(
      label: Text(
        gameTipsViewModel.game.league == League.afl
            ? option.afl
            : option.nrl,
      ),
      tooltip: gameTipsViewModel.game.league == League.afl
          ? option.aflTooltip
          : option.nrlTooltip,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
      selectedColor: Colors.lightGreen[500],
      selected:
          gameTipsViewModel.tip != null && gameTipsViewModel.tip!.tip == option,
      onSelected: gameTipsViewModel.savingTip
          ? null
          : (bool selected) async {
              if (gameTipViewModel.currentTipper.isAnonymous) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.orange,
                    content: Text(
                      'Read-only mode: Tipping is disabled for anonymous users.',
                    ),
                  ),
                );
                return;
              }

              try {
                if (gameTipsViewModel
                    .allTipsViewModel
                    .tipperViewModel
                    .inGodMode) {
                  showDialog(
                    context: context,
                    builder: (BuildContext dialogContext) {
                      return AlertDialog(
                        icon: const Icon(Icons.warning),
                        iconColor: Colors.red,
                        title: const Text('Warning: God Mode'),
                        content: const Text(
                          'You are tipping in God Mode. Are you sure you want to submit this tip? You cannot revert back to no tip, but you can change this tip later if needed.',
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                            },
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();
                              final tip = Tip(
                                tipper: gameTipsViewModel.currentTipper,
                                game: gameTipsViewModel.game,
                                tip: option,
                                submittedTimeUTC: DateTime.now().toUtc(),
                              );
                              await gameTipsViewModel.addTip(tip);
                            },
                            child: const Text('Submit'),
                          ),
                        ],
                      );
                    },
                  );

                  return;
                }

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
                        'Your tip [${gameTipsViewModel.game.league == League.afl ? gameTipsViewModel.tip!.tip.aflTooltip : gameTipsViewModel.tip!.tip.nrlTooltip}] has already been submitted.',
                      ),
                    ),
                  );
                } else {
                  final tip = Tip(
                    tipper: gameTipsViewModel.currentTipper,
                    game: gameTipsViewModel.game,
                    tip: option,
                    submittedTimeUTC: DateTime.now().toUtc(),
                  );
                  await gameTipsViewModel.addTip(tip);
                }
              } catch (e) {
                final msg = 'Error submitting tip: $e';
                log(msg);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(backgroundColor: Colors.red, content: Text(msg)),
                );
              }
            },
    );
  }

  ChoiceChip generatePercentStatsChip(
    GameResult option,
    GameTipViewModel gameTipsViewModel,
    GameStatsEntry? gameStatsEntry,
    BuildContext context,
  ) {
    var buttonText = '?';
    double? percentageForOption;
    switch (option) {
      case GameResult.a:
        percentageForOption = gameStatsEntry?.percentageTippedHomeMargin;
        break;
      case GameResult.b:
        percentageForOption = gameStatsEntry?.percentageTippedHome;
        break;
      case GameResult.c:
        percentageForOption = gameStatsEntry?.percentageTippedDraw;
        break;
      case GameResult.d:
        percentageForOption = gameStatsEntry?.percentageTippedAway;
        break;
      case GameResult.e:
        percentageForOption = gameStatsEntry?.percentageTippedAwayMargin;
        break;
      case GameResult.z:
        break;
    }
    if (percentageForOption != null) {
      buttonText = '${(percentageForOption * 100).toStringAsFixed(1)}%';
    }

    return ChoiceChip.elevated(
      avatar:
          gameTipsViewModel.game.scoring?.getGameResultCalculated(
                gameTipsViewModel.game.league,
              ) ==
              option
          ? const Icon(Icons.emoji_events, color: Colors.black)
          : null,
      label: percentageForOption == null
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            )
          : Text(buttonText),
      tooltip: gameTipsViewModel.game.league == League.afl
          ? option.aflTooltip
          : option.nrlTooltip,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
      selectedColor: Colors.lightGreen[500],
      selected:
          gameTipsViewModel.tip != null && gameTipsViewModel.tip!.tip == option,
    );
  }
}
