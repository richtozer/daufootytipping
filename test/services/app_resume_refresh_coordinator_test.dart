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
