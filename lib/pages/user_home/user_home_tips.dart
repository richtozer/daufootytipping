import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TippingList extends StatelessWidget {
  const TippingList({super.key});

  Widget buildChoiceChips(
      BuildContext context, Game game, TipsViewModel tipsViewModel) {
    final List<String> options;
    final List<String> optionsTooltips;
    if (game.league == League.nrl) {
      options = GameResult.values.map((e) => e.nrl).toList();
      options.removeLast(); // remove 'No Result' as an option to select
      optionsTooltips = GameResult.values.map((e) => e.nrlTooltip).toList();
    } else {
      options = GameResult.values.map((e) => e.afl).toList();
      options.removeLast(); // remove 'No Result' as an option to elect
      optionsTooltips = GameResult.values.map((e) => e.aflTooltip).toList();
    }
    return Wrap(
        children: List<Widget>.generate(
      options.length,
      (int index) {
        return ChoiceChip.elevated(
            label: Text(options[index]),
            tooltip: optionsTooltips[index],
            showCheckmark: false,
            labelStyle: const TextStyle(
              color: Colors.white,
            ),
            backgroundColor: const Color.fromRGBO(166, 184, 199, 1),
            selectedColor: const Color.fromRGBO(206, 0, 33, 1),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
            selected: tipsViewModel.getLatestGameTip(game)?.tip.index == index,
            onSelected: (bool selected) {
              Tip tip = Tip(
                tipper: Provider.of<TippersViewModel>(context, listen: false)
                        .tippers[
                    Provider.of<TippersViewModel>(context, listen: false)
                        .currentTipperIndex],
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

              Provider.of<TipsViewModel>(context, listen: false).addTip(tip);
            });
      },
    ).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<TipsViewModel>(
        builder: (context, tipsViewModel, child) {
          return CustomScrollView(
            slivers: <Widget>[
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    final game = tipsViewModel.games[index];
                    return Card(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(width: 0.5, color: Colors.grey),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: <Widget>[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  game.homeTeam.getHomeTeamLogo(game),
                                  Text(
                                    '${game.dbkey} - ${game.startTimeUTC.toLocal()} - ${game.homeTeam.name} v ${game.awayTeam.name}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  game.awayTeam.getAwayTeamLogo(game),
                                ],
                              ),
                              buildChoiceChips(context, game, tipsViewModel),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: tipsViewModel.games.length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
