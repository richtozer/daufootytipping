import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/view_models/gametips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring_modal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class LiveScoring extends StatelessWidget {
  const LiveScoring(
      {super.key,
      required this.tipGame,
      required this.dauround,
      required this.gameTipsViewModel,
      required this.selectedDAUComp});

  final GameTipsViewModel gameTipsViewModel;
  final TipGame tipGame;
  final DAUComp selectedDAUComp;
  final DAURound dauround;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameTipsViewModel>.value(
        value: gameTipsViewModel,
        child: Consumer<GameTipsViewModel>(
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
                    gameTipsViewModelConsumer.tipGame?.game.gameState ==
                            GameState.startedResultNotKnown
                        ? liveScoring(
                            gameTipsViewModelConsumer.tipGame!, context)
                        : fixtureScoresAvailable(
                            gameTipsViewModelConsumer.tipGame!),
                    gameTipsViewModelConsumer.tipGame?.game.gameState ==
                            GameState.startedResultNotKnown
                        ? Text(
                            'Interim Result: ${gameTipsViewModelConsumer.tipGame?.getGameResultText()}')
                        : Text(
                            'Result: ${gameTipsViewModelConsumer.tipGame?.getGameResultText()}'),
                    Row(
                      children: [
                        !tipGame.isDefaultTip()
                            ? Text(gameTipsViewModelConsumer
                                        .tipGame?.game.league ==
                                    League.nrl
                                ? 'Your tip: ${gameTipsViewModelConsumer.tipGame?.tip.nrl}'
                                : 'Your tip: ${gameTipsViewModelConsumer.tipGame?.tip.afl}')
                            : Row(
                                children: [
                                  Text(gameTipsViewModelConsumer
                                              .tipGame?.game.league ==
                                          League.nrl
                                      ? 'Your tip: ${gameTipsViewModelConsumer.tipGame?.tip.nrl}'
                                      : 'Your tip: ${gameTipsViewModelConsumer.tipGame?.tip.afl}'),
                                  InkWell(
                                    onTap: () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          duration: Duration(seconds: 7),
                                          backgroundColor: Colors.yellow,
                                          content: Text(
                                              style: TextStyle(
                                                  color: Colors.black),
                                              'You were automatically given a default tip of [Away] '
                                              'for this game. With the world\'s best Footy Tipping app, you have no excuse to miss a tip! 😄'),
                                        ),
                                      );
                                    },
                                    child: const Icon(Icons.info_outline),
                                  )
                                ],
                              ),
                      ],
                    ),
                    gameTipsViewModelConsumer.tipGame?.game.gameState ==
                            GameState.startedResultNotKnown
                        ? Text(
                            'Interim points: ${gameTipsViewModelConsumer.tipGame?.getTipScoreCalculated()} / ${gameTipsViewModelConsumer.tipGame?.getMaxScoreCalculated()}')
                        : Text(
                            'Points: ${gameTipsViewModelConsumer.tipGame?.getTipScoreCalculated()} / ${gameTipsViewModelConsumer.tipGame?.getMaxScoreCalculated()}'),
                  ],
                ),
              ],
            ),
          );
        }));
  }

  Widget liveScoring(TipGame consumerTipGame, BuildContext context) {
    return GestureDetector(
      onTap: () => showMaterialModalBottomSheet(
          expand: false,
          context: context,
          builder: (context) => LiveScoringModal(consumerTipGame, dauround)),
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

  Row fixtureScoresAvailable(TipGame consumerTipGame) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${consumerTipGame.game.scoring?.currentScore(ScoringTeam.home)}',
            style: consumerTipGame.game.scoring!.didHomeTeamWin()
                ? const TextStyle(
                    fontSize: 18,
                    backgroundColor: Colors.lightGreen,
                    fontWeight: FontWeight.w900)
                : null),
        const Text(textAlign: TextAlign.left, ' v '),
        Text('${consumerTipGame.game.scoring?.currentScore(ScoringTeam.away)}',
            style: consumerTipGame.game.scoring!.didAwayTeamWin()
                ? const TextStyle(
                    fontSize: 18,
                    backgroundColor: Colors.lightGreen,
                    fontWeight: FontWeight.w900)
                : null),
      ],
    );
  }
}
