import 'package:flutter/material.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_update_report.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';

class AdminDaucompsEditFixtureButton extends StatelessWidget {
  final DAUCompsViewModel dauCompsViewModel;
  final DAUComp? daucomp;
  // This callback is expected to be `(fn) => parent.setState(fn)`.
  // The `fn` passed to it should be the code that was originally in `setState`.
  final Function(VoidCallback fn) setStateCallback;
  final Function(bool disabled) onDisableBack;

  const AdminDaucompsEditFixtureButton({
    super.key,
    required this.dauCompsViewModel,
    required this.daucomp,
    required this.setStateCallback,
    required this.onDisableBack,
  });

  @override
  Widget build(BuildContext context) {
    if (daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          if (dauCompsViewModel.isDownloading) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: League.afl.colour,
                content: const Text('Fixture download already in progress'),
              ),
            );
            return;
          }
          try {
            onDisableBack(true);

            String result = await dauCompsViewModel.getNetworkFixtureData(
              daucomp!,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text(result),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: League.afl.colour,
                  content: Text(
                    'An error occurred during fixture download: $e',
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } finally {
            onDisableBack(false);
          }
        },
        child: Text(
          !dauCompsViewModel.isDownloading ? 'Download' : 'Downloading...',
        ),
      );
    }
  }
}

class AdminDaucompsEditScoringButton extends StatelessWidget {
  final DAUCompsViewModel dauCompsViewModel;
  final DAUComp? daucomp;
  final Function(VoidCallback fn) setStateCallback;
  final Function(bool disabled) onDisableBack;

  const AdminDaucompsEditScoringButton({
    super.key,
    required this.dauCompsViewModel,
    required this.daucomp,
    required this.setStateCallback,
    required this.onDisableBack,
  });

  @override
  Widget build(BuildContext context) {
    if (daucomp == null) {
      return const SizedBox.shrink();
    } else {
      return OutlinedButton(
        onPressed: () async {
          if (dauCompsViewModel.statsViewModel?.isUpdateScoringRunning ??
              false) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Scoring already in progress'),
              ),
            );
            return;
          }

          try {
            onDisableBack(true);
            await Future.delayed(const Duration(milliseconds: 100));
            final statsViewModel = dauCompsViewModel.statsViewModel;
            if (statsViewModel == null) {
              throw StateError('statsViewModel is null');
            }

            final report = await statsViewModel.updateStatsWithReport(
              daucomp!,
              null,
              null,
            );
            if (context.mounted) {
              await showDialog<void>(
                context: context,
                builder: (_) => _ScoringUpdateReportDialog(report: report),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(
                    'An error occurred during scoring calculation: $e',
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } finally {
            if (context.mounted) {
              onDisableBack(false);
            }
          }
        },
        child: Text(
          !(dauCompsViewModel.statsViewModel?.isUpdateScoringRunning ?? false)
              ? 'Rescore'
              : 'Scoring...',
        ),
      );
    }
  }
}

class _ScoringUpdateReportDialog extends StatelessWidget {
  final ScoringUpdateReport report;

  const _ScoringUpdateReportDialog({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Rescore complete'),
      content: SizedBox(
        width: 460,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report.resultMessage),
                const SizedBox(height: 8),
                Text(
                  report.summaryLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!report.hasChanges) ...[
                  const SizedBox(height: 12),
                  const Text('No scoring changes detected.'),
                ],
                if (report.leaderboardChanges.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Leaderboard changes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...report.leaderboardChanges.map(
                    (change) => _ScoringChangeCard(
                      title: change.tipperName,
                      lines: [
                        'Rank ${change.beforeRank} -> ${change.afterRank} (${_formatRankDelta(change.rankDelta)})',
                        'Total ${change.beforeTotal} -> ${change.afterTotal} (${_formatSignedDelta(change.totalDelta)})',
                        'NRL ${change.beforeNrl} -> ${change.afterNrl}, AFL ${change.beforeAfl} -> ${change.afterAfl}',
                        'Rounds won ${change.beforeRoundsWon} -> ${change.afterRoundsWon}, Margins ${change.beforeMargins} -> ${change.afterMargins}, UPS ${change.beforeUps} -> ${change.afterUps}',
                      ],
                    ),
                  ),
                ],
                if (report.roundChanges.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Round score changes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...report.roundChanges.map(
                    (change) => _ScoringChangeCard(
                      title: 'Round ${change.roundNumber} • ${change.tipperName}',
                      lines: [
                        'Total ${change.beforeTotal} -> ${change.afterTotal} (${_formatSignedDelta(change.totalDelta)})',
                        'NRL ${change.beforeNrl} -> ${change.afterNrl}, AFL ${change.beforeAfl} -> ${change.afterAfl}',
                        'Round rank ${change.beforeRank} -> ${change.afterRank} (${_formatRankDelta(change.rankDelta)})',
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ScoringChangeCard extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _ScoringChangeCard({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...lines.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(line),
              )),
        ],
      ),
    );
  }
}

String _formatSignedDelta(int delta) {
  if (delta > 0) return '+$delta';
  return '$delta';
}

String _formatRankDelta(int rankDelta) {
  if (rankDelta > 0) return 'up $rankDelta';
  if (rankDelta < 0) return 'down ${rankDelta.abs()}';
  return 'unchanged';
}
