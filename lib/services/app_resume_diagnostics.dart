import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'app_resume_diagnostics_storage.dart';

export 'app_resume_diagnostics_storage.dart' show ResumeDiagnosticsStorage;

typedef ResumeDiagnosticsClock = DateTime Function();
typedef ResumeProbeEventRecorder =
    void Function(
      String stage,
      Map<String, Object?> details,
      bool anomalous,
    );

class ResumeDiagnosticEvent {
  const ResumeDiagnosticEvent({
    required this.utc,
    required this.sequence,
    required this.processId,
    required this.stage,
    required this.details,
    this.attemptId,
    this.anomalous = false,
  });

  factory ResumeDiagnosticEvent.fromJson(Map<String, dynamic> json) {
    return ResumeDiagnosticEvent(
      utc: DateTime.parse(json['utc'] as String).toUtc(),
      sequence: json['sequence'] as int,
      processId: json['processId'] as String,
      attemptId: json['attemptId'] as String?,
      stage: json['stage'] as String,
      anomalous: json['anomalous'] as bool? ?? false,
      details: Map<String, Object?>.from(
        json['details'] as Map? ?? const <String, Object?>{},
      ),
    );
  }

  final DateTime utc;
  final int sequence;
  final String processId;
  final String? attemptId;
  final String stage;
  final bool anomalous;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'utc': utc.toIso8601String(),
      'sequence': sequence,
      'processId': processId,
      'attemptId': attemptId,
      'stage': stage,
      'anomalous': anomalous,
      'details': details,
    };
  }

  String encode() => jsonEncode(toJson());
}

class ResumeDiagnosticsRecorder {
  ResumeDiagnosticsRecorder({
    required ResumeDiagnosticsStorage storage,
    required String processId,
    ResumeDiagnosticsClock? now,
    this.normalRetention = const Duration(days: 14),
    this.anomalousRetention = const Duration(days: 30),
    this.activeAttemptAfterFinish = const Duration(minutes: 1),
    this.unattachedDedupeWindow = const Duration(minutes: 1),
    this.maxEvents = 5000,
    this.maxStoredBytes = 4 * 1024 * 1024,
  }) : _storage = storage,
       _processId = processId,
       _now = now ?? DateTime.now;

  final ResumeDiagnosticsStorage _storage;
  final String _processId;
  final ResumeDiagnosticsClock _now;
  final Duration normalRetention;
  final Duration anomalousRetention;
  final Duration activeAttemptAfterFinish;
  final Duration unattachedDedupeWindow;
  final int maxEvents;
  final int maxStoredBytes;

  final List<ResumeDiagnosticEvent> _events = <ResumeDiagnosticEvent>[];
  final Set<String> _attemptDedupeKeys = <String>{};
  final Map<String, DateTime> _unattachedDedupeTimesUtc = <String, DateTime>{};
  Future<void> _pendingWrites = Future<void>.value();
  bool _initialized = false;
  int _sequence = 0;
  int _storedBytes = 0;
  int _attemptCounter = 0;
  String? _activeAttemptId;
  DateTime? _activeAttemptExpiresUtc;

  String? get activeAttemptId => _isAttemptActive ? _activeAttemptId : null;

  bool get _isAttemptActive {
    final String? attemptId = _activeAttemptId;
    if (attemptId == null) {
      return false;
    }
    final DateTime? expiresUtc = _activeAttemptExpiresUtc;
    return expiresUtc == null || !_now().toUtc().isAfter(expiresUtc);
  }

  Future<void> initialize({
    Map<String, Object?> processDetails = const <String, Object?>{},
  }) async {
    if (_initialized) {
      return;
    }

    final List<String> encodedEvents = await _storage.readLines();
    bool storageNeedsRewrite = false;
    for (final String encodedEvent in encodedEvents) {
      try {
        final dynamic decoded = jsonDecode(encodedEvent);
        if (decoded is Map<String, dynamic>) {
          _events.add(ResumeDiagnosticEvent.fromJson(decoded));
        } else {
          storageNeedsRewrite = true;
        }
      } catch (error) {
        storageNeedsRewrite = true;
        log('Discarding unreadable Android resume diagnostic event: $error');
      }
    }
    _events.sort((a, b) {
      final int timestampComparison = a.utc.compareTo(b.utc);
      return timestampComparison != 0
          ? timestampComparison
          : a.sequence.compareTo(b.sequence);
    });
    if (_events.isNotEmpty) {
      _sequence = _events
          .map((event) => event.sequence)
          .reduce((a, b) => a > b ? a : b);
    }
    _storedBytes = _events.fold<int>(
      0,
      (total, event) => total + _eventStorageBytes(event),
    );
    final int eventCountBeforePruning = _events.length;
    final bool eventsPruned = _pruneEvents(_now().toUtc());
    if (storageNeedsRewrite ||
        eventsPruned ||
        _events.length != eventCountBeforePruning) {
      await _storage.replaceLines(
        _events.map((event) => event.encode()).toList(),
      );
    }
    _initialized = true;
    await record(
      'process_started',
      details: processDetails,
      attachToActiveAttempt: false,
    );
  }

  String beginAttempt({
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    _ensureInitialized();
    _attemptCounter++;
    final String attemptId =
        '$_processId-${_now().toUtc().microsecondsSinceEpoch}-$_attemptCounter';
    _activeAttemptId = attemptId;
    _activeAttemptExpiresUtc = null;
    _attemptDedupeKeys.clear();
    unawaited(record('attempt_started', details: details));
    return attemptId;
  }

  void finishAttempt({bool anomalous = false}) {
    if (!_isAttemptActive) {
      return;
    }
    unawaited(
      record('attempt_pipeline_finished', anomalous: anomalous),
    );
    _activeAttemptExpiresUtc = _now().toUtc().add(activeAttemptAfterFinish);
  }

  Future<void> record(
    String stage, {
    Map<String, Object?> details = const <String, Object?>{},
    bool anomalous = false,
    bool attachToActiveAttempt = true,
    bool requireActiveAttempt = false,
    String? dedupeKey,
  }) {
    _ensureInitialized();
    final String? attemptId = attachToActiveAttempt ? activeAttemptId : null;
    if (requireActiveAttempt && attemptId == null) {
      return Future<void>.value();
    }
    final DateTime nowUtc = _now().toUtc();
    if (dedupeKey != null) {
      if (attemptId != null && !_attemptDedupeKeys.add(dedupeKey)) {
        return Future<void>.value();
      }
      if (attemptId == null) {
        final DateTime? lastRecordedUtc =
            _unattachedDedupeTimesUtc[dedupeKey];
        if (lastRecordedUtc != null &&
            nowUtc.difference(lastRecordedUtc) < unattachedDedupeWindow) {
          return Future<void>.value();
        }
        _unattachedDedupeTimesUtc[dedupeKey] = nowUtc;
      }
    }

    final ResumeDiagnosticEvent event = ResumeDiagnosticEvent(
      utc: nowUtc,
      sequence: ++_sequence,
      processId: _processId,
      attemptId: attemptId,
      stage: stage,
      anomalous: anomalous,
      details: _jsonSafeDetails(details),
    );
    _pendingWrites = _pendingWrites.then((_) => _appendAndPersist(event)).catchError(
      (Object error, StackTrace stackTrace) {
        log(
          'Failed to persist Android resume diagnostics: $error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    return _pendingWrites;
  }

  Future<List<ResumeDiagnosticEvent>> readEvents() async {
    await flush();
    return List<ResumeDiagnosticEvent>.unmodifiable(_events);
  }

  Future<String> exportText() async {
    final List<ResumeDiagnosticEvent> events = await readEvents();
    return events.map((event) => event.encode()).join('\n');
  }

  Future<List<String>> exportTextChunks({
    int maxChunkBytes = 200 * 1024,
  }) async {
    if (maxChunkBytes <= 0) {
      throw ArgumentError.value(
        maxChunkBytes,
        'maxChunkBytes',
        'must be greater than zero',
      );
    }

    final List<ResumeDiagnosticEvent> events = await readEvents();
    final List<String> chunks = <String>[];
    final List<String> currentLines = <String>[];
    int currentBytes = 0;

    for (final ResumeDiagnosticEvent event in events) {
      final String encodedEvent = event.encode();
      final int encodedBytes = utf8.encode(encodedEvent).length;
      final int separatorBytes = currentLines.isEmpty ? 0 : 1;
      if (currentLines.isNotEmpty &&
          currentBytes + separatorBytes + encodedBytes > maxChunkBytes) {
        chunks.add(currentLines.join('\n'));
        currentLines.clear();
        currentBytes = 0;
      }
      if (currentLines.isNotEmpty) {
        currentBytes++;
      }
      currentLines.add(encodedEvent);
      currentBytes += encodedBytes;
    }

    if (currentLines.isNotEmpty) {
      chunks.add(currentLines.join('\n'));
    }
    return List<String>.unmodifiable(chunks);
  }

  Future<void> flush() => _pendingWrites;

  Future<void> _appendAndPersist(ResumeDiagnosticEvent event) async {
    final String encodedEvent = event.encode();
    _events.add(event);
    _storedBytes += utf8.encode(encodedEvent).length + 1;
    if (_pruneEvents(event.utc)) {
      await _storage.replaceLines(
        _events.map((storedEvent) => storedEvent.encode()).toList(),
      );
      return;
    }
    await _storage.appendLine(encodedEvent);
  }

  bool _pruneEvents(DateTime nowUtc) {
    bool eventsPruned = false;
    final Set<String> anomalousAttemptIds = _events
        .where((event) => event.anomalous)
        .map((event) => event.attemptId)
        .whereType<String>()
        .toSet();

    _events.removeWhere((event) {
      final bool belongsToAnomalousAttempt =
          event.attemptId != null &&
          anomalousAttemptIds.contains(event.attemptId);
      final Duration retention = event.anomalous || belongsToAnomalousAttempt
          ? anomalousRetention
          : normalRetention;
      final bool expired = nowUtc.difference(event.utc) > retention;
      if (expired) {
        _storedBytes -= _eventStorageBytes(event);
      }
      eventsPruned = eventsPruned || expired;
      return expired;
    });

    while (_events.length > maxEvents) {
      final ResumeDiagnosticEvent removed = _removeOldestPreferredEvent(
        anomalousAttemptIds,
      );
      _storedBytes -= _eventStorageBytes(removed);
      eventsPruned = true;
    }

    while (_events.isNotEmpty && _storedBytes > maxStoredBytes) {
      final ResumeDiagnosticEvent removed = _removeOldestPreferredEvent(
        anomalousAttemptIds,
      );
      _storedBytes -= _eventStorageBytes(removed);
      eventsPruned = true;
    }
    return eventsPruned;
  }

  ResumeDiagnosticEvent _removeOldestPreferredEvent(
    Set<String> anomalousAttemptIds,
  ) {
    final int normalEventIndex = _events.indexWhere(
      (event) =>
          !event.anomalous &&
          (event.attemptId == null ||
              !anomalousAttemptIds.contains(event.attemptId)),
    );
    return _events.removeAt(normalEventIndex >= 0 ? normalEventIndex : 0);
  }

  int _eventStorageBytes(ResumeDiagnosticEvent event) {
    return utf8.encode(event.encode()).length + 1;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('ResumeDiagnosticsRecorder is not initialized.');
    }
  }
}

class RealtimeDatabaseDiagnosticProbe {
  RealtimeDatabaseDiagnosticProbe({
    required FirebaseDatabase database,
    required ResumeProbeEventRecorder recordEvent,
    ResumeDiagnosticsClock? now,
    this.probePath = '/Diagnostics/androidResumeProbe',
  }) : _database = database,
       _recordEvent = recordEvent,
       _now = now ?? DateTime.now;

  final FirebaseDatabase _database;
  final ResumeProbeEventRecorder _recordEvent;
  final ResumeDiagnosticsClock _now;
  final String probePath;

  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  StreamSubscription<DatabaseEvent>? _probeSubscription;
  int _generationCounter = 0;
  int? _activeGeneration;
  String? _activeProbeId;

  bool get active => _activeGeneration != null;

  Future<void> start() async {
    if (active) {
      _emit(
        'extended_probe_start_ignored_already_active',
        details: _identityDetails(),
      );
      return;
    }

    final int generation = ++_generationCounter;
    final String probeId =
        'probe-${_now().toUtc().microsecondsSinceEpoch}-$generation';
    _activeGeneration = generation;
    _activeProbeId = probeId;
    final Map<String, Object?> identity = _identityDetails();
    _emit('extended_probe_started', details: identity);

    try {
      final DatabaseReference connectionReference = _database.ref(
        '.info/connected',
      );
      _connectionSubscription = connectionReference.onValue.listen(
        (event) {
          final Object? value = event.snapshot.value;
          _emit(
            'extended_probe_connection_state',
            details: <String, Object?>{
              ...identity,
              'connected': value is bool ? value : null,
            },
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          _emit(
            'extended_probe_connection_observer_error',
            details: <String, Object?>{
              ...identity,
              'error': error.toString(),
            },
            anomalous: true,
          );
        },
        onDone: () {
          _emit(
            'extended_probe_connection_observer_done',
            details: identity,
            anomalous: true,
          );
        },
      );
      _emit(
        'extended_probe_connection_observer_attached',
        details: identity,
      );

      final DatabaseReference probeReference = _database.ref(probePath);
      _probeSubscription = probeReference.onValue.listen(
        (event) {
          _emit(
            'extended_probe_fresh_listener_snapshot',
            details: <String, Object?>{
              ...identity,
              'exists': event.snapshot.exists,
              'value': AppResumeDiagnostics.probeValueForDiagnostics(
                event.snapshot.value,
              ),
            },
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          _emit(
            'extended_probe_fresh_listener_error',
            details: <String, Object?>{
              ...identity,
              'error': error.toString(),
            },
            anomalous: true,
          );
        },
        onDone: () {
          _emit(
            'extended_probe_fresh_listener_done',
            details: identity,
            anomalous: true,
          );
        },
      );
      _emit('extended_probe_fresh_listener_attached', details: identity);
    } catch (error) {
      _emit(
        'extended_probe_start_failed',
        details: <String, Object?>{
          ..._identityDetails(),
          'error': error.toString(),
        },
        anomalous: true,
      );
      await stop(reason: 'start_failed');
      rethrow;
    }
  }

  Future<void> stop({String reason = 'manual'}) async {
    final int? generation = _activeGeneration;
    final String? probeId = _activeProbeId;
    if (generation == null || probeId == null) {
      return;
    }

    final Map<String, Object?> identity = <String, Object?>{
      'probeId': probeId,
      'observerGeneration': generation,
      'probePath': probePath,
    };
    final StreamSubscription<DatabaseEvent>? connectionSubscription =
        _connectionSubscription;
    final StreamSubscription<DatabaseEvent>? probeSubscription =
        _probeSubscription;
    _connectionSubscription = null;
    _probeSubscription = null;
    _activeGeneration = null;
    _activeProbeId = null;

    await _cancelSubscription(
      subscription: connectionSubscription,
      observer: 'connection',
      reason: reason,
      identity: identity,
    );
    await _cancelSubscription(
      subscription: probeSubscription,
      observer: 'fresh_listener',
      reason: reason,
      identity: identity,
    );
    _emit(
      'extended_probe_stopped',
      details: <String, Object?>{...identity, 'reason': reason},
    );
  }

  Future<void> _cancelSubscription({
    required StreamSubscription<DatabaseEvent>? subscription,
    required String observer,
    required String reason,
    required Map<String, Object?> identity,
  }) async {
    if (subscription == null) {
      return;
    }
    final Map<String, Object?> details = <String, Object?>{
      ...identity,
      'observer': observer,
      'reason': reason,
    };
    _emit('extended_probe_observer_cancel_requested', details: details);
    try {
      await subscription.cancel();
      _emit('extended_probe_observer_cancelled', details: details);
    } catch (error) {
      _emit(
        'extended_probe_observer_cancel_failed',
        details: <String, Object?>{
          ...details,
          'error': error.toString(),
        },
        anomalous: true,
      );
    }
  }

  Map<String, Object?> _identityDetails() {
    return <String, Object?>{
      'probeId': _activeProbeId,
      'observerGeneration': _activeGeneration,
      'probePath': probePath,
    };
  }

  void _emit(
    String stage, {
    Map<String, Object?> details = const <String, Object?>{},
    bool anomalous = false,
  }) {
    _recordEvent(stage, details, anomalous);
  }
}

typedef SecondaryRealtimeDatabaseClientFactory =
    Future<SecondaryRealtimeDatabaseDiagnosticClient> Function(
      String appName,
      ResumeProbeEventRecorder recordEvent,
    );

class SecondaryRealtimeDatabaseDiagnosticClient {
  SecondaryRealtimeDatabaseDiagnosticClient({
    required this.appName,
    required this.database,
    required Future<void> Function() dispose,
  }) : _dispose = dispose;

  final String appName;
  final FirebaseDatabase database;
  final Future<void> Function() _dispose;

  Future<void> dispose() => _dispose();
}

/// Creates a completely separate Firebase app/database client for diagnosis.
///
/// This probe never replaces the primary database or any application listener.
/// It exists only to establish whether new RTDB client state can synchronize
/// while the retained primary client remains stale.
class SecondaryRealtimeDatabaseDiagnosticProbe {
  SecondaryRealtimeDatabaseDiagnosticProbe({
    required SecondaryRealtimeDatabaseClientFactory clientFactory,
    required ResumeProbeEventRecorder recordEvent,
    required this.gamesPath,
    ResumeDiagnosticsClock? now,
    this.diagnosticProbePath = '/Diagnostics/androidResumeProbe',
    this.configProbePath = '/AppConfig/resumeProbe',
  }) : _clientFactory = clientFactory,
       _recordEvent = recordEvent,
       _now = now ?? DateTime.now;

  final SecondaryRealtimeDatabaseClientFactory _clientFactory;
  final ResumeProbeEventRecorder _recordEvent;
  final ResumeDiagnosticsClock _now;
  final String gamesPath;
  final String diagnosticProbePath;
  final String configProbePath;

  final Map<String, StreamSubscription<DatabaseEvent>> _subscriptions =
      <String, StreamSubscription<DatabaseEvent>>{};
  SecondaryRealtimeDatabaseDiagnosticClient? _client;
  int _generationCounter = 0;
  int? _activeGeneration;
  String? _activeProbeId;
  String? _activeAppName;

  bool get active => _activeGeneration != null;

  Future<void> start() async {
    if (active) {
      _emit(
        'secondary_probe_start_ignored_already_active',
        details: _identityDetails(),
      );
      return;
    }

    final int generation = ++_generationCounter;
    final int timestamp = _now().toUtc().microsecondsSinceEpoch;
    _activeGeneration = generation;
    _activeProbeId = 'secondary-probe-$timestamp-$generation';
    _activeAppName = 'android-resume-diagnostics-$timestamp-$generation';
    final Map<String, Object?> identity = _identityDetails();
    _emit('secondary_probe_started', details: identity);

    try {
      final SecondaryRealtimeDatabaseDiagnosticClient client =
          await _clientFactory(
            _activeAppName!,
            (stage, details, anomalous) {
              _emit(
                stage,
                details: <String, Object?>{...identity, ...details},
                anomalous: anomalous,
              );
            },
          );
      _client = client;
      _emit(
        'secondary_probe_client_ready',
        details: <String, Object?>{
          ...identity,
          'clientAppName': client.appName,
        },
      );
      _attachObservers(client.database, identity);
    } catch (error) {
      _emit(
        'secondary_probe_start_failed',
        details: <String, Object?>{
          ...identity,
          'error': error.toString(),
        },
        anomalous: true,
      );
      await stop(reason: 'start_failed');
      rethrow;
    }
  }

  void _attachObservers(
    FirebaseDatabase database,
    Map<String, Object?> identity,
  ) {
    _attachObserver(
      database: database,
      path: '.info/connected',
      observer: 'connection',
      identity: identity,
      snapshotDetails: (snapshot) {
        final Object? value = snapshot.value;
        return <String, Object?>{
          'connected': value is bool ? value : null,
        };
      },
    );
    _attachObserver(
      database: database,
      path: diagnosticProbePath,
      observer: 'diagnostic_probe',
      identity: identity,
      snapshotDetails: _scalarSnapshotDetails,
    );
    _attachObserver(
      database: database,
      path: configProbePath,
      observer: 'config_probe',
      identity: identity,
      snapshotDetails: _scalarSnapshotDetails,
    );
    _attachObserver(
      database: database,
      path: gamesPath,
      observer: 'games',
      identity: identity,
      snapshotDetails: _gamesSnapshotDetails,
    );
  }

  void _attachObserver({
    required FirebaseDatabase database,
    required String path,
    required String observer,
    required Map<String, Object?> identity,
    required Map<String, Object?> Function(DataSnapshot snapshot)
    snapshotDetails,
  }) {
    final Map<String, Object?> observerDetails = <String, Object?>{
      ...identity,
      'observer': observer,
      'path': path,
    };
    final StreamSubscription<DatabaseEvent> subscription = database
        .ref(path)
        .onValue
        .listen(
          (event) {
            _emit(
              'secondary_probe_${observer}_snapshot',
              details: <String, Object?>{
                ...observerDetails,
                ...snapshotDetails(event.snapshot),
              },
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            _emit(
              'secondary_probe_observer_error',
              details: <String, Object?>{
                ...observerDetails,
                'error': error.toString(),
              },
              anomalous: true,
            );
          },
          onDone: () {
            _emit(
              'secondary_probe_observer_done',
              details: observerDetails,
              anomalous: true,
            );
          },
        );
    _subscriptions[observer] = subscription;
    _emit('secondary_probe_observer_attached', details: observerDetails);
  }

  Map<String, Object?> _scalarSnapshotDetails(DataSnapshot snapshot) {
    return <String, Object?>{
      'exists': snapshot.exists,
      'value': AppResumeDiagnostics.probeValueForDiagnostics(snapshot.value),
    };
  }

  Map<String, Object?> _gamesSnapshotDetails(DataSnapshot snapshot) {
    final Object? rawValue = snapshot.value;
    final Map<Object?, Object?>? rawGames = rawValue is Map
        ? Map<Object?, Object?>.from(rawValue)
        : null;
    final DateTime nowUtc = _now().toUtc();
    final DateTime earliestUtc = nowUtc.subtract(const Duration(days: 8));
    final DateTime latestUtc = nowUtc.add(const Duration(days: 2));
    final List<Map<String, Object?>> recentGames = <Map<String, Object?>>[];

    for (final MapEntry<Object?, Object?> entry
        in rawGames?.entries ?? const <MapEntry<Object?, Object?>>[]) {
      final Object? rawGameValue = entry.value;
      if (rawGameValue is! Map) {
        continue;
      }
      final Map<Object?, Object?> rawGame = Map<Object?, Object?>.from(
        rawGameValue,
      );
      final Object? rawDateUtc = rawGame['DateUtc'];
      final DateTime? startUtc = rawDateUtc is String
          ? DateTime.tryParse(rawDateUtc)?.toUtc()
          : null;
      if (startUtc == null ||
          startUtc.isBefore(earliestUtc) ||
          startUtc.isAfter(latestUtc)) {
        continue;
      }
      recentGames.add(<String, Object?>{
        'gameKey': entry.key?.toString(),
        'startUtc': startUtc.toIso8601String(),
        'homeScore': rawGame['HomeTeamScore'],
        'awayScore': rawGame['AwayTeamScore'],
      });
    }
    recentGames.sort(
      (a, b) => (a['startUtc'] as String).compareTo(b['startUtc'] as String),
    );

    return <String, Object?>{
      'exists': snapshot.exists,
      'entryCount': rawGames?.length ?? 0,
      'recentGames': recentGames.take(40).toList(),
    };
  }

  Future<void> stop({String reason = 'manual'}) async {
    final int? generation = _activeGeneration;
    final String? probeId = _activeProbeId;
    if (generation == null || probeId == null) {
      return;
    }

    final Map<String, Object?> identity = _identityDetails();
    final Map<String, StreamSubscription<DatabaseEvent>> subscriptions =
        Map<String, StreamSubscription<DatabaseEvent>>.from(_subscriptions);
    final SecondaryRealtimeDatabaseDiagnosticClient? client = _client;
    _subscriptions.clear();
    _client = null;
    _activeGeneration = null;
    _activeProbeId = null;
    _activeAppName = null;

    for (final MapEntry<String, StreamSubscription<DatabaseEvent>> entry
        in subscriptions.entries) {
      final Map<String, Object?> details = <String, Object?>{
        ...identity,
        'observer': entry.key,
        'reason': reason,
      };
      _emit('secondary_probe_observer_cancel_requested', details: details);
      try {
        await entry.value.cancel();
        _emit('secondary_probe_observer_cancelled', details: details);
      } catch (error) {
        _emit(
          'secondary_probe_observer_cancel_failed',
          details: <String, Object?>{
            ...details,
            'error': error.toString(),
          },
          anomalous: true,
        );
      }
    }

    if (client != null) {
      _emit(
        'secondary_probe_client_dispose_requested',
        details: <String, Object?>{...identity, 'reason': reason},
      );
      try {
        await client.dispose();
        _emit(
          'secondary_probe_client_disposed',
          details: <String, Object?>{...identity, 'reason': reason},
        );
      } catch (error) {
        _emit(
          'secondary_probe_client_dispose_failed',
          details: <String, Object?>{
            ...identity,
            'reason': reason,
            'error': error.toString(),
          },
          anomalous: true,
        );
      }
    }

    _emit(
      'secondary_probe_stopped',
      details: <String, Object?>{...identity, 'reason': reason},
    );
  }

  Map<String, Object?> _identityDetails() {
    return <String, Object?>{
      'probeId': _activeProbeId,
      'observerGeneration': _activeGeneration,
      'secondaryAppName': _activeAppName,
      'diagnosticProbePath': diagnosticProbePath,
      'configProbePath': configProbePath,
      'gamesPath': gamesPath,
    };
  }

  void _emit(
    String stage, {
    Map<String, Object?> details = const <String, Object?>{},
    bool anomalous = false,
  }) {
    _recordEvent(stage, details, anomalous);
  }
}

class AppResumeDiagnostics {
  AppResumeDiagnostics._();

  static const bool compileTimeEnabled = bool.fromEnvironment(
    'ANDROID_RESUME_DIAGNOSTICS',
    defaultValue: false,
  );
  static const String diagnosticProbePath =
      '/Diagnostics/androidResumeProbe';
  static const String configProbeKey = 'resumeProbe';

  static ResumeDiagnosticsRecorder? _recorder;
  static StreamSubscription<DatabaseEvent>? _connectionSubscription;
  static RealtimeDatabaseDiagnosticProbe? _extendedProbe;
  static SecondaryRealtimeDatabaseDiagnosticProbe? _secondaryProbe;
  static int _connectionObserverGenerationCounter = 0;
  static int? _activeConnectionObserverGeneration;
  static bool? _latestSdkReportedConnected;
  static DateTime? _latestConnectionSampleUtc;

  static bool get enabled => _recorder != null;
  static bool get extendedProbeActive => _extendedProbe?.active ?? false;
  static bool get secondaryProbeActive => _secondaryProbe?.active ?? false;

  static Object? probeValueForDiagnostics(Object? value) {
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is String) {
      return value.length <= 256
          ? value
          : '${value.substring(0, 256)}<truncated>';
    }
    return '<${value.runtimeType}>';
  }

  static Future<void> initialize({
    required Map<String, Object?> processDetails,
  }) async {
    if (!compileTimeEnabled || _recorder != null) {
      return;
    }
    final DateTime processStartUtc = DateTime.now().toUtc();
    final ResumeDiagnosticsRecorder recorder = ResumeDiagnosticsRecorder(
      storage: await createResumeDiagnosticsStorage(),
      processId: 'android-${processStartUtc.microsecondsSinceEpoch}',
    );
    await recorder.initialize(processDetails: processDetails);
    _recorder = recorder;
  }

  static void record(
    String stage, {
    Map<String, Object?> details = const <String, Object?>{},
    bool anomalous = false,
    bool attachToActiveAttempt = true,
    bool requireActiveAttempt = false,
    String? dedupeKey,
  }) {
    final ResumeDiagnosticsRecorder? recorder = _recorder;
    if (recorder == null) {
      return;
    }
    try {
      unawaited(
        recorder.record(
          stage,
          details: details,
          anomalous: anomalous,
          attachToActiveAttempt: attachToActiveAttempt,
          requireActiveAttempt: requireActiveAttempt,
          dedupeKey: dedupeKey,
        ),
      );
    } catch (error, stackTrace) {
      log(
        'Failed to enqueue Android resume diagnostics: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void beginAttempt({required FirebaseDatabase database}) {
    final ResumeDiagnosticsRecorder? recorder = _recorder;
    if (recorder == null) {
      return;
    }
    recorder.beginAttempt();
    final StreamSubscription<DatabaseEvent>? previousSubscription =
        _connectionSubscription;
    if (previousSubscription != null) {
      unawaited(
        _cancelConnectionObserver(
          previousSubscription,
          generation: _activeConnectionObserverGeneration,
          reason: 'replaced_by_resume_attempt',
        ),
      );
    }
    final int observerGeneration = ++_connectionObserverGenerationCounter;
    _activeConnectionObserverGeneration = observerGeneration;
    _latestSdkReportedConnected = null;
    _latestConnectionSampleUtc = null;
    _connectionSubscription = database.ref('.info/connected').onValue.listen(
      (event) {
        final bool? connected = event.snapshot.value is bool
            ? event.snapshot.value as bool
            : null;
        _latestSdkReportedConnected = connected;
        _latestConnectionSampleUtc = DateTime.now().toUtc();
        record(
          'sdk_reported_connection_state',
          details: <String, Object?>{
            'connected': connected,
            'observerGeneration': observerGeneration,
            'observerKind': 'resume_attempt',
          },
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        record(
          'connection_observer_error',
          details: <String, Object?>{
            'error': error.toString(),
            'observerGeneration': observerGeneration,
            'observerKind': 'resume_attempt',
          },
          anomalous: true,
        );
      },
      onDone: () {
        record(
          'connection_observer_done',
          details: <String, Object?>{
            'observerGeneration': observerGeneration,
            'observerKind': 'resume_attempt',
          },
          anomalous: true,
        );
      },
    );
    record(
      'connection_observer_attached',
      details: <String, Object?>{
        'observerGeneration': observerGeneration,
        'observerKind': 'resume_attempt',
      },
    );
  }

  static void recordReconnectStarted() {
    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime? sampleUtc = _latestConnectionSampleUtc;
    record(
      'reconnect_started',
      details: <String, Object?>{
        'sdkReportedConnected': _latestSdkReportedConnected,
        'connectionSampleAgeMs': sampleUtc == null
            ? null
            : nowUtc.difference(sampleUtc).inMilliseconds,
      },
    );
  }

  static void finishAttempt({bool anomalous = false}) {
    final StreamSubscription<DatabaseEvent>? subscription =
        _connectionSubscription;
    _connectionSubscription = null;
    final int? generation = _activeConnectionObserverGeneration;
    _activeConnectionObserverGeneration = null;
    if (subscription != null) {
      unawaited(
        _cancelConnectionObserver(
          subscription,
          generation: generation,
          reason: 'resume_attempt_finished',
        ),
      );
    }
    _recorder?.finishAttempt(anomalous: anomalous);
  }

  static Future<void> startExtendedProbe({
    required FirebaseDatabase database,
  }) async {
    if (_recorder == null) {
      return;
    }
    final RealtimeDatabaseDiagnosticProbe probe =
        _extendedProbe ??= RealtimeDatabaseDiagnosticProbe(
          database: database,
          probePath: diagnosticProbePath,
          recordEvent: (stage, details, anomalous) {
            record(
              stage,
              details: details,
              anomalous: anomalous,
              attachToActiveAttempt: false,
            );
          },
        );
    await probe.start();
  }

  static Future<void> stopExtendedProbe({String reason = 'manual'}) async {
    await _extendedProbe?.stop(reason: reason);
  }

  static Future<void> startSecondaryProbe({required String gamesPath}) async {
    if (_recorder == null) {
      return;
    }
    if (!extendedProbeActive) {
      record(
        'secondary_probe_started_without_primary_probe',
        details: <String, Object?>{'gamesPath': gamesPath},
        anomalous: true,
        attachToActiveAttempt: false,
      );
    }
    final SecondaryRealtimeDatabaseDiagnosticProbe probe =
        _secondaryProbe ??= SecondaryRealtimeDatabaseDiagnosticProbe(
          gamesPath: gamesPath,
          clientFactory: _createSecondaryDiagnosticClient,
          recordEvent: (stage, details, anomalous) {
            record(
              stage,
              details: details,
              anomalous: anomalous,
              attachToActiveAttempt: false,
            );
          },
        );
    await probe.start();
  }

  static Future<void> stopSecondaryProbe({String reason = 'manual'}) async {
    await _secondaryProbe?.stop(reason: reason);
    _secondaryProbe = null;
  }

  static Future<SecondaryRealtimeDatabaseDiagnosticClient>
  _createSecondaryDiagnosticClient(
    String appName,
    ResumeProbeEventRecorder recordEvent,
  ) async {
    FirebaseApp? app;
    try {
      recordEvent(
        'secondary_probe_firebase_app_initializing',
        const <String, Object?>{},
        false,
      );
      app = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      recordEvent(
        'secondary_probe_firebase_app_initialized',
        <String, Object?>{
          'projectId': app.options.projectId,
          'databaseUrlPresent': app.options.databaseURL?.isNotEmpty ?? false,
        },
        false,
      );

      final FirebaseAppCheck appCheck = FirebaseAppCheck.instanceFor(app: app);
      try {
        final bool useDebugProvider = kDebugMode || kProfileMode;
        recordEvent(
          'secondary_probe_app_check_activation_started',
          <String, Object?>{
            'provider': useDebugProvider ? 'debug' : 'play_integrity',
          },
          false,
        );
        await appCheck.activate(
          providerAndroid: useDebugProvider
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
        );
        recordEvent(
          'secondary_probe_app_check_activation_completed',
          const <String, Object?>{},
          false,
        );
      } catch (error) {
        recordEvent(
          'secondary_probe_app_check_activation_failed',
          <String, Object?>{'error': error.toString()},
          true,
        );
      }

      try {
        recordEvent(
          'secondary_probe_app_check_token_refresh_started',
          const <String, Object?>{},
          false,
        );
        final AppCheckTokenResult? tokenResult = await appCheck
            .getTokenResult(true)
            .timeout(const Duration(seconds: 20));
        recordEvent(
          'secondary_probe_app_check_token_refresh_completed',
          <String, Object?>{
            'tokenReady': tokenResult?.token.isNotEmpty ?? false,
            'expirationUtc': tokenResult?.expirationTime
                ?.toUtc()
                .toIso8601String(),
          },
          tokenResult?.token.isEmpty ?? true,
        );
      } catch (error) {
        recordEvent(
          'secondary_probe_app_check_token_refresh_failed',
          <String, Object?>{'error': error.toString()},
          true,
        );
      }

      final FirebaseDatabase database = FirebaseDatabase.instanceFor(
        app: app,
        databaseURL: app.options.databaseURL,
      );
      database.setPersistenceEnabled(false);
      recordEvent(
        'secondary_probe_database_created',
        const <String, Object?>{'persistenceEnabled': false},
        false,
      );
      try {
        database.setLoggingEnabled(true);
        recordEvent(
          'secondary_probe_native_logging_enabled',
          const <String, Object?>{},
          false,
        );
      } catch (error) {
        recordEvent(
          'secondary_probe_native_logging_failed',
          <String, Object?>{'error': error.toString()},
          true,
        );
      }

      return SecondaryRealtimeDatabaseDiagnosticClient(
        appName: appName,
        database: database,
        dispose: () async {
          try {
            await database.goOffline();
          } finally {
            await app!.delete();
          }
        },
      );
    } catch (error) {
      recordEvent(
        'secondary_probe_client_creation_failed',
        <String, Object?>{'error': error.toString()},
        true,
      );
      if (app != null) {
        try {
          await app.delete();
        } catch (deleteError) {
          recordEvent(
            'secondary_probe_failed_app_cleanup',
            <String, Object?>{'error': deleteError.toString()},
            true,
          );
        }
      }
      rethrow;
    }
  }

  static Future<void> _cancelConnectionObserver(
    StreamSubscription<DatabaseEvent> subscription, {
    required int? generation,
    required String reason,
  }) async {
    final Map<String, Object?> details = <String, Object?>{
      'observerGeneration': generation,
      'observerKind': 'resume_attempt',
      'reason': reason,
    };
    record('connection_observer_cancel_requested', details: details);
    try {
      await subscription.cancel();
      record('connection_observer_cancelled', details: details);
    } catch (error) {
      record(
        'connection_observer_cancel_failed',
        details: <String, Object?>{
          ...details,
          'error': error.toString(),
        },
        anomalous: true,
      );
    }
  }

  static void recordGamePresentation({
    required String gameKey,
    required String presentation,
    required String gameState,
    required int? officialHomeScore,
    required int? officialAwayScore,
    required int? displayedHomeScore,
    required int? displayedAwayScore,
    required int liveScoreCount,
  }) {
    record(
      'widget_game_observed',
      details: <String, Object?>{
        'gameKey': gameKey,
        'presentation': presentation,
        'gameState': gameState,
        'officialHomeScore': officialHomeScore,
        'officialAwayScore': officialAwayScore,
        'displayedHomeScore': displayedHomeScore,
        'displayedAwayScore': displayedAwayScore,
        'liveScoreCount': liveScoreCount,
      },
      dedupeKey:
          '$gameKey|$presentation|$gameState|$officialHomeScore|$officialAwayScore|$displayedHomeScore|$displayedAwayScore|$liveScoreCount',
    );
  }

  static Future<String> exportText() async {
    return _recorder?.exportText() ?? '';
  }

  static Future<List<String>> exportTextChunks({
    int maxChunkBytes = 200 * 1024,
  }) async {
    return _recorder?.exportTextChunks(maxChunkBytes: maxChunkBytes) ??
        const <String>[];
  }

  static Future<List<ResumeDiagnosticEvent>> readEvents() async {
    return _recorder?.readEvents() ?? const <ResumeDiagnosticEvent>[];
  }

  @visibleForTesting
  static void installRecorderForTest(ResumeDiagnosticsRecorder recorder) {
    _recorder = recorder;
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    await _extendedProbe?.stop(reason: 'test_reset');
    _extendedProbe = null;
    await _secondaryProbe?.stop(reason: 'test_reset');
    _secondaryProbe = null;
    final StreamSubscription<DatabaseEvent>? connectionSubscription =
        _connectionSubscription;
    _connectionSubscription = null;
    await connectionSubscription?.cancel();
    _connectionObserverGenerationCounter = 0;
    _activeConnectionObserverGeneration = null;
    _latestSdkReportedConnected = null;
    _latestConnectionSampleUtc = null;
    _recorder = null;
  }
}

Map<String, Object?> _jsonSafeDetails(Map<String, Object?> details) {
  return details.map(
    (key, value) => MapEntry<String, Object?>(key, _jsonSafeValue(value)),
  );
}

Object? _jsonSafeValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is Iterable<Object?>) {
    return value.map(_jsonSafeValue).toList();
  }
  if (value is Map) {
    return value.map(
      (key, nestedValue) => MapEntry<String, Object?>(
        key.toString(),
        _jsonSafeValue(nestedValue),
      ),
    );
  }
  return value.toString();
}
