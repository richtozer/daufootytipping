import 'dart:developer';

import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';

import 'package:flutter/material.dart';

class TipChoice extends StatelessWidget {
  final Future<Tip?> latestGameTip;
  final GameTipsViewModel gameTipsViewModel;

  const TipChoice(this.latestGameTip, this.gameTipsViewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Tip?>(
        future: latestGameTip,
        builder: (context, AsyncSnapshot<Tip?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CircularProgressIndicator(); // Show loading spinner while waiting for data
            //return const SizedBox.shrink(); //return empty widget while waiting for data
          } else if (snapshot.hasError) {
            return Text(
                'Error: ${snapshot.error}'); // Show error message if something went wrong
          } else {
            Tip? latestGameTip = snapshot.data;

            return Focus(
              onFocusChange: (hasFocus) {
                if (hasFocus) {
                  log('CARD has focus');
                  //print('current tipper: ${gameTipsViewModel.currentTipper}');
                  //print('current game: ${gameTipsViewModel.game}');
                  //print('latest tip: ${latestGameTip}');
                }
              },
              child: Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        generateChoiceChip(GameResult.a, gameTipsViewModel.game,
                            latestGameTip, context),
                        generateChoiceChip(GameResult.b, gameTipsViewModel.game,
                            latestGameTip, context)
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        generateChoiceChip(GameResult.c, gameTipsViewModel.game,
                            latestGameTip, context),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        generateChoiceChip(GameResult.d, gameTipsViewModel.game,
                            latestGameTip, context),
                        generateChoiceChip(GameResult.e, gameTipsViewModel.game,
                            latestGameTip, context)
                      ],
                    )
                  ],
                ),
              ),
            );
          }
        });
  }

  ChoiceChip generateChoiceChip(
      GameResult option, Game game, Tip? latestGameTip, BuildContext context) {
    return ChoiceChip.elevated(
      label: Text(game.league == League.afl ? option.afl : option.nrl),
      tooltip:
          game.league == League.afl ? option.aflTooltip : option.nrlTooltip,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(0.0),
      ),
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
      selectedColor: const Color(0xFF789697),
      selected: latestGameTip != null && latestGameTip.tip == option,
      onSelected: (bool selected) {
        if (latestGameTip != null && latestGameTip.tip == option) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(
                  'Your tip [${latestGameTip.game.league == League.afl ? latestGameTip.tip.aflTooltip : latestGameTip.tip.nrlTooltip}] has already been submitted.'),
            ),
          );
        } else {
          Tip tip = Tip(
            tipper: gameTipsViewModel.currentTipper,
            game: gameTipsViewModel.game,
            tip: option,
            submittedTimeUTC: DateTime.now().toUtc(),
          );
          gameTipsViewModel.addTip(tip);
        }
      },
    );
  }
}
