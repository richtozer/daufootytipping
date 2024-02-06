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
              Text('Home: ${tip.game.scoring?.homeTeamScore}'),
              Text(
                'Away: ${tip.game.scoring?.awayTeamScore}',
              ),
              Text(tip.game.league == League.nrl
                  ? 'Result: ${tip.game.scoring?.getGameResultCalculated(tip.game.league).nrl}'
                  : 'Result: ${tip.game.scoring?.getGameResultCalculated(tip.game.league).afl}'),
              Text(tip.game.league == League.nrl
                  ? 'Tip: ${tip.tip.nrl} Default: ${tip.isDefaultTip()}'
                  : 'Tip: ${tip.tip.afl} Default: ${tip.isDefaultTip()}'),
              Text(
                  'Score: ${Scoring.getTipScoreCalculated(tip.game.league, tip.game.scoring!.getGameResultCalculated(tip.game.league), tip.tip)} / ${Scoring.getTipScoreCalculated(tip.game.league, tip.game.scoring!.getGameResultCalculated(tip.game.league), tip.game.scoring!.getGameResultCalculated(tip.game.league))}'),
            ],
          ),
        ],
      ),
    );
  }
}
