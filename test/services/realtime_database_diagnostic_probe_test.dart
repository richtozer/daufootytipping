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
