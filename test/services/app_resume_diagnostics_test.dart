import 'dart:async';
import 'dart:convert';

import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseDatabase extends Mock implements FirebaseDatabase {}

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MemoryResumeDiagnosticsStorage implements ResumeDiagnosticsStorage {
  List<String> values = <String>[];
  int appendCount = 0;
  int replaceCount = 0;

  @override
  Future<void> appendLine(String encodedEvent) async {
    appendCount++;
    values.add(encodedEvent);
  }

  @override
  Future<List<String>> readLines() async => List<String>.from(values);

  @override
  Future<void> replaceLines(List<String> encodedEvents) async {
    replaceCount++;
    values = List<String>.from(encodedEvents);
  }
}

void main() {
  group('ResumeDiagnosticsRecorder', () {
    late MemoryResumeDiagnosticsStorage storage;
    late DateTime nowUtc;
    late ResumeDiagnosticsRecorder recorder;

    setUp(() async {
      storage = MemoryResumeDiagnosticsStorage();
      nowUtc = DateTime.utc(2026, 8, 30, 8);
      recorder = ResumeDiagnosticsRecorder(
        storage: storage,
        processId: 'process-a',
        now: () => nowUtc,
      );
      await recorder.initialize(
        processDetails: const <String, Object?>{'buildNumber': '705'},
      );
    });

    test('persists ordered events eagerly with one attempt id', () async {
      final String attemptId = recorder.beginAttempt();
      await recorder.record('reconnect_started');
      await recorder.record('fixture_get_returned');
      await recorder.flush();

      final List<ResumeDiagnosticEvent> events = await recorder.readEvents();
      final List<ResumeDiagnosticEvent> attemptEvents = events
          .where((event) => event.attemptId == attemptId)
          .toList();

      expect(
        attemptEvents.map((event) => event.stage),
        <String>[
          'attempt_started',
          'reconnect_started',
          'fixture_get_returned',
        ],
      );
      expect(storage.appendCount, 4);
      expect(storage.replaceCount, 0);
      expect(
        storage.values.map((value) => jsonDecode(value)['sequence']),
        orderedEquals(<int>[1, 2, 3, 4]),
      );
    });

    test('reloads events written by the previous process', () async {
      await recorder.record(
        'fixture_refresh_attempt_failed',
        anomalous: true,
      );

      final ResumeDiagnosticsRecorder nextProcess = ResumeDiagnosticsRecorder(
        storage: storage,
        processId: 'process-b',
        now: () => nowUtc.add(const Duration(minutes: 1)),
      );
      await nextProcess.initialize();

      final List<ResumeDiagnosticEvent> events =
          await nextProcess.readEvents();
      expect(
        events.map((event) => event.stage),
        containsAll(<String>[
          'fixture_refresh_attempt_failed',
          'process_started',
        ]),
      );
      expect(
        events.map((event) => event.processId).toSet(),
        <String>{'process-a', 'process-b'},
      );
    });

    test('enforces the event limit while the process is running', () async {
      final MemoryResumeDiagnosticsStorage limitedStorage =
          MemoryResumeDiagnosticsStorage();
      final ResumeDiagnosticsRecorder limitedRecorder =
          ResumeDiagnosticsRecorder(
            storage: limitedStorage,
            processId: 'limited-process',
            now: () => nowUtc,
            maxEvents: 3,
          );
      await limitedRecorder.initialize();

      for (int index = 0; index < 5; index++) {
        await limitedRecorder.record('event-$index');
      }

      final List<ResumeDiagnosticEvent> events =
          await limitedRecorder.readEvents();
      expect(events.map((event) => event.stage), <String>[
        'event-2',
        'event-3',
        'event-4',
      ]);
      expect(limitedStorage.replaceCount, greaterThan(0));
    });

    test('enforces the byte limit while the process is running', () async {
      const int maxStoredBytes = 1000;
      final MemoryResumeDiagnosticsStorage limitedStorage =
          MemoryResumeDiagnosticsStorage();
      final ResumeDiagnosticsRecorder limitedRecorder =
          ResumeDiagnosticsRecorder(
            storage: limitedStorage,
            processId: 'byte-limited-process',
            now: () => nowUtc,
            maxStoredBytes: maxStoredBytes,
          );
      await limitedRecorder.initialize();

      for (int index = 0; index < 10; index++) {
        await limitedRecorder.record(
          'event-$index',
          details: <String, Object?>{
            'payload': List<String>.filled(200, 'x').join(),
          },
        );
      }

      final List<ResumeDiagnosticEvent> events =
          await limitedRecorder.readEvents();
      final int persistedBytes = limitedStorage.values.fold<int>(
        0,
        (total, line) => total + utf8.encode(line).length + 1,
      );
      expect(persistedBytes, lessThanOrEqualTo(maxStoredBytes));
      expect(events.map((event) => event.stage), contains('event-9'));
      expect(events.length, lessThan(11));
      expect(limitedStorage.replaceCount, greaterThan(0));
    });

    test('exports complete JSONL as bounded line-safe chunks', () async {
      for (int index = 0; index < 8; index++) {
        await recorder.record(
          'chunk-event-$index',
          details: <String, Object?>{
            'payload': List<String>.filled(100, 'x').join(),
          },
        );
      }

      final String completeExport = await recorder.exportText();
      final List<String> chunks = await recorder.exportTextChunks(
        maxChunkBytes: 500,
      );

      expect(chunks.length, greaterThan(1));
      expect(chunks.join('\n'), completeExport);
      for (final String chunk in chunks) {
        expect(utf8.encode(chunk).length, lessThanOrEqualTo(500));
        for (final String line in chunk.split('\n')) {
          expect(jsonDecode(line), isA<Map<String, dynamic>>());
        }
      }
    });

    test('rejects a non-positive export chunk size', () async {
      expect(
        () => recorder.exportTextChunks(maxChunkBytes: 0),
        throwsArgumentError,
      );
    });

    test('retains an anomalous attempt longer than benign events', () async {
      recorder.beginAttempt();
      await recorder.record('reconnect_attempt_failed', anomalous: true);
      recorder.finishAttempt(anomalous: true);
      await recorder.flush();

      nowUtc = nowUtc.add(const Duration(days: 20));
      final ResumeDiagnosticsRecorder nextProcess = ResumeDiagnosticsRecorder(
        storage: storage,
        processId: 'process-b',
        now: () => nowUtc,
      );
      await nextProcess.initialize();

      final List<ResumeDiagnosticEvent> events =
          await nextProcess.readEvents();
      final List<String> stages = events.map((event) => event.stage).toList();
      expect(stages, contains('attempt_started'));
      expect(stages, contains('reconnect_attempt_failed'));
      expect(
        events
            .where((event) => event.stage == 'process_started')
            .map((event) => event.processId),
        <String>['process-b'],
      );
      expect(storage.replaceCount, 1);
    });

    test('deduplicates identical widget observations per attempt', () async {
      recorder.beginAttempt();
      await recorder.record(
        'widget_game_observed',
        dedupeKey: 'game-1|interim|10|8',
      );
      await recorder.record(
        'widget_game_observed',
        dedupeKey: 'game-1|interim|10|8',
      );

      final List<ResumeDiagnosticEvent> widgetEvents =
          (await recorder.readEvents())
              .where((event) => event.stage == 'widget_game_observed')
              .toList();
      expect(widgetEvents, hasLength(1));
    });

    test('does not record attempt-only events outside an attempt', () async {
      await recorder.record(
        'widget_game_observed',
        requireActiveAttempt: true,
      );

      expect(
        (await recorder.readEvents())
            .where((event) => event.stage == 'widget_game_observed'),
        isEmpty,
      );
    });

    test(
      'records late observations without attaching an expired attempt',
      () async {
        final String attemptId = recorder.beginAttempt();
        await recorder.record(
          'widget_game_observed',
          dedupeKey: 'game-1|interim|10|8',
        );
        recorder.finishAttempt();
        await recorder.flush();

        nowUtc = nowUtc.add(const Duration(minutes: 2));
        await recorder.record(
          'widget_game_observed',
          dedupeKey: 'game-1|interim|10|8',
        );

        final List<ResumeDiagnosticEvent> widgetEvents =
            (await recorder.readEvents())
                .where((event) => event.stage == 'widget_game_observed')
                .toList();
        expect(widgetEvents, hasLength(2));
        expect(widgetEvents.first.attemptId, attemptId);
        expect(widgetEvents.last.attemptId, isNull);
      },
    );

    test('retains an unattached anomalous event for thirty days', () async {
      await recorder.record(
        'lifecycle_refreshDroppedInProgress',
        anomalous: true,
        attachToActiveAttempt: false,
      );

      nowUtc = nowUtc.add(const Duration(days: 20));
      final ResumeDiagnosticsRecorder nextProcess = ResumeDiagnosticsRecorder(
        storage: storage,
        processId: 'process-b',
        now: () => nowUtc,
      );
      await nextProcess.initialize();

      expect(
        (await nextProcess.readEvents()).map((event) => event.stage),
        contains('lifecycle_refreshDroppedInProgress'),
      );
    });
  });

  group('AppResumeDiagnostics connection observer', () {
    late MemoryResumeDiagnosticsStorage storage;
    late ResumeDiagnosticsRecorder recorder;
    late MockFirebaseDatabase database;
    late MockDatabaseReference connectionReference;
    late StreamController<DatabaseEvent> connectionEvents;

    setUp(() async {
      await AppResumeDiagnostics.resetForTest();
      storage = MemoryResumeDiagnosticsStorage();
      recorder = ResumeDiagnosticsRecorder(
        storage: storage,
        processId: 'process-observer-test',
        now: () => DateTime.utc(2026, 9, 5, 14),
      );
      await recorder.initialize();
      AppResumeDiagnostics.installRecorderForTest(recorder);

      database = MockFirebaseDatabase();
      connectionReference = MockDatabaseReference();
      connectionEvents = StreamController<DatabaseEvent>.broadcast();
      when(() => database.ref('.info/connected')).thenReturn(
        connectionReference,
      );
      when(() => connectionReference.onValue).thenAnswer(
        (_) => connectionEvents.stream,
      );
    });

    tearDown(() async {
      await AppResumeDiagnostics.resetForTest();
      await connectionEvents.close();
    });

    test('records attach, sample, and cancel events for one generation', () async {
      AppResumeDiagnostics.beginAttempt(database: database);
      connectionEvents.add(_databaseEvent(value: false));
      await Future<void>.delayed(Duration.zero);

      AppResumeDiagnostics.finishAttempt(anomalous: true);
      await Future<void>.delayed(Duration.zero);
      await recorder.flush();

      final List<ResumeDiagnosticEvent> events = await recorder.readEvents();
      expect(
        events.map((event) => event.stage),
        containsAll(<String>[
          'connection_observer_attached',
          'sdk_reported_connection_state',
          'connection_observer_cancel_requested',
          'connection_observer_cancelled',
        ]),
      );
      for (final ResumeDiagnosticEvent event in events.where(
        (event) => event.stage.startsWith('connection_observer') ||
            event.stage == 'sdk_reported_connection_state',
      )) {
        expect(event.details['observerGeneration'], 1);
        expect(event.details['observerKind'], 'resume_attempt');
      }
      expect(
        events
            .singleWhere(
              (event) => event.stage == 'sdk_reported_connection_state',
            )
            .details['connected'],
        isFalse,
      );
      expect(
        events
            .singleWhere(
              (event) => event.stage == 'connection_observer_cancelled',
            )
            .details['reason'],
        'resume_attempt_finished',
      );
    });
  });

  group('AppResumeDiagnostics connection tracking', () {
    late MemoryResumeDiagnosticsStorage storage;
    late ResumeDiagnosticsRecorder recorder;
    late MockFirebaseDatabase database;
    late MockDatabaseReference connectionReference;
    late StreamController<DatabaseEvent> connectionEvents;

    setUp(() async {
      await AppResumeDiagnostics.resetForTest();
      storage = MemoryResumeDiagnosticsStorage();
      recorder = ResumeDiagnosticsRecorder(storage: storage, processId: 'p');
      await recorder.initialize();
      AppResumeDiagnostics.installRecorderForTest(recorder);

      database = MockFirebaseDatabase();
      connectionReference = MockDatabaseReference();
      connectionEvents = StreamController<DatabaseEvent>.broadcast();
      when(
        () => database.ref('.info/connected'),
      ).thenReturn(connectionReference);
      when(
        () => connectionReference.onValue,
      ).thenAnswer((_) => connectionEvents.stream);
    });

    tearDown(() async {
      await AppResumeDiagnostics.resetForTest();
      await connectionEvents.close();
    });

    Future<List<ResumeDiagnosticEvent>> eventsNamed(String stage) async {
      await recorder.flush();
      return (await recorder.readEvents())
          .where((event) => event.stage == stage)
          .toList();
    }

    test('records each change of state, not each repeated event', () async {
      AppResumeDiagnostics.startConnectionTracking(database: database);
      connectionEvents.add(_databaseEvent(value: false));
      connectionEvents.add(_databaseEvent(value: false));
      connectionEvents.add(_databaseEvent(value: true));
      connectionEvents.add(_databaseEvent(value: true));
      await Future<void>.delayed(Duration.zero);

      final List<ResumeDiagnosticEvent> changes = await eventsNamed(
        'sdk_connection_changed',
      );

      expect(changes.map((event) => event.details['connected']), <bool>[
        false,
        true,
      ]);
      expect(changes.first.details['previousConnected'], isNull);
      expect(changes.last.details['previousConnected'], isFalse);
      expect(changes.last.details['previousStateMs'], isA<int>());
    });

    test('keeps watching after a resume attempt finishes', () async {
      AppResumeDiagnostics.startConnectionTracking(database: database);
      AppResumeDiagnostics.beginAttempt(database: database);
      connectionEvents.add(_databaseEvent(value: false));
      await Future<void>.delayed(Duration.zero);
      AppResumeDiagnostics.finishAttempt();
      await Future<void>.delayed(Duration.zero);

      connectionEvents.add(_databaseEvent(value: true));
      await Future<void>.delayed(Duration.zero);

      final List<ResumeDiagnosticEvent> changes = await eventsNamed(
        'sdk_connection_changed',
      );
      expect(changes.map((event) => event.details['connected']), <bool>[
        false,
        true,
      ]);
    });

    test('starts only once', () async {
      AppResumeDiagnostics.startConnectionTracking(database: database);
      AppResumeDiagnostics.startConnectionTracking(database: database);
      connectionEvents.add(_databaseEvent(value: true));
      await Future<void>.delayed(Duration.zero);

      expect(await eventsNamed('sdk_connection_changed'), hasLength(1));
    });

    test('does nothing when diagnostics are off', () async {
      await AppResumeDiagnostics.resetForTest();

      AppResumeDiagnostics.startConnectionTracking(database: database);

      verifyNever(() => database.ref(any()));
    });
  });

  group('AppResumeDiagnostics.trackWrite', () {
    late MemoryResumeDiagnosticsStorage storage;
    late ResumeDiagnosticsRecorder recorder;

    setUp(() async {
      await AppResumeDiagnostics.resetForTest();
      storage = MemoryResumeDiagnosticsStorage();
      recorder = ResumeDiagnosticsRecorder(storage: storage, processId: 'p');
      await recorder.initialize();
      AppResumeDiagnostics.installRecorderForTest(recorder);
    });

    tearDown(() async {
      await AppResumeDiagnostics.resetForTest();
    });

    Future<List<ResumeDiagnosticEvent>> writeEvents() async {
      await recorder.flush();
      return (await recorder.readEvents())
          .where((event) => event.stage.startsWith('rtdb_write_'))
          .toList();
    }

    test('records the start and completion of a write and returns its result', () async {
      final int result = await AppResumeDiagnostics.trackWrite<int>(
        'tip_submit',
        () async => 42,
        details: const <String, Object?>{'pathCount': 1},
      );

      expect(result, 42);
      final List<ResumeDiagnosticEvent> events = await writeEvents();
      expect(events.map((event) => event.stage), <String>[
        'rtdb_write_started',
        'rtdb_write_completed',
      ]);
      expect(events.first.details['name'], 'tip_submit');
      expect(events.first.details['pathCount'], 1);
      expect(events.first.details['writeId'], events.last.details['writeId']);
      expect(events.last.details['elapsedMs'], isA<int>());
    });

    test('records a failure and rethrows it', () async {
      await expectLater(
        AppResumeDiagnostics.trackWrite<void>(
          'tipper_update',
          () async => throw StateError('permission denied'),
        ),
        throwsA(isA<StateError>()),
      );

      final List<ResumeDiagnosticEvent> events = await writeEvents();
      expect(events.map((event) => event.stage), <String>[
        'rtdb_write_started',
        'rtdb_write_failed',
      ]);
      expect(events.last.anomalous, isTrue);
      expect(events.last.details['error'], contains('permission denied'));
    });

    test('records a reminder while a write is still unacknowledged, then its late completion', () async {
      final Completer<void> serverAnswer = Completer<void>();

      final Future<void> tracked = AppResumeDiagnostics.trackWrite<void>(
        'tipper_update',
        () => serverAnswer.future,
        reminders: const <Duration>[Duration(milliseconds: 20)],
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      serverAnswer.complete();
      await tracked;

      final List<ResumeDiagnosticEvent> events = await writeEvents();
      expect(events.map((event) => event.stage), <String>[
        'rtdb_write_started',
        'rtdb_write_still_pending',
        'rtdb_write_completed',
      ]);
      expect(events[1].anomalous, isTrue);
      expect(events[1].details['elapsedMs'] as int, greaterThanOrEqualTo(20));
    });

    test('a write that finishes before its reminder leaves no reminder', () async {
      await AppResumeDiagnostics.trackWrite<void>(
        'tipper_update',
        () async {},
        reminders: const <Duration>[Duration(milliseconds: 30)],
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final List<ResumeDiagnosticEvent> events = await writeEvents();
      expect(
        events.map((event) => event.stage),
        isNot(contains('rtdb_write_still_pending')),
      );
    });

    test('adds nothing and still runs the write when diagnostics are off', () async {
      await AppResumeDiagnostics.resetForTest();
      var ran = false;

      final int result = await AppResumeDiagnostics.trackWrite<int>(
        'tip_submit',
        () async {
          ran = true;
          return 7;
        },
      );

      expect(ran, isTrue);
      expect(result, 7);
    });
  });

  group('AppResumeDiagnostics.supportsPlatform', () {
    test('records on the two phone platforms, where the resume stall is seen', () {
      expect(
        AppResumeDiagnostics.supportsPlatform(
          TargetPlatform.android,
          isWeb: false,
        ),
        isTrue,
      );
      expect(
        AppResumeDiagnostics.supportsPlatform(TargetPlatform.iOS, isWeb: false),
        isTrue,
      );
    });

    test('does not record on web or on the desktop platforms', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          AppResumeDiagnostics.supportsPlatform(platform, isWeb: true),
          isFalse,
          reason: 'web has no file storage for the log ($platform)',
        );
      }
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          AppResumeDiagnostics.supportsPlatform(platform, isWeb: false),
          isFalse,
          reason: '$platform is not a phone platform',
        );
      }
    });
  });
}

MockDatabaseEvent _databaseEvent({required Object? value}) {
  final MockDatabaseEvent event = MockDatabaseEvent();
  final MockDataSnapshot snapshot = MockDataSnapshot();
  when(() => event.snapshot).thenReturn(snapshot);
  when(() => snapshot.value).thenReturn(value);
  return event;
}
