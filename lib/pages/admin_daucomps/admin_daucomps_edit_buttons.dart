import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';

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
    }

    final statsViewModel = dauCompsViewModel.statsViewModel;
    if (statsViewModel == null) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(onPressed: null, child: Text('Run Updates')),
        ],
      );
    }

    return ListenableBuilder(
      listenable: statsViewModel,
      builder: (context, _) {
        final isBusy =
            dauCompsViewModel.isDownloading ||
            statsViewModel.isUpdateScoringRunning;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                      log(
                        'AdminDaucompsEditScoringButton: selected steps: '
                        'downloadFixtures=${selectedSteps.downloadFixtures}, '
                        'recalculateScoring=${selectedSteps.recalculateScoring}',
                      );

                      var progressDialogShown = false;
                      final adminProgress = ValueNotifier<AdminUpdateProgress>(
                        const AdminUpdateProgress(
                          'Preparing admin update...',
                          null,
                        ),
                      );
                      Future<void>? progressDialogClosed;
                      var progressDialogPopRequested = false;
                      try {
                        onDisableBack(true);
                        await Future.delayed(const Duration(milliseconds: 100));

                        if (context.mounted) {
                          progressDialogShown = true;
                          progressDialogClosed = showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => _AdminUpdateProgressDialog(
                              adminProgress: adminProgress,
                              statsViewModel: statsViewModel,
                            ),
                          );
                          unawaited(progressDialogClosed);
                        }

                        String? fixtureResult;
                        if (selectedSteps.downloadFixtures) {
                          log('AdminDaucompsEditScoringButton: starting fixture download step.');
                          adminProgress.value = const AdminUpdateProgress(
                            'Downloading fixtures...',
                            null,
                          );
                          fixtureResult = await dauCompsViewModel
                              .getNetworkFixtureData(daucomp!);
                          log(
                            'AdminDaucompsEditScoringButton: fixture download step completed: $fixtureResult',
                          );
                        }

                        String? scoringResult;
                        final skipUiScoringAfterBackendFixtureDownload =
                            selectedSteps.downloadFixtures &&
                            dauCompsViewModel
                                .lastFixtureDownloadRanViaCloudFunction;
                        if (selectedSteps.recalculateScoring &&
                            skipUiScoringAfterBackendFixtureDownload) {
                          log(
                            'AdminDaucompsEditScoringButton: skipping UI scoring step because backend fixture download already triggered scoring.',
                          );
                        } else if (selectedSteps.recalculateScoring) {
                          log('AdminDaucompsEditScoringButton: starting backend scoring update step.');
                          adminProgress.value = const AdminUpdateProgress(
                            'Updating scores...',
                            null,
                          );
                          scoringResult = await dauCompsViewModel
                              .rescoreWithBackend(daucomp!);
                          log('AdminDaucompsEditScoringButton: backend scoring update step completed.');
                        }

                        if (context.mounted) {
                          if (progressDialogShown) {
                            Navigator.of(context, rootNavigator: true).pop();
                            progressDialogPopRequested = true;
                            await progressDialogClosed?.catchError((_) {});
                          }
                          if (!context.mounted) {
                            return;
                          }
                          if (scoringResult != null || fixtureResult != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.green,
                                content: Text(scoringResult ?? fixtureResult!),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      } catch (e, stackTrace) {
                        log(
                          'AdminDaucompsEditScoringButton: admin update failed: $e',
                          error: e,
                          stackTrace: stackTrace,
                        );
                        if (context.mounted) {
                          if (progressDialogShown) {
                            Navigator.of(context, rootNavigator: true).pop();
                            progressDialogPopRequested = true;
                            await progressDialogClosed?.catchError((_) {});
                          }
                          if (!context.mounted) {
                            return;
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
                        if (progressDialogPopRequested) {
                          await progressDialogClosed?.catchError((_) {});
                        }
                        adminProgress.dispose();
                        if (context.mounted) {
                          onDisableBack(false);
                        }
                      }
                    },
                  child: Text(!isBusy ? 'Run Updates' : 'Updating...'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

String _adminUpdateErrorMessage(Object error, bool wasScoringSelected) {
  if (error is FirebaseFunctionsException) {
    final detail = error.message?.trim();
    final suffix = detail == null || detail.isEmpty
        ? error.code
        : '${error.code}: $detail';
    return 'Could not update scores ($suffix). Please try again.';
  }
  if (error is StateError) {
    return 'Could not update scores (${error.message}). Please try again.';
  }
  return wasScoringSelected
      ? 'Could not update scores. Please try again.'
      : 'Could not complete the update. Please try again.';
}

class FixtureDownloadStatusBanner extends StatelessWidget {
  final DAUComp comp;
  final DatabaseReference? statusReference;

  const FixtureDownloadStatusBanner({
    super.key,
    required this.comp,
    this.statusReference,
  });

  @override
  Widget build(BuildContext context) {
    final DatabaseReference reference;
    try {
      reference =
          statusReference ??
          configuredDatabaseRef(
            '${p.statsPathRoot}/${comp.dbkey}/${p.scoringStatusKey}',
          );
    } on StateError {
      return const _FixtureDownloadStatusCard(
        icon: Icons.info_outline,
        color: Colors.grey,
        title: 'Fixture status not available',
        subtitle: 'Realtime Database is not configured for this screen.',
      );
    }

    return StreamBuilder<DatabaseEvent>(
      stream: reference.onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FixtureDownloadStatusCard(
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'Fixture status unavailable',
            subtitle: snapshot.error.toString(),
          );
        }

        final value = snapshot.data?.snapshot.value;
        if (value is! Map) {
          return const _FixtureDownloadStatusCard(
            icon: Icons.info_outline,
            color: Colors.grey,
            title: 'Fixture status not checked yet',
            subtitle:
                'The scheduler will update this after the next run.',
          );
        }

        final status = FixtureDownloadStatus.fromJson(
          Map<String, dynamic>.from(value),
        );
        final now = DateTime.now().toUtc();
        final (icon, color, title, subtitle) = status.describe(now);
        return _FixtureDownloadStatusCard(
          icon: icon,
          color: color,
          title: title,
          subtitle: subtitle,
        );
      },
    );
  }
}

class _FixtureDownloadStatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  const _FixtureDownloadStatusCard({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FixtureDownloadStatus {
  final String? state;
  final String? message;
  final String? error;
  final DateTime? lastCheckedAt;
  final DateTime? lastAppliedAt;

  const FixtureDownloadStatus({
    required this.state,
    required this.message,
    required this.error,
    required this.lastCheckedAt,
    required this.lastAppliedAt,
  });

  factory FixtureDownloadStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parseTimestamp(String? value) =>
        value == null ? null : DateTime.tryParse(value);

    return FixtureDownloadStatus(
      state: json['state']?.toString() ?? json['status']?.toString(),
      message: json['message']?.toString(),
      error: json['error']?.toString(),
      lastCheckedAt: parseTimestamp(json['lastCheckedAt']?.toString()),
      lastAppliedAt: parseTimestamp(json['lastAppliedAt']?.toString()),
    );
  }

  (IconData, Color, String, String?) describe(DateTime now) {
    final effectiveState = state?.toLowerCase();
    final checkedAgo = _relativeTime(now, lastCheckedAt);
    final appliedAgo = _relativeTime(now, lastAppliedAt);

    return switch (effectiveState) {
      'downloading' => (
        Icons.downloading_outlined,
        Colors.blue,
        'Fixture download in progress',
        message ?? 'The backend is currently applying fixture updates.',
      ),
      'nothing_to_do' => (
        Icons.info_outline,
        Colors.grey,
        'Nothing to do',
        checkedAgo == null
            ? message ?? 'The last scheduler run found no fixture changes.'
            : 'The last scheduler run found no fixture changes. Last checked $checkedAgo.',
      ),
      'applied' => (
        Icons.cloud_done_outlined,
        Colors.green,
        'Fixture changes applied',
        appliedAgo == null
            ? message ?? 'The latest fixture changes were applied.'
            : 'Fixture changes last applied $appliedAgo.',
      ),
      'failed' => (
        Icons.error_outline,
        Colors.red,
        'Fixture download failed',
        error ?? message ?? 'The latest fixture download attempt failed.',
      ),
      _ => (
        Icons.info_outline,
        Colors.grey,
        'Fixture status',
        message ?? 'Waiting for the next scheduler run.',
      ),
    };
  }
}

String? _relativeTime(DateTime now, DateTime? timestamp) {
  if (timestamp == null) {
    return null;
  }

  final diff = now.difference(timestamp);
  if (diff.isNegative) {
    return 'just now';
  }

  if (diff.inDays >= 1) {
    final days = diff.inDays;
    return days == 1 ? '1 day ago' : '$days days ago';
  }

  if (diff.inHours >= 1) {
    final hours = diff.inHours;
    return hours == 1 ? '1 hour ago' : '$hours hours ago';
  }

  if (diff.inMinutes >= 1) {
    final minutes = diff.inMinutes;
    return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
  }

  return 'just now';
}

class AdminUpdateStepSelection {
  final bool downloadFixtures;
  final bool recalculateScoring;

  const AdminUpdateStepSelection({
    required this.downloadFixtures,
    required this.recalculateScoring,
  });

  bool get hasAnyStep => downloadFixtures || recalculateScoring;
}

class AdminUpdateProgress {
  final String message;
  final double? value;

  const AdminUpdateProgress(this.message, this.value);
}

Future<AdminUpdateStepSelection?> _showAdminUpdateStepsDialog(
  BuildContext context,
) {
  var downloadFixtures = false;
  var recalculateScoring = true;

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
                  onChanged: (value) {
                    setDialogState(() {
                      downloadFixtures = value ?? false;
                    });
                  },
                  title: const Text('Download fixtures'),
                  subtitle: const Text(
                    'Fetch latest fixture scores through the backend and save game updates.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: recalculateScoring,
                  onChanged: (value) {
                    setDialogState(() {
                      recalculateScoring = value ?? false;
                    });
                  },
                  title: const Text('Recalculate scoring'),
                  subtitle: const Text(
                    'Rebuild round points, leaderboards, and game averages.',
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
              const Text('Keep this screen open until the update completes.'),
            ],
          );
        },
      ),
    );
  }
}
