import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring_modal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class ScoringTile extends StatelessWidget {
  const ScoringTile(
      {super.key,
      required this.tip,
      required this.gameTipsViewModel,
      required this.selectedDAUComp});

  final GameTipViewModel gameTipsViewModel;
  final Tip tip;
  final DAUComp selectedDAUComp;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameTipViewModel>.value(
        value: gameTipsViewModel,
        child: Consumer<GameTipViewModel>(
            builder: (context, gameTipsViewModelConsumer, child) {
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    gameTipsViewModelConsumer.game.gameState ==
                            GameState.startedResultNotKnown
                        ? liveScoring(gameTipsViewModelConsumer.tip!, context)
                        : fixtureScoring(gameTipsViewModelConsumer),
                    gameTipsViewModelConsumer.game.gameState ==
                            GameState.startedResultNotKnown
                        ? Text(
                            'Interim Result: ${gameTipsViewModelConsumer.tip?.getGameResultText()}')
                        : Text(
                            'Result: ${gameTipsViewModelConsumer.tip?.getGameResultText()}'),
                    Row(
                      children: [
                        !tip.isDefaultTip()
                            ? Text(gameTipsViewModelConsumer.tip?.game.league ==
                                    League.nrl
                                ? 'Your tip: ${gameTipsViewModelConsumer.tip?.tip.nrl}'
                                : 'Your tip: ${gameTipsViewModelConsumer.tip?.tip.afl}')
                            : Row(
                                children: [
                                  Text(gameTipsViewModelConsumer
                                              .tip?.game.league ==
                                          League.nrl
                                      ? 'Your tip: ${gameTipsViewModelConsumer.tip?.tip.nrl}'
                                      : 'Your tip: ${gameTipsViewModelConsumer.tip?.tip.afl}'),
                                  InkWell(
                                    onTap: () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          duration: Duration(seconds: 10),
                                          backgroundColor: Colors.orange,
                                          content: Text(
                                              style: TextStyle(
                                                  color: Colors.black),
                                              'You did not tip this game and were automatically given a default tip of [Away] for this game.\n\n'
                                              'The app will send out reminders to late tippers, however you need to keep notifications from DAU Tips turned on in your phone settings.\n\nWith the world\'s best Footy Tipping app, you have no excuse to miss a tip! 😄'),
                                        ),
                                      );
                                    },
                                    child: const Icon(Icons.info_outline),
                                  )
                                ],
                              ),
                      ],
                    ),
                    gameTipsViewModelConsumer.tip?.game.gameState ==
                            GameState.startedResultNotKnown
                        ? Text(
                            'Interim points: ${gameTipsViewModelConsumer.tip?.getTipScoreCalculated()} / ${gameTipsViewModelConsumer.tip?.getMaxScoreCalculated()}')
                        : Text(
                            'Points: ${gameTipsViewModelConsumer.tip?.getTipScoreCalculated()} / ${gameTipsViewModelConsumer.tip?.getMaxScoreCalculated()}'),
                  ],
                ),
              ],
            ),
          );
        }));
  }

  Widget liveScoring(Tip consumerTipGame, BuildContext context) {
    return GestureDetector(
      onTap: () => showMaterialModalBottomSheet(
          expand: false,
          context: context,
          builder: (context) => LiveScoringModal(consumerTipGame)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.edit),
          SizedBox(
            width: 70,
            child: Tooltip(
              message: 'Click here to enter live scores',
              child: Text(
                  ' ${consumerTipGame.game.scoring?.currentScore(ScoringTeam.home) ?? '0'} v ${consumerTipGame.game.scoring?.currentScore(ScoringTeam.away) ?? '0'} '),
            ),
          ),
        ],
      ),
    );
  }

  Row fixtureScoring(GameTipViewModel consumerTipGameViewModel) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${consumerTipGameViewModel.game.scoring!.homeTeamScore}',
            style: consumerTipGameViewModel.game.scoring!.didHomeTeamWin()
                ? TextStyle(
                    fontSize: 18,
                    backgroundColor: Colors.lightGreen[200],
                    fontWeight: FontWeight.w900)
                : null),
        const Text(textAlign: TextAlign.left, ' v '),
        Text('${consumerTipGameViewModel.game.scoring!.awayTeamScore}',
            style: consumerTipGameViewModel.game.scoring!.didAwayTeamWin()
                ? TextStyle(
                    fontSize: 18,
                    backgroundColor: Colors.lightGreen[200],
                    fontWeight: FontWeight.w900)
                : null),
      ],
    );
  }
}
