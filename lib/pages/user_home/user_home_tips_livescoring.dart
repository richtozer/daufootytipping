import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LiveScoring extends StatelessWidget {
  const LiveScoring({
    super.key,
    required this.tipGame,
  });

  final TipGame tipGame;

  @override
  Widget build(BuildContext context) {
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
              tipGame.game.gameState == GameState.resultNotKnown
                  ? liveScoring()
                  : finishedScoring(),
              Text('Result: ${tipGame.getGameResultText()}'),
              Row(
                children: [
                  !tipGame.isDefaultTip()
                      ? Text(tipGame.game.league == League.nrl
                          ? 'Your tip: ${tipGame.tip.nrl}'
                          : 'Your tip: ${tipGame.tip.afl}')
                      : Row(
                          children: [
                            Text(tipGame.game.league == League.nrl
                                ? 'Your tip: ${tipGame.tip.nrl}'
                                : 'Your tip: ${tipGame.tip.afl}'),
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
                  'Your points: ${tipGame.getTipScoreCalculated()} / ${tipGame.getMaxScoreCalculated()}'),
            ],
          ),
        ],
      ),
    );
  }

  Row liveScoring() {
    TextEditingController homeScoreController = TextEditingController(
        text: '${tipGame.game.scoring?.homeTeamScore ?? ''}');
    TextEditingController awayScoreController = TextEditingController(
        text: '${tipGame.game.scoring?.awayTeamScore ?? ''}');

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
                onChanged: (value) {
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
          tipGame.tipper,
          scoreTeam,
          int.tryParse(score)!,
          false);

      tipGame.game.scoring!.homeTeamCroudSourcedScore1 = croudSourcedScore;
    }
  }
}
