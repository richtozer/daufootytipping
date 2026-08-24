import 'package:flutter/foundation.dart';

class AppResumeDataRefresher {
  AppResumeDataRefresher({
    required TargetPlatform platform,
    required Future<void> Function() reconnectRealtimeDatabase,
    required Future<void> Function() refreshFixtureData,
    List<Duration> reconnectRetryDelays = const [],
    void Function(Object error, StackTrace stackTrace)? onReconnectError,
  }) : _platform = platform,
       _reconnectRealtimeDatabase = reconnectRealtimeDatabase,
       _refreshFixtureData = refreshFixtureData,
       _reconnectRetryDelays = reconnectRetryDelays,
       _onReconnectError = onReconnectError;

  final TargetPlatform _platform;
  final Future<void> Function() _reconnectRealtimeDatabase;
  final Future<void> Function() _refreshFixtureData;
  final List<Duration> _reconnectRetryDelays;
  final void Function(Object error, StackTrace stackTrace)? _onReconnectError;

  Future<void> refresh() async {
    if (_platform == TargetPlatform.android) {
      await _reconnectAndroidDatabase();
    }

    await _refreshFixtureData();
  }

  Future<void> _reconnectAndroidDatabase() async {
    for (var attempt = 0;; attempt++) {
      try {
        await _reconnectRealtimeDatabase();
        return;
      } catch (error, stackTrace) {
        if (attempt >= _reconnectRetryDelays.length) {
          _onReconnectError?.call(error, stackTrace);
          return;
        }
        await Future<void>.delayed(_reconnectRetryDelays[attempt]);
      }
    }
  }
}
