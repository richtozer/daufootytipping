import 'dart:async';

import 'package:daufootytipping/services/app_resume_refresh_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not refresh for the initial resumed state', () async {
    var refreshCount = 0;
    final coordinator = AppResumeRefreshCoordinator(
      refresh: () async {
        refreshCount++;
      },
    );

    await coordinator.handleLifecycleState(AppLifecycleState.resumed);

    expect(refreshCount, 0);
  });

  test('refreshes once after returning from the background', () async {
    var refreshCount = 0;
    final coordinator = AppResumeRefreshCoordinator(
      refresh: () async {
        refreshCount++;
      },
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);

    expect(refreshCount, 1);
  });

  test('reports lifecycle decisions around a resume refresh', () async {
    final events = <AppResumeLifecycleEvent>[];
    var startedCount = 0;
    var finishedCount = 0;
    final coordinator = AppResumeRefreshCoordinator(
      refresh: () async {},
      onLifecycleEvent: events.add,
      onRefreshStarted: () => startedCount++,
      onRefreshFinished: () => finishedCount++,
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);

    expect(
      events.map((event) => event.decision),
      <AppResumeLifecycleDecision>[
        AppResumeLifecycleDecision.backgroundMarked,
        AppResumeLifecycleDecision.refreshStarted,
        AppResumeLifecycleDecision.refreshFinished,
      ],
    );
    expect(startedCount, 1);
    expect(finishedCount, 1);
  });

  test('diagnostic observer failures do not interrupt refresh', () async {
    var refreshCount = 0;
    final coordinator = AppResumeRefreshCoordinator(
      refresh: () async {
        refreshCount++;
      },
      onLifecycleEvent: (_) => throw StateError('observer failed'),
      onRefreshStarted: () => throw StateError('start observer failed'),
      onRefreshFinished: () => throw StateError('finish observer failed'),
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);

    expect(refreshCount, 1);
  });

  test('does not refresh after an inactive-only interruption', () async {
    var refreshCount = 0;
    final coordinator = AppResumeRefreshCoordinator(
      refresh: () async {
        refreshCount++;
      },
    );

    await coordinator.handleLifecycleState(AppLifecycleState.inactive);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);

    expect(refreshCount, 0);
  });

  test('does not overlap resume refreshes', () async {
    var refreshCount = 0;
    final refreshStarted = Completer<void>();
    final finishRefresh = Completer<void>();
    final coordinator = AppResumeRefreshCoordinator(
      refresh: () async {
        refreshCount++;
        refreshStarted.complete();
        await finishRefresh.future;
      },
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    final firstResume = coordinator.handleLifecycleState(
      AppLifecycleState.resumed,
    );
    await refreshStarted.future;
    await coordinator.handleLifecycleState(AppLifecycleState.inactive);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);
    finishRefresh.complete();
    await firstResume;

    expect(refreshCount, 1);
  });

  test('marks a resume dropped during another refresh as anomalous', () async {
    final events = <AppResumeLifecycleEvent>[];
    final refreshStarted = Completer<void>();
    final finishRefresh = Completer<void>();
    final coordinator = AppResumeRefreshCoordinator(
      refresh: () async {
        refreshStarted.complete();
        await finishRefresh.future;
      },
      onLifecycleEvent: events.add,
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    final firstResume = coordinator.handleLifecycleState(
      AppLifecycleState.resumed,
    );
    await refreshStarted.future;
    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);
    finishRefresh.complete();
    await firstResume;

    final AppResumeLifecycleEvent droppedEvent = events.singleWhere(
      (event) =>
          event.decision ==
          AppResumeLifecycleDecision.refreshDroppedInProgress,
    );
    expect(droppedEvent.isAnomalous, isTrue);
  });

  test('retries transient resume refresh failures', () async {
    var refreshCount = 0;
    final errors = <Object>[];
    final coordinator = AppResumeRefreshCoordinator(
      refresh: () async {
        refreshCount++;
        if (refreshCount == 1) {
          throw StateError('temporarily offline');
        }
      },
      retryDelays: const [Duration.zero],
      shouldRetry: (error) => error is StateError,
      onError: (error, _) => errors.add(error),
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);

    expect(refreshCount, 2);
    expect(errors, isEmpty);
  });
}
