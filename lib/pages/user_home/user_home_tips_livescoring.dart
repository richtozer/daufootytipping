import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class LiveScoring extends StatelessWidget {
  const LiveScoring(
      {super.key,
      required this.tipGame,
      required this.gameTipsViewModel,
      required this.selectedDAUComp});

  final GameTipsViewModel gameTipsViewModel;
  final TipGame tipGame;
  final DAUComp selectedDAUComp;

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
                            GameState.resultNotKnown
                        ? liveScoring(gameTipsViewModelConsumer.tipGame!)
                        : finishedScoring(gameTipsViewModelConsumer.tipGame!),
                    gameTipsViewModelConsumer.tipGame?.game.gameState ==
                            GameState.resultNotKnown
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
                    Text(
                        'Your points: ${gameTipsViewModelConsumer.tipGame?.getTipScoreCalculated()} / ${gameTipsViewModelConsumer.tipGame?.getMaxScoreCalculated()}'),
                  ],
                ),
              ],
            ),
          );
        }));
  }

  Row liveScoring(TipGame consumerTipGame) {
    TextEditingController homeScoreController = TextEditingController(
        text: consumerTipGame.game.scoring?.currentHomeScore() == null
            ? '0'
            : '${consumerTipGame.game.scoring?.currentHomeScore()}');
    TextEditingController awayScoreController = TextEditingController(
        text: consumerTipGame.game.scoring?.currentAwayScore() == null
            ? '0'
            : '${consumerTipGame.game.scoring?.currentAwayScore()}');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🏉'),
        SizedBox(
          width: 35,
          child: Tooltip(
            message: 'Enter the current home team score here',
            child: TextField(
                textAlign: TextAlign.center,
                decoration: null,
                maxLength: 3,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                controller: homeScoreController,
                textInputAction: TextInputAction.done,
                onTap: () => homeScoreController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: homeScoreController.value.text.length),
                onSubmitted: (value) {
                  liveScoreUpdated(
                      value, ScoreTeam.home, consumerTipGame, selectedDAUComp);
                }),
          ),
        ),
        const Text(' v '),
        SizedBox(
          width: 35,
          child: Tooltip(
            message: 'Enter the current away team score here',
            child: TextField(
                textAlign: TextAlign.center,
                decoration: null,
                maxLength: 3,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                controller: awayScoreController,
                textInputAction: TextInputAction.done,
                onTap: () => awayScoreController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: awayScoreController.value.text.length),
                onSubmitted: (value) {
                  liveScoreUpdated(
                      value, ScoreTeam.away, consumerTipGame, selectedDAUComp);
                }),
          ),
        ),
        const Text('🏉'),
      ],
    );
  }

  Row finishedScoring(TipGame consumerTipGame) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${consumerTipGame.game.scoring?.currentHomeScore()}',
            style: consumerTipGame.game.scoring!.didHomeTeamWin()
                ? const TextStyle(
                    fontSize: 18,
                    backgroundColor: Color(0xff04cf5d),
                    fontWeight: FontWeight.w900)
                : null),
        const Text(textAlign: TextAlign.left, ' v '),
        Text('${consumerTipGame.game.scoring?.currentAwayScore()}',
            style: consumerTipGame.game.scoring!.didAwayTeamWin()
                ? const TextStyle(
                    fontSize: 18,
                    backgroundColor: Color(0xff04cf5d),
                    fontWeight: FontWeight.w900)
                : null),
      ],
    );
  }

  void liveScoreUpdated(dynamic score, ScoreTeam scoreTeam,
      TipGame consumerTipGame, DAUComp selectedDAUComp) {
    if (score.isNotEmpty) {
      CrowdSourcedScore croudSourcedScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          scoreTeam,
          consumerTipGame.tipper.dbkey!,
          int.tryParse(score)!,
          false);

      consumerTipGame.game.scoring?.croudSourcedScores ??= [];

      consumerTipGame.game.scoring?.croudSourcedScores?.add(croudSourcedScore);

      // only key a maximum of 3 crowd sourced scores per scoreTeam i.e scoreTeam.away or scoreTeam.home
      // delete the oldest score if there are more than 3
      if (consumerTipGame.game.scoring?.croudSourcedScores != null &&
          consumerTipGame.game.scoring!.croudSourcedScores!
                  .where((element) => element.scoreTeam == scoreTeam)
                  .length >
              3) {
        consumerTipGame.game.scoring!.croudSourcedScores!.removeWhere(
            (element) =>
                element.scoreTeam == scoreTeam &&
                element.submittedTimeUTC ==
                    consumerTipGame.game.scoring!.croudSourcedScores!
                        .where((element) => element.scoreTeam == scoreTeam)
                        .reduce((value, element) => value.submittedTimeUTC
                                .isBefore(element.submittedTimeUTC)
                            ? value
                            : element)
                        .submittedTimeUTC);
      }

      di<AllScoresViewModel>().writeLiveScoreToDb(
          consumerTipGame.game.scoring!, consumerTipGame.game);

      //update scoring for everybody for this round
      // di<DAUCompsViewModel>()
      //     .updateScoring(selectedDAUComp, null, consumerTipGame.game.dauRound);
      di<DAUCompsViewModel>().updateScoring(selectedDAUComp, null, null);
    }
  }
}
