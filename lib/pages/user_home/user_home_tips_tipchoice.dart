import 'dart:developer';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:flutter/material.dart';

class BuildChoiceChips extends StatelessWidget {
  final GameTipsViewModel gameTipsViewModel;

  const BuildChoiceChips(this.gameTipsViewModel, {super.key});

  Future<Tip?> getGameTips() async {
    Tip? latestGameTip = await gameTipsViewModel.getLatestGameTip();
    log('zzz finished getGameTips()');
    return latestGameTip;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Tip?>(
        future: getGameTips(),
        builder: (context, AsyncSnapshot<Tip?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            //return const CircularProgressIndicator(); // Show loading spinner while waiting for data
            return const SizedBox
                .shrink(); //return empty widget while waiting for data
          } else if (snapshot.hasError) {
            return Text(
                'Error: ${snapshot.error}'); // Show error message if something went wrong
          } else {
            Tip? latestGameTip = snapshot.data;
            final List<String> options;
            final List<String> optionsTooltips;
            if (gameTipsViewModel.game.league == League.nrl) {
              options = GameResult.values.map((e) => e.nrl).toList();
              options.removeLast(); // remove 'No Result' as an option to select
              optionsTooltips =
                  GameResult.values.map((e) => e.nrlTooltip).toList();
            } else {
              options = GameResult.values.map((e) => e.afl).toList();
              options.removeLast(); // remove 'No Result' as an option to elect
              optionsTooltips =
                  GameResult.values.map((e) => e.aflTooltip).toList();
            }

            return Wrap(
                children: List<Widget>.generate(options.length, (int index) {
              return ChoiceChip.elevated(
                label: Text(options[index]),
                tooltip: optionsTooltips[index],
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(0.0),
                ),
                padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                selectedColor: const Color(0xFF789697),
                selected:
                    latestGameTip != null && latestGameTip.tip.index == index,
                onSelected: (bool selected) {
                  if (latestGameTip != null &&
                      latestGameTip.tip.index == index) {
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
                      tip: index == 0
                          ? GameResult.a
                          : (index == 1)
                              ? GameResult.b
                              : (index == 2)
                                  ? GameResult.c
                                  : (index == 3)
                                      ? GameResult.d
                                      : GameResult.e,
                      submittedTimeUTC: DateTime.now().toUtc(),
                    );
                    gameTipsViewModel.addTip(tip);
                  }
                },
              );
            })); // end of List.generate
          }
        }); // end of else
  }
}
