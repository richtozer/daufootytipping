import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class LiveScoring extends StatelessWidget {
  const LiveScoring({
    super.key,
    required this.tipGame,
  });

  final TipGame tipGame;

  @override
  Widget build(BuildContext context) {
    return Consumer<GameTipsViewModel>(
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
                    : finishedScoring(),
                Text(
                    'Result: ${gameTipsViewModelConsumer.tipGame?.getGameResultText()}'),
                Row(
                  children: [
                    !tipGame.isDefaultTip()
                        ? Text(gameTipsViewModelConsumer.tipGame?.game.league ==
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      duration: Duration(seconds: 7),
                                      backgroundColor: Colors.yellow,
                                      content: Text(
                                          style: TextStyle(color: Colors.black),
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
    });
  }

  Row liveScoring(TipGame consumerTipGame) {
    TextEditingController homeScoreController = TextEditingController(
        text: '${consumerTipGame.game.scoring?.currentHomeScore()}');
    TextEditingController awayScoreController = TextEditingController(
        text: '${consumerTipGame.game.scoring?.currentAwayScore()}');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🏉 Live: '),
        SizedBox(
          width: 35,
          child: Tooltip(
            message: 'Enter the current home team score here',
            child: TextField(
                decoration: null,
                maxLength: 3,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: false),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                controller: homeScoreController,
                onSubmitted: (value) {
                  liveScoreUpdated(value, ScoreTeam.home);
                }),
          ),
        ),
        const Text(' v '),
        SizedBox(
          width: 35,
          child: Tooltip(
            message: 'Enter the current away team score here',
            child: TextField(
                decoration: null,
                maxLength: 3,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: false),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                controller: awayScoreController,
                onChanged: (value) {
                  liveScoreUpdated(value, ScoreTeam.away);
                }),
          ),
        ),
      ],
    );
  }

  Row finishedScoring() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${tipGame.game.scoring?.homeTeamScore ?? ''}',
            style: tipGame.game.scoring!.didHomeTeamWin()
                ? const TextStyle(
                    fontSize: 18,
                    backgroundColor: Color(0xff04cf5d),
                    fontWeight: FontWeight.w900)
                : null),
        const Text(textAlign: TextAlign.left, ' v '),
        Text('${tipGame.game.scoring?.awayTeamScore ?? ''}',
            style: tipGame.game.scoring!.didAwayTeamWin()
                ? const TextStyle(
                    fontSize: 18,
                    backgroundColor: Color(0xff04cf5d),
                    fontWeight: FontWeight.w900)
                : null),
      ],
    );
  }

  void liveScoreUpdated(dynamic score, ScoreTeam scoreTeam) {
    if (score.isNotEmpty) {
      CrowdSourcedScore croudSourcedScore = CrowdSourcedScore(
          DateTime.now().toUtc(),
          scoreTeam,
          tipGame.tipper.dbkey!,
          int.tryParse(score)!,
          false);

      tipGame.game.scoring?.croudSourcedScores ??= [];

      tipGame.game.scoring?.croudSourcedScores?.add(croudSourcedScore);

      di<ScoresViewModel>()
          .writeLiveScoreToDb(tipGame.game.scoring!, tipGame.game);
    }
  }
}
