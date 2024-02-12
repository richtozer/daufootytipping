import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:flutter/material.dart';

class LiveScoring extends StatelessWidget {
  const LiveScoring({
    super.key,
    required this.tip,
  });

  final Tip tip;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                  Text('${tip.game.scoring?.homeTeamScore}',
                      style: tip.game.scoring!.didHomeTeamWin()
                          ? const TextStyle(
                              fontSize: 18,
                              backgroundColor: Color(0xff04cf5d),
                              fontWeight: FontWeight.w900)
                          : null),
                  const Text(textAlign: TextAlign.left, ' v '),
                  Text('${tip.game.scoring?.awayTeamScore}',
                      style: tip.game.scoring!.didAwayTeamWin()
                          ? const TextStyle(
                              fontSize: 18,
                              backgroundColor: Color(0xff04cf5d),
                              fontWeight: FontWeight.w900)
                          : null),
                ],
              ),
              Text('Result: ${tip.getGameResultText()}'),
              Row(
                children: [
                  !tip.isDefaultTip()
                      ? Text(tip.game.league == League.nrl
                          ? 'Tip: ${tip.tip.nrl}'
                          : 'Tip: ${tip.tip.afl}')
                      : Row(
                          children: [
                            Text(tip.game.league == League.nrl
                                ? 'Tip: ${tip.tip.nrl}'
                                : 'Tip: ${tip.tip.afl}'),
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
                  'Score: ${tip.getTipScoreCalculated()} / ${tip.getMaxScoreCalculated()}'),
            ],
          ),
        ],
      ),
    );
  }
}
