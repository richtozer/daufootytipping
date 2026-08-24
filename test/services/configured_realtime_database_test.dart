import 'dart:async';

import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseDatabase extends Mock implements FirebaseDatabase {}

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

void main() {
  late MockFirebaseDatabase mockDatabase;
  late MockDatabaseReference mockRootReference;
  late MockDatabaseReference mockPathReference;
  late MockDatabaseReference mockConnectedReference;

  setUp(() {
    ConfiguredRealtimeDatabase.resetForTest();
    mockDatabase = MockFirebaseDatabase();
    mockRootReference = MockDatabaseReference();
    mockPathReference = MockDatabaseReference();
    mockConnectedReference = MockDatabaseReference();
  });

  test('throws when accessed before configuration', () {
    expect(() => configuredRealtimeDatabase, throwsStateError);
    expect(() => configuredDatabaseRef(), throwsStateError);
  });

  test('returns the configured database instance and refs', () {
    when(() => mockDatabase.ref()).thenReturn(mockRootReference);
    when(() => mockDatabase.ref('ConfigRoot')).thenReturn(mockPathReference);

    ConfiguredRealtimeDatabase.configure(mockDatabase);

    expect(configuredRealtimeDatabase, same(mockDatabase));
    expect(configuredDatabaseRef(), same(mockRootReference));
    expect(configuredDatabaseRef('ConfigRoot'), same(mockPathReference));
  });

  test('waits for the database to report connected after going online', () async {
    final connectionEvents = StreamController<DatabaseEvent>.broadcast();
    final connectedEvent = MockDatabaseEvent();
    final connectedSnapshot = MockDataSnapshot();
    when(() => mockDatabase.goOffline()).thenAnswer((_) async {});
    when(() => mockDatabase.goOnline()).thenAnswer((_) async {});
    when(
      () => mockDatabase.ref('.info/connected'),
    ).thenReturn(mockConnectedReference);
    when(
      () => mockConnectedReference.onValue,
    ).thenAnswer((_) => connectionEvents.stream);
    when(() => connectedEvent.snapshot).thenReturn(connectedSnapshot);
    when(() => connectedSnapshot.value).thenReturn(true);
    ConfiguredRealtimeDatabase.configure(mockDatabase);

    var refreshCompleted = false;
    final refresh = restartRealtimeDatabaseConnection().then(
      (_) => refreshCompleted = true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(refreshCompleted, isFalse);
    connectionEvents.add(connectedEvent);
    await refresh;

    verifyInOrder([
      () => mockDatabase.goOffline(),
      () => mockDatabase.goOnline(),
    ]);
    expect(refreshCompleted, isTrue);
    await connectionEvents.close();
  });

  test('times out when the database does not reconnect', () async {
    when(() => mockDatabase.goOffline()).thenAnswer((_) async {});
    when(() => mockDatabase.goOnline()).thenAnswer((_) async {});
    when(
      () => mockDatabase.ref('.info/connected'),
    ).thenReturn(mockConnectedReference);
    when(
      () => mockConnectedReference.onValue,
    ).thenAnswer((_) => const Stream<DatabaseEvent>.empty());

    await expectLater(
      restartRealtimeDatabaseConnection(
        database: mockDatabase,
        connectionTimeout: Duration.zero,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  group('configureRealtimeDatabasePersistence', () {
    test('sets cache size before enabling persistence on Android', () {
      configureRealtimeDatabasePersistence(
        mockDatabase,
        platform: TargetPlatform.android,
      );

      verifyInOrder([
        () => mockDatabase.setPersistenceCacheSizeBytes(
          realtimeDatabasePersistenceCacheSizeBytes,
        ),
        () => mockDatabase.setPersistenceEnabled(true),
      ]);
    });

    test('enables persistence before setting cache size on iOS', () {
      configureRealtimeDatabasePersistence(
        mockDatabase,
        platform: TargetPlatform.iOS,
      );

      verifyInOrder([
        () => mockDatabase.setPersistenceEnabled(true),
        () => mockDatabase.setPersistenceCacheSizeBytes(
          realtimeDatabasePersistenceCacheSizeBytes,
        ),
      ]);
    });

    test('uses iOS-compatible order on macOS', () {
      configureRealtimeDatabasePersistence(
        mockDatabase,
        platform: TargetPlatform.macOS,
      );

      verifyInOrder([
        () => mockDatabase.setPersistenceEnabled(true),
        () => mockDatabase.setPersistenceCacheSizeBytes(
          realtimeDatabasePersistenceCacheSizeBytes,
        ),
      ]);
    });
  });
}
