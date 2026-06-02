import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_update_report.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';

class AdminDaucompsEditFixtureButton extends StatelessWidget {
  static const String webDisabledTooltip =
      'Fixture download is disabled on web because browser cross-origin restrictions block the fixture source.';

  final DAUCompsViewModel dauCompsViewModel;
  final DAUComp? daucomp;
  // This callback is expected to be `(fn) => parent.setState(fn)`.
  // The `fn` passed to it should be the code that was originally in `setState`.
  final Function(VoidCallback fn) setStateCallback;
  final Function(bool disabled) onDisableBack;
  final bool? isWebOverride;

  const AdminDaucompsEditFixtureButton({
    super.key,
    required this.dauCompsViewModel,
    required this.daucomp,
    required this.setStateCallback,
    required this.onDisableBack,
    this.isWebOverride,
  });

  @override
  Widget build(BuildContext context) {
    if (daucomp == null) {
      return const SizedBox.shrink();
    } else {
      final isWebPlatform = isWebOverride ?? kIsWeb;
      if (isWebPlatform) {
        return const Tooltip(
          message: webDisabledTooltip,
          child: OutlinedButton(
            onPressed: null,
            child: Text('Download'),
          ),
        );
      }

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
    }

    final statsViewModel = dauCompsViewModel.statsViewModel;
    if (statsViewModel == null) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(onPressed: null, child: Text('Run Updates')),
          SizedBox(width: 8),
          _AdminDatabaseStatusIndicator(
            status: AdminDatabaseRefreshStatus.failed(
              'Stats view model unavailable.',
            ),
          ),
        ],
      );
    }

    return ListenableBuilder(
      listenable: statsViewModel,
      builder: (context, _) {
        final isWebPlatform = kIsWeb;
        final isBusy =
            dauCompsViewModel.isDownloading ||
            statsViewModel.isUpdateScoringRunning ||
            statsViewModel.adminDatabaseRefreshStatus.isChecking;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: isBusy
                  ? null
                  : () async {
                      if (dauCompsViewModel.isDownloading) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: League.afl.colour,
                            content: const Text(
                              'Fixture download already in progress',
                            ),
                          ),
                        );
                        return;
                      }
                      if (statsViewModel.isUpdateScoringRunning) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.red,
                            content: Text('Scoring already in progress'),
                          ),
                        );
                        return;
                      }

                      final selectedSteps = await _showAdminUpdateStepsDialog(
                        context,
                        fixtureDownloadAvailable: !isWebPlatform,
                      );
                      if (selectedSteps == null) {
                        return;
                      }
                      if (!selectedSteps.hasAnyStep) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Colors.orange,
                              content: Text('Select at least one update step.'),
                            ),
                          );
                        }
                        return;
                      }

                      var progressDialogShown = false;
                      final adminProgress = ValueNotifier<AdminUpdateProgress>(
                        const AdminUpdateProgress(
                          'Preparing admin update...',
                          null,
                        ),
                      );
                      try {
                        onDisableBack(true);
                        await Future.delayed(const Duration(milliseconds: 100));

                        if (context.mounted) {
                          progressDialogShown = true;
                          unawaited(
                            showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _AdminUpdateProgressDialog(
                                adminProgress: adminProgress,
                                statsViewModel: statsViewModel,
                              ),
                            ),
                          );
                        }

                        String? fixtureResult;
                        if (selectedSteps.downloadFixtures) {
                          adminProgress.value = const AdminUpdateProgress(
                            'Downloading fixtures...',
                            null,
                          );
                          fixtureResult = await dauCompsViewModel
                              .getNetworkFixtureData(daucomp!);
                        }

                        ScoringUpdateReport? report;
                        if (selectedSteps.recalculateScoring) {
                          adminProgress.value = const AdminUpdateProgress(
                            'Refreshing database sources...',
                            null,
                          );
                          await statsViewModel.prepareFreshAdminScoringInputs(
                            daucomp!,
                          );
                          report = await statsViewModel.updateStatsWithReport(
                            daucomp!,
                            null,
                            null,
                            rebuildGameStats: selectedSteps.rebuildGameStats,
                          );
                        }

                        if (context.mounted) {
                          if (progressDialogShown) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                          if (report != null) {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => _ScoringUpdateReportDialog(
                                report: report!,
                                fixtureResult: fixtureResult,
                              ),
                            );
                          } else if (fixtureResult != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.green,
                                content: Text(fixtureResult),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          if (progressDialogShown) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.orange,
                              content: Text(
                                _adminUpdateErrorMessage(
                                  e,
                                  selectedSteps.recalculateScoring,
                                ),
                              ),
                              duration: const Duration(seconds: 6),
                            ),
                          );
                        }
                      } finally {
                        adminProgress.dispose();
                        if (context.mounted) {
                          onDisableBack(false);
                        }
                      }
                    },
              child: Text(!isBusy ? 'Run Updates' : 'Updating...'),
            ),
            const SizedBox(width: 8),
            _AdminDatabaseStatusIndicator(
              status: statsViewModel.adminDatabaseRefreshStatus,
            ),
          ],
        );
      },
    );
  }
}

String _adminUpdateErrorMessage(Object error, bool wasScoringSelected) {
  if (wasScoringSelected &&
      (error is TimeoutException ||
          error is StateError ||
          error.toString().contains('Database freshness check failed'))) {
    return 'Could not confirm the latest data. Check the connection and try again.';
  }

  return wasScoringSelected
      ? 'Could not update scores. Please try again.'
      : 'Could not complete the update. Please try again.';
}

class _AdminDatabaseStatusIndicator extends StatelessWidget {
  final AdminDatabaseRefreshStatus status;

  const _AdminDatabaseStatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label, tooltip) = switch (status.state) {
      AdminDatabaseRefreshState.unknown => (
        Icons.help_outline,
        Colors.grey,
        'Not checked',
        'The app will check for fresh data before updating scores.',
      ),
      AdminDatabaseRefreshState.checking => (
        Icons.sync,
        Colors.blue,
        'Checking',
        'Checking that the latest data is available.',
      ),
      AdminDatabaseRefreshState.fresh => (
        Icons.cloud_done_outlined,
        Colors.green,
        'Ready',
        'Latest data confirmed.',
      ),
      AdminDatabaseRefreshState.blocked => (
        Icons.cloud_off_outlined,
        Colors.orange,
        'Try again',
        'Latest data could not be confirmed. Check the connection and try again.',
      ),
      AdminDatabaseRefreshState.failed => (
        Icons.error_outline,
        Colors.red,
        'Needs attention',
        'The update could not start. Check the connection and try again.',
      ),
    };

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminUpdateStepSelection {
  final bool downloadFixtures;
  final bool recalculateScoring;
  final bool rebuildGameStats;

  const AdminUpdateStepSelection({
    required this.downloadFixtures,
    required this.recalculateScoring,
    required this.rebuildGameStats,
  });

  bool get hasAnyStep =>
      downloadFixtures || recalculateScoring || rebuildGameStats;
}

class AdminUpdateProgress {
  final String message;
  final double? value;

  const AdminUpdateProgress(this.message, this.value);
}

Future<AdminUpdateStepSelection?> _showAdminUpdateStepsDialog(
  BuildContext context, {
  required bool fixtureDownloadAvailable,
}) {
  var downloadFixtures = false;
  var recalculateScoring = true;
  var rebuildGameStats = true;

  return showDialog<AdminUpdateStepSelection>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Run admin updates'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fixture downloads and scoring updates are normally handled automatically. Use these manual repair steps only when you see fixture, scoring, or average point issues.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: downloadFixtures,
                  onChanged: fixtureDownloadAvailable
                      ? (value) {
                          setDialogState(() {
                            downloadFixtures = value ?? false;
                          });
                        }
                      : null,
                  title: const Text('Download fixtures'),
                  subtitle: Text(
                    fixtureDownloadAvailable
                        ? 'Fetch latest fixture scores and save game updates.'
                        : AdminDaucompsEditFixtureButton.webDisabledTooltip,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: recalculateScoring,
                  onChanged: (value) {
                    setDialogState(() {
                      recalculateScoring = value ?? false;
                      if (!recalculateScoring) {
                        rebuildGameStats = false;
                      }
                    });
                  },
                  title: const Text('Recalculate scoring'),
                  subtitle: const Text('Rebuild round points and leaderboards.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: rebuildGameStats,
                  onChanged: recalculateScoring
                      ? (value) {
                          setDialogState(() {
                            rebuildGameStats = value ?? false;
                          });
                        }
                      : null,
                  title: const Text('Rebuild game averages'),
                  subtitle: const Text(
                    'Refresh paid and free average points for completed games.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  AdminUpdateStepSelection(
                    downloadFixtures: downloadFixtures,
                    recalculateScoring: recalculateScoring,
                    rebuildGameStats: rebuildGameStats,
                  ),
                ),
                child: const Text('Run'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ScoringUpdateReportDialog extends StatelessWidget {
  final ScoringUpdateReport report;
  final String? fixtureResult;

  const _ScoringUpdateReportDialog({required this.report, this.fixtureResult});

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
                if (fixtureResult != null) ...[
                  const SizedBox(height: 8),
                  Text('Fixture download: $fixtureResult'),
                ],
                const SizedBox(height: 8),
                Text(
                  report.summaryLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                      lines: _buildLeaderboardChangeLines(change),
                    ),
                  ),
                ],
                if (report.roundChanges.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Round point changes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...report.roundChanges.map(
                    (change) => _ScoringChangeCard(
                      title: 'Round ${change.roundNumber} • ${change.tipperName}',
                      lines: _buildRoundChangeLines(change),
                    ),
                  ),
                ],
                if (report.gameStatsChanges.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Game average changes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...report.gameStatsChanges.map(
                    (change) => _ScoringChangeCard(
                      title: '${change.gameName} • ${change.cohortLabel}',
                      lines: _buildGameStatsChangeLines(change),
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

class _AdminUpdateProgressDialog extends StatelessWidget {
  final ValueListenable<AdminUpdateProgress> adminProgress;
  final StatsViewModel statsViewModel;

  const _AdminUpdateProgressDialog({
    required this.adminProgress,
    required this.statsViewModel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Running updates'),
      content: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[adminProgress, statsViewModel]),
        builder: (context, _) {
          final progressValue =
              statsViewModel.scoringProgressValue ?? adminProgress.value.value;
          final progressMessage =
              statsViewModel.scoringProgressMessage ?? adminProgress.value.message;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: progressValue),
              const SizedBox(height: 16),
              Text(progressMessage),
              const SizedBox(height: 8),
              const Text('Keep this screen open until the report appears.'),
            ],
          );
        },
      ),
    );
  }
}

List<String> _buildLeaderboardChangeLines(ScoringLeaderboardChange change) {
  final lines = <String>[];

  if (change.beforeRank != change.afterRank) {
    lines.add(
      'Rank ${change.beforeRank} -> ${change.afterRank} (${_formatRankDelta(change.rankDelta)})',
    );
  }
  if (change.beforeTotal != change.afterTotal) {
    lines.add(
      _formatMetricChange('Total', change.beforeTotal, change.afterTotal),
    );
  }

  final leagueChanges = <String>[];
  if (change.beforeNrl != change.afterNrl) {
    leagueChanges.add(
      _formatMetricChange('NRL', change.beforeNrl, change.afterNrl),
    );
  }
  if (change.beforeAfl != change.afterAfl) {
    leagueChanges.add(
      _formatMetricChange('AFL', change.beforeAfl, change.afterAfl),
    );
  }
  if (leagueChanges.isNotEmpty) {
    lines.add(leagueChanges.join(', '));
  }

  final standingChanges = <String>[];
  if (change.beforeRoundsWon != change.afterRoundsWon) {
    standingChanges.add(
      _formatMetricChange(
        'Rounds won',
        change.beforeRoundsWon,
        change.afterRoundsWon,
      ),
    );
  }
  if (change.beforeMargins != change.afterMargins) {
    standingChanges.add(
      _formatMetricChange(
        'Margins',
        change.beforeMargins,
        change.afterMargins,
      ),
    );
  }
  if (change.beforeUps != change.afterUps) {
    standingChanges.add(
      _formatMetricChange('UPS', change.beforeUps, change.afterUps),
    );
  }
  if (standingChanges.isNotEmpty) {
    lines.add(standingChanges.join(', '));
  }

  return lines;
}

List<String> _buildRoundChangeLines(ScoringRoundChange change) {
  final lines = <String>[];

  if (change.beforeTotal != change.afterTotal) {
    lines.add(
      _formatMetricChange('Total', change.beforeTotal, change.afterTotal),
    );
  }

  final leagueChanges = <String>[];
  if (change.beforeNrl != change.afterNrl) {
    leagueChanges.add(
      _formatMetricChange('NRL', change.beforeNrl, change.afterNrl),
    );
  }
  if (change.beforeAfl != change.afterAfl) {
    leagueChanges.add(
      _formatMetricChange('AFL', change.beforeAfl, change.afterAfl),
    );
  }
  if (leagueChanges.isNotEmpty) {
    lines.add(leagueChanges.join(', '));
  }

  if (change.beforeRank != change.afterRank) {
    lines.add(
      'Round rank ${change.beforeRank} -> ${change.afterRank} (${_formatRankDelta(change.rankDelta)})',
    );
  }

  return lines;
}

List<String> _buildGameStatsChangeLines(ScoringGameStatsChange change) {
  final lines = <String>[];

  if (change.beforeAveragePoints != change.afterAveragePoints) {
    lines.add(
      'Avg ${_formatNullableDouble(change.beforeAveragePoints)} -> ${_formatNullableDouble(change.afterAveragePoints)}',
    );
  }

  return lines;
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

String _formatMetricChange(String label, int before, int after) {
  return '$label $before -> $after (${_formatSignedDelta(after - before)})';
}

String _formatNullableDouble(double? value) {
  return value == null ? 'missing' : value.toStringAsPrecision(2);
}
