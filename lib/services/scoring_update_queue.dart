import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// Represents a scoring update request with deduplication key
class ScoringUpdateRequest {
  final DAUComp dauComp;
  final DAURound? round;
  final Tipper? tipper;
  final DateTime requestedAt;
  final Completer<String> completer;

  /// Priority levels: higher numbers = higher priority
  /// 3 = Admin full rescore, 2 = Round-wide updates, 1 = Individual tip updates
  final int priority;

  ScoringUpdateRequest({
    required this.dauComp,
    required this.round,
    required this.tipper,
    required this.completer,
    this.priority = 1,
  }) : requestedAt = DateTime.now();

  /// Creates a deduplication key for this request
  /// Same tipper + round combinations will be deduplicated
  String get deduplicationKey {
    final compKey = dauComp.dbkey;
    final roundKey = round?.dAUroundNumber.toString() ?? 'ALL_ROUNDS';
    final tipperKey = tipper?.dbkey ?? 'ALL_TIPPERS';
    return '$compKey:$roundKey:$tipperKey';
  }

  /// Creates a user-friendly description for logging
  String get description {
    final compName = dauComp.name;
    final roundDesc = round != null
        ? 'Round ${round!.dAUroundNumber}'
        : 'all rounds';
    final tipperDesc = tipper?.name ?? 'all tippers';
    return '$compName - $roundDesc - $tipperDesc';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoringUpdateRequest &&
          deduplicationKey == other.deduplicationKey;

  @override
  int get hashCode => deduplicationKey.hashCode;
}

/// Sequential queue for scoring updates with deduplication
class ScoringUpdateQueue {
  static final ScoringUpdateQueue _instance = ScoringUpdateQueue._internal();
  factory ScoringUpdateQueue() => _instance;
  ScoringUpdateQueue._internal();

  final List<ScoringUpdateRequest> _queue = [];
  final Map<String, ScoringUpdateRequest> _deduplicateMap = {};
  bool _processingQueue = false;
  Timer? _processingTimer;

  /// Adds a scoring update request to the queue with deduplication
  Future<String> queueScoringUpdate({
    required DAUComp dauComp,
    required DAURound? round,
    required Tipper? tipper,
    int priority = 1,
  }) async {
    final completer = Completer<String>();
    final request = ScoringUpdateRequest(
      dauComp: dauComp,
      round: round,
      tipper: tipper,
      completer: completer,
      priority: priority,
    );

    return _addRequestToQueue(request);
  }

  Future<String> _addRequestToQueue(ScoringUpdateRequest request) async {
    // Check if we already have a pending request with the same deduplication key
    final existingRequest = _deduplicateMap[request.deduplicationKey];
    if (existingRequest != null) {
      // Complete the old request with a deduped message
      if (!existingRequest.completer.isCompleted) {
        existingRequest.completer.complete('Superseded by newer request');
      }

      // Remove the old request from the queue
      _queue.remove(existingRequest);
      log('ScoringUpdateQueue: Deduplicated ${existingRequest.description}');
    }

    // Add the new request
    _queue.add(request);
    _deduplicateMap[request.deduplicationKey] = request;

    // Sort queue by priority (highest priority first), then by request time
    _queue.sort((a, b) {
      final priorityComparison = b.priority.compareTo(a.priority);
      if (priorityComparison != 0) return priorityComparison;
      return a.requestedAt.compareTo(b.requestedAt);
    });

    log(
      'ScoringUpdateQueue: Queued ${request.description} (queue size: ${_queue.length})',
    );

    // Start processing if not already running
    _scheduleProcessing();

    return await request.completer.future;
  }

  void _scheduleProcessing() {
    if (_processingQueue) return;

    // Use a small delay to allow multiple rapid requests to batch together
    _processingTimer?.cancel();
    _processingTimer = Timer(const Duration(milliseconds: 100), _processQueue);
  }

  Future<void> _processQueue() async {
    if (_processingQueue || _queue.isEmpty) return;

    _processingQueue = true;
    log(
      'ScoringUpdateQueue: Starting queue processing (${_queue.length} items)',
    );

    try {
      while (_queue.isNotEmpty) {
        final request = _queue.removeAt(0);
        _deduplicateMap.remove(request.deduplicationKey);

        if (request.completer.isCompleted) {
          log('ScoringUpdateQueue: Skipping already completed request');
          continue;
        }

        try {
          log('ScoringUpdateQueue: Processing ${request.description}');
          final stopwatch = Stopwatch()..start();

          final result = await di<StatsViewModel>().updateStats(
            request.dauComp,
            request.round,
            request.tipper,
          );

          stopwatch.stop();
          log(
            'ScoringUpdateQueue: Completed ${request.description} in ${stopwatch.elapsedMilliseconds}ms - $result',
          );

          if (!request.completer.isCompleted) {
            request.completer.complete(result);
          }
        } catch (e) {
          log(
            'ScoringUpdateQueue: Error processing ${request.description}: $e',
          );
          if (!request.completer.isCompleted) {
            request.completer.completeError(e);
          }
        }

        // Small delay between requests to prevent overwhelming the system
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } finally {
      _processingQueue = false;
      log('ScoringUpdateQueue: Finished queue processing');
    }
  }

  /// Gets current queue status for debugging
  Map<String, dynamic> get queueStatus => {
    'queueLength': _queue.length,
    'processing': _processingQueue,
    'pendingRequests': _queue
        .map(
          (r) => {
            'description': r.description,
            'priority': r.priority,
            'requestedAt': r.requestedAt.toIso8601String(),
          },
        )
        .toList(),
  };

  /// Clears the queue (useful for testing or emergency situations)
  void clearQueue() {
    log('ScoringUpdateQueue: Clearing queue (${_queue.length} items)');

    // Complete all pending requests with cancellation message
    for (final request in _queue) {
      if (!request.completer.isCompleted) {
        request.completer.complete('Queue cleared');
      }
    }

    _queue.clear();
    _deduplicateMap.clear();
    _processingTimer?.cancel();
    _processingQueue = false;
  }
}
