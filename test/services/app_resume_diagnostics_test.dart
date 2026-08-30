import 'dart:convert';

import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
