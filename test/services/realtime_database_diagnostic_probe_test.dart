import 'dart:async';

import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseDatabase extends Mock implements FirebaseDatabase {}

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

void main() {
  late MockFirebaseDatabase database;
  late MockDatabaseReference connectionReference;
  late MockDatabaseReference probeReference;
  late StreamController<DatabaseEvent> connectionEvents;
  late StreamController<DatabaseEvent> probeEvents;
  late List<Map<String, Object?>> recordedEvents;
  late RealtimeDatabaseDiagnosticProbe probe;

  setUp(() {
    database = MockFirebaseDatabase();
    connectionReference = MockDatabaseReference();
    probeReference = MockDatabaseReference();
    connectionEvents = StreamController<DatabaseEvent>.broadcast();
    probeEvents = StreamController<DatabaseEvent>.broadcast();
    recordedEvents = <Map<String, Object?>>[];

    when(() => database.ref('.info/connected')).thenReturn(
      connectionReference,
    );
    when(() => database.ref('/Diagnostics/testProbe')).thenReturn(
      probeReference,
    );
    when(() => connectionReference.onValue).thenAnswer(
      (_) => connectionEvents.stream,
    );
    when(() => probeReference.onValue).thenAnswer((_) => probeEvents.stream);

    probe = RealtimeDatabaseDiagnosticProbe(
      database: database,
      probePath: '/Diagnostics/testProbe',
      now: () => DateTime.utc(2026, 9, 5, 12),
      recordEvent: (stage, details, anomalous) {
        recordedEvents.add(<String, Object?>{
          'stage': stage,
          'details': details,
          'anomalous': anomalous,
        });
      },
    );
  });

  tearDown(() async {
    await probe.stop(reason: 'test_teardown');
    await connectionEvents.close();
    await probeEvents.close();
  });

  test('records observer lifetimes and backend nonce snapshots', () async {
    await probe.start();

    expect(probe.active, isTrue);
    expect(connectionEvents.hasListener, isTrue);
    expect(probeEvents.hasListener, isTrue);

    connectionEvents.add(_event(value: false, exists: true));
    probeEvents.add(_event(value: 'nonce-20260905-1', exists: true));
    await Future<void>.delayed(Duration.zero);

    expect(
      recordedEvents.map((event) => event['stage']),
      containsAllInOrder(<String>[
        'extended_probe_started',
        'extended_probe_connection_observer_attached',
        'extended_probe_fresh_listener_attached',
        'extended_probe_connection_state',
        'extended_probe_fresh_listener_snapshot',
      ]),
    );
    final Map<String, Object?> connectionDetails = _detailsFor(
      recordedEvents,
      'extended_probe_connection_state',
    );
    final Map<String, Object?> snapshotDetails = _detailsFor(
      recordedEvents,
      'extended_probe_fresh_listener_snapshot',
    );
    expect(connectionDetails['connected'], isFalse);
    expect(snapshotDetails['value'], 'nonce-20260905-1');
    expect(snapshotDetails['exists'], isTrue);
    expect(
      snapshotDetails['probeId'],
      'probe-1788609600000000-1',
    );
    expect(snapshotDetails['observerGeneration'], 1);

    await probe.stop(reason: 'manual_test_stop');

    expect(probe.active, isFalse);
    expect(connectionEvents.hasListener, isFalse);
    expect(probeEvents.hasListener, isFalse);
    final Iterable<Map<String, Object?>> cancelledEvents = recordedEvents.where(
      (event) => event['stage'] == 'extended_probe_observer_cancelled',
    );
    expect(cancelledEvents, hasLength(2));
    expect(
      cancelledEvents.map(
        (event) => (event['details'] as Map<String, Object?>)['observer'],
      ),
      containsAll(<String>['connection', 'fresh_listener']),
    );
    expect(
      _detailsFor(recordedEvents, 'extended_probe_stopped')['reason'],
      'manual_test_stop',
    );
  });

  test('does not attach duplicate observers while already active', () async {
    await probe.start();
    await probe.start();

    verify(() => database.ref('.info/connected')).called(1);
    verify(() => database.ref('/Diagnostics/testProbe')).called(1);
    expect(
      recordedEvents.map((event) => event['stage']),
      contains('extended_probe_start_ignored_already_active'),
    );
  });

  test('secondary client records independent snapshots and disposes', () async {
    final MockFirebaseDatabase secondaryDatabase = MockFirebaseDatabase();
    final Map<String, MockDatabaseReference> references =
        <String, MockDatabaseReference>{};
    final Map<String, StreamController<DatabaseEvent>> eventControllers =
        <String, StreamController<DatabaseEvent>>{};
    for (final String path in <String>[
      '.info/connected',
      '/Diagnostics/testProbe',
      '/AppConfig/resumeProbe',
      '/DAUCompsGames/test-comp',
    ]) {
      final MockDatabaseReference reference = MockDatabaseReference();
      final StreamController<DatabaseEvent> controller =
          StreamController<DatabaseEvent>.broadcast();
      references[path] = reference;
      eventControllers[path] = controller;
      when(() => secondaryDatabase.ref(path)).thenReturn(reference);
      when(() => reference.onValue).thenAnswer((_) => controller.stream);
    }
    final List<Map<String, Object?>> secondaryEvents =
        <Map<String, Object?>>[];
    int disposeCount = 0;
    final SecondaryRealtimeDatabaseDiagnosticProbe secondaryProbe =
        SecondaryRealtimeDatabaseDiagnosticProbe(
          gamesPath: '/DAUCompsGames/test-comp',
          diagnosticProbePath: '/Diagnostics/testProbe',
          now: () => DateTime.utc(2026, 9, 7, 12),
          clientFactory: (appName, recordEvent) async {
            recordEvent(
              'secondary_probe_app_check_token_refresh_completed',
              const <String, Object?>{'tokenReady': true},
              false,
            );
            return SecondaryRealtimeDatabaseDiagnosticClient(
              appName: appName,
              database: secondaryDatabase,
              dispose: () async {
                disposeCount++;
              },
            );
          },
          recordEvent: (stage, details, anomalous) {
            secondaryEvents.add(<String, Object?>{
              'stage': stage,
              'details': details,
              'anomalous': anomalous,
            });
          },
        );

    await secondaryProbe.start();

    expect(secondaryProbe.active, isTrue);
    expect(
      eventControllers.values.every((controller) => controller.hasListener),
      isTrue,
    );
    eventControllers['.info/connected']!.add(
      _event(value: true, exists: true),
    );
    eventControllers['/Diagnostics/testProbe']!.add(
      _event(value: 'secondary-nonce', exists: true),
    );
    eventControllers['/AppConfig/resumeProbe']!.add(
      _event(value: 42, exists: true),
    );
    eventControllers['/DAUCompsGames/test-comp']!.add(
      _event(
        value: <String, Object?>{
          'nrl-27-200': <String, Object?>{
            'DateUtc': '2026-09-06 05:00:00Z',
            'HomeTeamScore': 31,
            'AwayTeamScore': 30,
          },
          'old-game': <String, Object?>{
            'DateUtc': '2026-08-01 05:00:00Z',
            'HomeTeamScore': 1,
            'AwayTeamScore': 2,
          },
        },
        exists: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      secondaryEvents.map((event) => event['stage']),
      containsAll(<String>[
        'secondary_probe_app_check_token_refresh_completed',
        'secondary_probe_connection_snapshot',
        'secondary_probe_diagnostic_probe_snapshot',
        'secondary_probe_config_probe_snapshot',
        'secondary_probe_games_snapshot',
      ]),
    );
    expect(
      _detailsFor(
        secondaryEvents,
        'secondary_probe_connection_snapshot',
      )['connected'],
      isTrue,
    );
    expect(
      _detailsFor(
        secondaryEvents,
        'secondary_probe_diagnostic_probe_snapshot',
      )['value'],
      'secondary-nonce',
    );
    final Map<String, Object?> gamesDetails = _detailsFor(
      secondaryEvents,
      'secondary_probe_games_snapshot',
    );
    expect(gamesDetails['entryCount'], 2);
    expect(gamesDetails['recentGames'], <Map<String, Object?>>[
      <String, Object?>{
        'gameKey': 'nrl-27-200',
        'startUtc': '2026-09-06T05:00:00.000Z',
        'homeScore': 31,
        'awayScore': 30,
      },
    ]);

    await secondaryProbe.stop(reason: 'manual_test_stop');

    expect(secondaryProbe.active, isFalse);
    expect(disposeCount, 1);
    expect(
      eventControllers.values.every((controller) => !controller.hasListener),
      isTrue,
    );
    expect(
      secondaryEvents
          .where(
            (event) => event['stage'] == 'secondary_probe_observer_cancelled',
          )
          .length,
      4,
    );
    expect(
      _detailsFor(secondaryEvents, 'secondary_probe_stopped')['reason'],
      'manual_test_stop',
    );

    for (final StreamController<DatabaseEvent> controller
        in eventControllers.values) {
      await controller.close();
    }
  });

  test('secondary client does not create a duplicate while active', () async {
    final MockFirebaseDatabase secondaryDatabase = MockFirebaseDatabase();
    final List<StreamController<DatabaseEvent>> controllers =
        <StreamController<DatabaseEvent>>[];
    for (final String path in <String>[
      '.info/connected',
      '/Diagnostics/androidResumeProbe',
      '/AppConfig/resumeProbe',
      '/DAUCompsGames/test-comp',
    ]) {
      final MockDatabaseReference reference = MockDatabaseReference();
      final StreamController<DatabaseEvent> controller =
          StreamController<DatabaseEvent>.broadcast();
      controllers.add(controller);
      when(() => secondaryDatabase.ref(path)).thenReturn(reference);
      when(() => reference.onValue).thenAnswer((_) => controller.stream);
    }
    final List<Map<String, Object?>> secondaryEvents =
        <Map<String, Object?>>[];
    int createCount = 0;
    final SecondaryRealtimeDatabaseDiagnosticProbe secondaryProbe =
        SecondaryRealtimeDatabaseDiagnosticProbe(
          gamesPath: '/DAUCompsGames/test-comp',
          clientFactory: (appName, recordEvent) async {
            createCount++;
            return SecondaryRealtimeDatabaseDiagnosticClient(
              appName: appName,
              database: secondaryDatabase,
              dispose: () async {},
            );
          },
          recordEvent: (stage, details, anomalous) {
            secondaryEvents.add(<String, Object?>{
              'stage': stage,
              'details': details,
              'anomalous': anomalous,
            });
          },
        );

    await secondaryProbe.start();
    await secondaryProbe.start();

    expect(createCount, 1);
    expect(
      secondaryEvents.map((event) => event['stage']),
      contains('secondary_probe_start_ignored_already_active'),
    );

    await secondaryProbe.stop(reason: 'test_teardown');
    for (final StreamController<DatabaseEvent> controller in controllers) {
      await controller.close();
    }
  });

  test('secondary client resets its lifecycle after creation failure', () async {
    final List<Map<String, Object?>> secondaryEvents =
        <Map<String, Object?>>[];
    final SecondaryRealtimeDatabaseDiagnosticProbe secondaryProbe =
        SecondaryRealtimeDatabaseDiagnosticProbe(
          gamesPath: '/DAUCompsGames/test-comp',
          clientFactory: (appName, recordEvent) async {
            throw StateError('secondary app unavailable');
          },
          recordEvent: (stage, details, anomalous) {
            secondaryEvents.add(<String, Object?>{
              'stage': stage,
              'details': details,
              'anomalous': anomalous,
            });
          },
        );

    await expectLater(
      secondaryProbe.start(),
      throwsA(isA<StateError>()),
    );

    expect(secondaryProbe.active, isFalse);
    expect(
      secondaryEvents.map((event) => event['stage']),
      containsAllInOrder(<String>[
        'secondary_probe_started',
        'secondary_probe_start_failed',
        'secondary_probe_stopped',
      ]),
    );
    expect(
      secondaryEvents.singleWhere(
        (event) => event['stage'] == 'secondary_probe_start_failed',
      )['anomalous'],
      isTrue,
    );
  });
}

MockDatabaseEvent _event({required Object? value, required bool exists}) {
  final MockDatabaseEvent event = MockDatabaseEvent();
  final MockDataSnapshot snapshot = MockDataSnapshot();
  when(() => event.snapshot).thenReturn(snapshot);
  when(() => snapshot.value).thenReturn(value);
  when(() => snapshot.exists).thenReturn(exists);
  return event;
}

Map<String, Object?> _detailsFor(
  List<Map<String, Object?>> events,
  String stage,
) {
  return events.singleWhere((event) => event['stage'] == stage)['details']!
      as Map<String, Object?>;
}
