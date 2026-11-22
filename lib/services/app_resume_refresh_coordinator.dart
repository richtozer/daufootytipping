import 'package:flutter/widgets.dart';

class AppResumeRefreshCoordinator {
  AppResumeRefreshCoordinator({
    required Future<void> Function() refresh,
    Duration resumeDelay = Duration.zero,
    List<Duration> retryDelays = const [],
    bool Function(Object error)? shouldRetry,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _refresh = refresh,
       _resumeDelay = resumeDelay,
       _retryDelays = retryDelays,
       _shouldRetry = shouldRetry ?? ((_) => false),
       _onError = onError;

  final Future<void> Function() _refresh;
  final Duration _resumeDelay;
  final List<Duration> _retryDelays;
  final bool Function(Object error) _shouldRetry;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  bool _wasBackgrounded = false;
  bool _refreshInProgress = false;

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive) {
      return;
    }

    if (state != AppLifecycleState.resumed) {
      _wasBackgrounded = true;
      return;
    }

    if (!_wasBackgrounded) {
      return;
    }

    _wasBackgrounded = false;
    if (_refreshInProgress) {
      return;
    }

    _refreshInProgress = true;
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
    }
  }
}
