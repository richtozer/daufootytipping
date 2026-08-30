import 'package:flutter/widgets.dart';

enum AppResumeLifecycleDecision {
  ignoredInactive,
  backgroundMarked,
  ignoredWithoutBackground,
  refreshDroppedInProgress,
  refreshStarted,
  refreshFinished,
}

class AppResumeLifecycleEvent {
  const AppResumeLifecycleEvent({
    required this.state,
    required this.decision,
    required this.wasBackgrounded,
    required this.refreshInProgress,
  });

  final AppLifecycleState state;
  final AppResumeLifecycleDecision decision;
  final bool wasBackgrounded;
  final bool refreshInProgress;

  bool get isAnomalous {
    return decision == AppResumeLifecycleDecision.refreshDroppedInProgress;
  }
}

class AppResumeRefreshCoordinator {
  AppResumeRefreshCoordinator({
    required Future<void> Function() refresh,
    Duration resumeDelay = Duration.zero,
    List<Duration> retryDelays = const [],
    bool Function(Object error)? shouldRetry,
    void Function(Object error, StackTrace stackTrace)? onError,
    void Function(AppResumeLifecycleEvent event)? onLifecycleEvent,
    void Function()? onRefreshStarted,
    void Function()? onRefreshFinished,
  }) : _refresh = refresh,
       _resumeDelay = resumeDelay,
       _retryDelays = retryDelays,
       _shouldRetry = shouldRetry ?? ((_) => false),
       _onError = onError,
       _onLifecycleEvent = onLifecycleEvent,
       _onRefreshStarted = onRefreshStarted,
       _onRefreshFinished = onRefreshFinished;

  final Future<void> Function() _refresh;
  final Duration _resumeDelay;
  final List<Duration> _retryDelays;
  final bool Function(Object error) _shouldRetry;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  final void Function(AppResumeLifecycleEvent event)? _onLifecycleEvent;
  final void Function()? _onRefreshStarted;
  final void Function()? _onRefreshFinished;
  bool _wasBackgrounded = false;
  bool _refreshInProgress = false;

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive) {
      _emitLifecycleEvent(state, AppResumeLifecycleDecision.ignoredInactive);
      return;
    }

    if (state != AppLifecycleState.resumed) {
      _wasBackgrounded = true;
      _emitLifecycleEvent(state, AppResumeLifecycleDecision.backgroundMarked);
      return;
    }

    if (!_wasBackgrounded) {
      _emitLifecycleEvent(
        state,
        AppResumeLifecycleDecision.ignoredWithoutBackground,
      );
      return;
    }

    _wasBackgrounded = false;
    if (_refreshInProgress) {
      _emitLifecycleEvent(
        state,
        AppResumeLifecycleDecision.refreshDroppedInProgress,
      );
      return;
    }

    _refreshInProgress = true;
    _callObserver(_onRefreshStarted);
    _emitLifecycleEvent(state, AppResumeLifecycleDecision.refreshStarted);
    try {
      await Future<void>.delayed(_resumeDelay);
      for (var attempt = 0;; attempt++) {
        try {
          await _refresh();
          return;
        } catch (error, stackTrace) {
          if (!_shouldRetry(error) || attempt >= _retryDelays.length) {
            _onError?.call(error, stackTrace);
            return;
          }
          await Future<void>.delayed(_retryDelays[attempt]);
        }
      }
    } finally {
      _refreshInProgress = false;
      _emitLifecycleEvent(state, AppResumeLifecycleDecision.refreshFinished);
      _callObserver(_onRefreshFinished);
    }
  }

  void _emitLifecycleEvent(
    AppLifecycleState state,
    AppResumeLifecycleDecision decision,
  ) {
    final void Function(AppResumeLifecycleEvent event)? observer =
        _onLifecycleEvent;
    if (observer == null) {
      return;
    }
    try {
      observer(
        AppResumeLifecycleEvent(
          state: state,
          decision: decision,
          wasBackgrounded: _wasBackgrounded,
          refreshInProgress: _refreshInProgress,
        ),
      );
    } catch (_) {
      // Diagnostics must never change lifecycle refresh behavior.
    }
  }

  void _callObserver(void Function()? observer) {
    if (observer == null) {
      return;
    }
    try {
      observer();
    } catch (_) {
      // Diagnostics must never change lifecycle refresh behavior.
    }
  }
}
