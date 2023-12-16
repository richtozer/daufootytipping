import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/tips_viewmodel.dart';
import 'package:flutter/material.dart';

class BuildChoiceChips extends StatelessWidget {
  final TipsViewModel tipsViewModel;
  final Game game;
  late TippersViewModel tippersViewModel;

  BuildChoiceChips(this.tipsViewModel, this.game, {super.key}) {
    tippersViewModel = tipsViewModel.tippersViewModel;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Tip?>(
      future: tipsViewModel.getLatestGameTip(game),
      builder: (context, AsyncSnapshot<Tip?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator(); // Show loading spinner while waiting for data
        } else if (snapshot.hasError) {
          return Text(
              'Error: ${snapshot.error}'); // Show error message if something went wrong
        } else {
          final latestGameTip = snapshot.data;
          final List<String> options;
          final List<String> optionsTooltips;
          if (game.league == League.nrl) {
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
            children: List<Widget>.generate(
              options.length,
              (int index) {
                return FutureBuilder<Tipper>(
                  future: tipsViewModel.tippersViewModel.getcurrentTipper(),
                  builder:
                      (BuildContext context, AsyncSnapshot<Tipper> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator(); // Show a loading spinner while waiting
                    } else if (snapshot.hasError) {
                      return Text(
                          'Error: ${snapshot.error}'); // Show error if something went wrong
                    } else {
                      Tipper currentTipper = snapshot.data!;
                      return ChoiceChip.elevated(
                        label: Text(options[index]),
                        tooltip: optionsTooltips[index],
                        showCheckmark: false,
                        labelStyle: const TextStyle(
                          color: Colors.white,
                        ),
                        backgroundColor: const Color.fromRGBO(166, 184, 199, 1),
                        selectedColor: game.league == League.afl
                            ? const Color.fromRGBO(206, 0, 33, 1)
                            : const Color.fromARGB(100, 0, 207, 93),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                        selected: latestGameTip != null &&
                            latestGameTip.tip.index == index,
                        onSelected: (bool selected) {
                          Tip tip = Tip(
                            tipper: currentTipper,
                            game: game,
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
                          tipsViewModel.addTip(tip);
                        },
                      );
                    }
                  },
                );
              },
            ).toList(),
          );
        }
      },
    );
  }
}
