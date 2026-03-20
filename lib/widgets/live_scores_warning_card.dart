import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring_modal.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

/// Amber warning card displayed on stats pages when leaderboard scores
/// include crowd-sourced live data instead of official fixture results.
class LiveScoresWarningCard extends StatelessWidget with WatchItMixin {
  LiveScoresWarningCard({super.key});

  @override
  Widget build(BuildContext context) {
    final bool hasLiveScores = di.isRegistered<StatsViewModel>()
        ? watchIt<StatsViewModel>().hasLiveScoresInUse
        : false;

    if (!hasLiveScores) return const SizedBox.shrink();

    final int liveScoreCount =
        di<StatsViewModel>().gamesWithLiveScores.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: InkWell(
        onTap: () => _showLiveScoreDetails(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Stats may include in-progress or incorrect live scores for '
                  '$liveScoreCount ${liveScoreCount == 1 ? 'game' : 'games'} '
                  '— final results may differ.',
                  style: TextStyle(
                    color: Colors.amber.shade900,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(Icons.info, color: Colors.amber.shade800),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLiveScoreDetails(BuildContext context) async {
    final games = di<StatsViewModel>().gamesWithLiveScores;
    final Game? selectedGame = await showDialog<Game>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Games using interim scores'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'If required update game scores below to reflect actual game '
              'result. Stats will be updated accordingly.',
            ),
            ...games.map(
              (game) => InkWell(
                onTap: () => Navigator.pop(dialogContext, game),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${game.homeTeam.name}  '
                          '${game.scoring?.currentScore(ScoringTeam.home) ?? 0}'
                          ' - '
                          '${game.scoring?.currentScore(ScoringTeam.away) ?? 0}'
                          '  ${game.awayTeam.name}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      const Icon(Icons.edit, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (selectedGame != null && context.mounted) {
      await _openLiveScoringModal(context, selectedGame);
      if (context.mounted && di<StatsViewModel>().hasLiveScoresInUse) {
        await _showLiveScoreDetails(context);
      }
    }
  }

  Future<void> _openLiveScoringModal(BuildContext context, Game game) async {
    final dauCompsVM = context.read<DAUCompsViewModel>();
    final tipsVM = dauCompsVM.selectedTipperTipsViewModel;
    if (tipsVM == null) return;
    final tipper = di<TippersViewModel>().selectedTipper;
    final Tip? tip = await tipsVM.findTip(game, tipper);
    if (tip == null || !context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => LiveScoringModal(tip),
    );
  }
}
