import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/widgets/live_scores_warning_card.dart';
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
  late bool _hadOfficialFixtureScore;
  late StatsViewModel _statsViewModel;

  @override
  void initState() {
    super.initState();
    _statsViewModel = context.read<StatsViewModel?>() ?? di<StatsViewModel>();
    _hadOfficialFixtureScore = _hasOfficialFixtureScore(
      widget.gameTipsViewModel.game,
    );
    widget.gameTipsViewModel.addListener(_handleGameTipUpdated);
    _statsViewModel.getGamesStatsEntry(
      widget.gameTipsViewModel.game,
      false,
    );
  }

  @override
  void didUpdateWidget(covariant ScoringTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameTipsViewModel == widget.gameTipsViewModel) {
      return;
    }

    oldWidget.gameTipsViewModel.removeListener(_handleGameTipUpdated);
    _hadOfficialFixtureScore = _hasOfficialFixtureScore(
      widget.gameTipsViewModel.game,
    );
    widget.gameTipsViewModel.addListener(_handleGameTipUpdated);
    _statsViewModel.getGamesStatsEntry(
      widget.gameTipsViewModel.game,
      false,
    );
  }

  void _handleGameTipUpdated() {
    final game = widget.gameTipsViewModel.game;
    final hasOfficialFixtureScore = _hasOfficialFixtureScore(game);
    if (hasOfficialFixtureScore && !_hadOfficialFixtureScore) {
      _statsViewModel.getGamesStatsEntry(game, true);
    }
    _hadOfficialFixtureScore = hasOfficialFixtureScore;
  }

  bool _hasOfficialFixtureScore(Game game) {
    return game.scoring?.homeTeamScore != null &&
        game.scoring?.awayTeamScore != null;
  }

  @override
  void dispose() {
    widget.gameTipsViewModel.removeListener(_handleGameTipUpdated);
    super.dispose();
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
          final isInterimScore = _isInterimScore(game);

          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: _buildScoringTileContent(
              context,
              isInterimScore,
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildResultText(game, tip),
                  _buildTipRow(tip, league),
                  _buildPointsText(game, tip),
                  Selector<StatsViewModel?, GameStatsEntry?>(
                    selector: (_, statsViewModel) =>
                        statsViewModel?.gameStatsEntryFor(game),
                    builder: (_, gameStatsEntry, _) {
                      return _buildAveragePointsRow(
                        game,
                        gameStatsEntry,
                        tip,
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isInterimScore(Game game) {
    final scoring = game.scoring;
    final hasCrowdSourcedScore =
        scoring?.crowdSourcedScores?.isNotEmpty ?? false;
    final hasFinalFixtureScore =
        scoring?.homeTeamScore != null && scoring?.awayTeamScore != null;
    return hasCrowdSourcedScore && !hasFinalFixtureScore;
  }

  Widget _buildScoringTileContent(
    BuildContext context,
    bool isInterimScore,
    Widget child,
  ) {
    if (!isInterimScore) return child;

    return Tooltip(
      message: 'Scores are based on interim live score data.',
      child: InkWell(
        onTap: () => LiveScoresWarningCard.showLiveScoreDetails(context),
        borderRadius: BorderRadius.circular(8.0),
        child: child,
      ),
    );
  }

  Widget _buildResultText(Game game, Tip? tip) {
    final resultText = tip?.getGameResultText() ?? 'N/A';

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
                  'Result: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Flexible(
                  child: Text(resultText, overflow: TextOverflow.ellipsis),
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
                            'You did not tip this game and were automatically given a default tip of [Away].\n\n'
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
    final pointsText = _hasGameResult(game)
        ? '${tip?.getTipPointsCalculated()} / ${tip?.getMaxPointsCalculated()}'
        : '? / ?';

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
                  'Your Points: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Flexible(
                  child: Text(pointsText, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAveragePointsRow(
    Game game,
    GameStatsEntry? gameStatsEntry,
    Tip? tip,
  ) {
    final averagePoints = gameStatsEntry?.averagePoints;
    late final String averageText;
    if (!_hasGameResult(game)) {
      averageText = '? / ?';
    } else if (averagePoints != null) {
      averageText =
          '${averagePoints.toStringAsPrecision(2)} / ${tip?.getMaxPointsCalculated()}';
    } else {
      averageText = '? / ${tip?.getMaxPointsCalculated()}';
    }

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Tooltip(
              message:
                  'This is the average points collected by tippers for this game. Your aim is to collect more points than this to improve your ranking. If the game score is not finalised then this is an interim average.',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Avg Points: ',
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

  bool _hasGameResult(Game game) {
    final scoring = game.scoring;
    return scoring != null &&
        scoring.getGameResultCalculated(game.league) != GameResult.z;
  }
}
