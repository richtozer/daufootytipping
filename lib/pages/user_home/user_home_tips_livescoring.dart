import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:flutter/material.dart';

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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${tipGame.game.scoring?.homeTeamScore}',
                      style: tipGame.game.scoring!.didHomeTeamWin()
                          ? const TextStyle(
                              fontSize: 18,
                              backgroundColor: Color(0xff04cf5d),
                              fontWeight: FontWeight.w900)
                          : null),
                  const Text(textAlign: TextAlign.left, ' v '),
                  Text('${tipGame.game.scoring?.awayTeamScore}',
                      style: tipGame.game.scoring!.didAwayTeamWin()
                          ? const TextStyle(
                              fontSize: 18,
                              backgroundColor: Color(0xff04cf5d),
                              fontWeight: FontWeight.w900)
                          : null),
                ],
              ),
              Text('Result: ${tipGame.getGameResultText()}'),
              Row(
                children: [
                  !tipGame.isDefaultTip()
                      ? Text(tipGame.game.league == League.nrl
                          ? 'Tip: ${tipGame.tip.nrl}'
                          : 'Tip: ${tipGame.tip.afl}')
                      : Row(
                          children: [
                            Text(tipGame.game.league == League.nrl
                                ? 'Tip: ${tipGame.tip.nrl}'
                                : 'Tip: ${tipGame.tip.afl}'),
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
                  'Score: ${tipGame.getTipScoreCalculated()} / ${tipGame.getMaxScoreCalculated()}'),
            ],
          ),
        ],
      ),
    );
  }
}
