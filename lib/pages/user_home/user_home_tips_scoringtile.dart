import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class ScoringTile extends StatefulWidget {
  const ScoringTile({
    super.key,
    required this.tip,
    required this.gameTipsViewModel,
    required this.selectedDAUComp,
  });

  final GameTipViewModel gameTipsViewModel;
  final Tip tip;
  final DAUComp selectedDAUComp;

  @override
  ScoringTileState createState() => ScoringTileState();
}

class ScoringTileState extends State<ScoringTile> {
  @override
  void initState() {
    super.initState();
    di<StatsViewModel>().getGamesStatsEntry(
      widget.gameTipsViewModel.game,
      false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameTipViewModel>.value(
      value: widget.gameTipsViewModel,
      child: Consumer<GameTipViewModel>(
        builder: (context, gameTipsViewModelConsumer, child) {
          final tip = gameTipsViewModelConsumer.tip;
          final game = gameTipsViewModelConsumer.game;
          final league = tip?.game.league;

          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildResultText(game, tip),
                _buildTipRow(tip, league),
                _buildPointsText(game, tip),
                _buildAverageScoreRow(game, tip),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultText(Game game, Tip? tip) {
    final resultText = tip?.getGameResultText() ?? 'N/A';
    final isInterimResult = game.gameState == GameState.startedResultNotKnown;

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: isInterimResult
                ? Tooltip(
                    message:
                        'This is an interim result based on the current game score. The final result will be available after the game score is finalised.',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '* Result: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Flexible(
                          child: Text(
                            resultText,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Result: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Flexible(
                        child: Text(
                          resultText,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipRow(Tip? tip, League? league) {
    final tipText = league == League.nrl
        ? '${tip?.tip.nrl}'
        : '${tip?.tip.afl}';
    final tipLabel = 'Your tip: ';

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tipLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Flexible(child: Text(tipText, overflow: TextOverflow.ellipsis)),
                if (widget.tip.isDefaultTip())
                  InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          duration: Duration(seconds: 10),
                          backgroundColor: Colors.orange,
                          content: Text(
                            style: TextStyle(color: Colors.black),
                            'You did not tip this game and were automatically given a default tip of [Away] for this game.\n\n'
                            'The app will send out reminders to late tippers, however you need to keep notifications from DAU Tips turned on in your phone settings.\n\nWith the world\'s best Footy Tipping app, you have no excuse to miss a tip! 😄',
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.info_outline),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsText(Game game, Tip? tip) {
    final pointsText =
        '${tip?.getTipScoreCalculated()} / ${tip?.getMaxScoreCalculated()}';
    final isInterimResult = game.gameState == GameState.startedResultNotKnown;

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: isInterimResult
                ? Tooltip(
                    message:
                        'This is an interim result based on the current game score. The final result will be available after the game score is finalised.',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '* Points: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Flexible(
                          child: Text(
                            pointsText,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Your Points: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Flexible(
                        child: Text(
                          pointsText,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAverageScoreRow(Game game, Tip? tip) {
    final averageScore =
        di<StatsViewModel>().gamesStatsEntry[game]?.averageScore;
    final averageText = averageScore != null
        ? '${averageScore.toStringAsPrecision(2)} / ${tip?.getMaxScoreCalculated()}'
        : '? / ${tip?.getMaxScoreCalculated()}';

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Tooltip(
              message:
                  'This is the average score of tips for all tippers for this game. Your aim is to score higher than this to improve your ranking. If the score is not finalised then this is an interim average.',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Average: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Flexible(
                    child: Text(averageText, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
