import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';

/// Lightweight startup instrumentation that can be enabled with:
/// `--dart-define=STARTUP_PROFILING=true`
class StartupProfiling {
  static const bool enabled = bool.fromEnvironment(
    'STARTUP_PROFILING',
    defaultValue: false,
  );

  static final Map<String, Stopwatch> _stopwatches = <String, Stopwatch>{};
  static final Map<String, TimelineTask> _tasks = <String, TimelineTask>{};

  static void start(
    String phase, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    if (!enabled) {
      return;
    }
    _tasks.remove(phase)?.finish();
    _stopwatches[phase] = Stopwatch()..start();
    _tasks[phase] = TimelineTask()..start(phase, arguments: arguments);
  }

  static void end(
    String phase, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    if (!enabled) {
      return;
    }
    final Stopwatch? stopwatch = _stopwatches.remove(phase);
    final TimelineTask? task = _tasks.remove(phase);
    if (stopwatch == null && task == null) {
      return;
    }
    final int? elapsedMs = stopwatch?.elapsedMilliseconds;
    final Map<String, Object?> timelineArgs = <String, Object?>{
      'elapsedMs': elapsedMs,
      ...arguments,
    };

    if (task != null) {
      task.finish(arguments: timelineArgs);
    } else {
      Timeline.instantSync('$phase:end', arguments: timelineArgs);
    }

    final String message = '[startup-profile] $phase ${elapsedMs ?? -1}ms';
    log(message);
    debugPrint(message);
  }

  static Future<T> trackAsync<T>(
    String phase,
    Future<T> Function() body, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    if (!enabled) {
      return body();
    }
    start(phase, arguments: arguments);
    try {
      return await body();
    } finally {
      end(phase);
    }
  }

  static T trackSync<T>(
    String phase,
    T Function() body, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    if (!enabled) {
      return body();
    }
    start(phase, arguments: arguments);
    try {
      return body();
    } finally {
      end(phase);
    }
  }

  static void instant(
    String name, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    if (!enabled) {
      return;
    }
    final int epochMs = DateTime.now().millisecondsSinceEpoch;
    final Map<String, Object?> timelineArgs = <String, Object?>{
      'epochMs': epochMs,
      ...arguments,
    };
    Timeline.instantSync(name, arguments: timelineArgs);
    final String message =
        '[startup-profile] $name epochMs=$epochMs args=$arguments';
    log(message);
    debugPrint(message);
  }

  /// Estimates payload size for JSON-like objects while profiling is enabled.
  static int? estimatePayloadBytes(dynamic payload) {
    if (!enabled || payload == null) {
      return null;
    }
    try {
      if (payload is String) {
        return payload.length;
      }
      return utf8.encode(jsonEncode(payload)).length;
    } catch (_) {
      return null;
    }
  }
}
