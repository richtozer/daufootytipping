import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Temporary, privacy-safe diagnostics for the iOS percentage-stats issue.
///
/// Events stay in memory until the process exits. Only technical identifiers
/// are recorded, and the bounded buffer prevents diagnostics from growing for
/// the lifetime of the app.
class PercentStatsDiagnostics {
  PercentStatsDiagnostics._();

  static const int _maximumEvents = 400;
  static const int _maximumTrackedGameKeys = 32;
  static final Stopwatch _clock = Stopwatch()..start();
  static final List<Map<String, Object?>> _events = [];
  static final LinkedHashSet<String> _trackedGameKeys = LinkedHashSet();
  static int _nextSequence = 1;

  static void record(
    String stage, {
    String? gameKey,
    Map<String, Object?> details = const {},
  }) {
    if (gameKey != null) {
      trackGameKey(gameKey);
    }

    final event = <String, Object?>{
      'sequence': _nextSequence++,
      'elapsedMs': _clock.elapsedMilliseconds,
      'stage': stage,
      if (gameKey != null) 'gameKey': keyFingerprint(gameKey),
      ...details,
    };
    _events.add(Map<String, Object?>.unmodifiable(event));
    if (_events.length > _maximumEvents) {
      _events.removeAt(0);
    }
  }

  static void trackGameKey(String gameKey) {
    _trackedGameKeys.remove(gameKey);
    _trackedGameKeys.add(gameKey);
    while (_trackedGameKeys.length > _maximumTrackedGameKeys) {
      _trackedGameKeys.remove(_trackedGameKeys.first);
    }
  }

  static bool isTracking(String gameKey) {
    return _trackedGameKeys.contains(gameKey);
  }

  static List<String> get trackedGameKeys {
    return List<String>.unmodifiable(_trackedGameKeys);
  }

  static Map<String, Object?> keyFingerprint(String key) {
    return <String, Object?>{
      'text': key,
      'length': key.length,
      'hashCode': key.hashCode,
      'codeUnits': key.codeUnits,
      'utf8Bytes': utf8.encode(key),
    };
  }

  static List<Map<String, Object?>> nearMatchingKeyFingerprints(
    String target,
    Iterable<String> candidates, {
    int limit = 8,
  }) {
    final targetParts = target.split('-');
    final targetLeague = targetParts.isEmpty ? target : targetParts.first;
    final targetRoundPrefix = targetParts.length >= 2
        ? '${targetParts[0]}-${targetParts[1]}-'
        : target;
    final matches = candidates.where((key) => key != target).toList()
      ..sort((left, right) {
        final rankComparison = _nearMatchRank(
          left,
          targetLeague: targetLeague,
          targetRoundPrefix: targetRoundPrefix,
        ).compareTo(
          _nearMatchRank(
            right,
            targetLeague: targetLeague,
            targetRoundPrefix: targetRoundPrefix,
          ),
        );
        return rankComparison != 0 ? rankComparison : left.compareTo(right);
      });
    return matches.take(limit).map(keyFingerprint).toList(growable: false);
  }

  static int _nearMatchRank(
    String key, {
    required String targetLeague,
    required String targetRoundPrefix,
  }) {
    if (key.startsWith(targetRoundPrefix)) {
      return 0;
    }
    if (key.startsWith('$targetLeague-')) {
      return 1;
    }
    return 2;
  }

  static String buildReport({
    required String gameKey,
    required Map<String, Object?> currentState,
    int maximumReportEvents = 160,
  }) {
    final relevantEvents = _events.where((event) {
      final eventGameKey = event['gameKey'];
      if (eventGameKey == null) {
        return true;
      }
      return eventGameKey is Map && eventGameKey['text'] == gameKey;
    }).toList(growable: false);
    final firstIncludedIndex = relevantEvents.length > maximumReportEvents
        ? relevantEvents.length - maximumReportEvents
        : 0;

    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'diagnostic': 'percent-stats-v1',
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'targetGameKey': keyFingerprint(gameKey),
      'currentState': currentState,
      'events': relevantEvents.sublist(firstIncludedIndex),
    });
  }

  @visibleForTesting
  static List<Map<String, Object?>> get eventsForTest {
    return List<Map<String, Object?>>.unmodifiable(_events);
  }

  @visibleForTesting
  static int get maximumEventsForTest => _maximumEvents;

  @visibleForTesting
  static void resetForTest() {
    _events.clear();
    _trackedGameKeys.clear();
    _nextSequence = 1;
    _clock
      ..reset()
      ..start();
  }
}
