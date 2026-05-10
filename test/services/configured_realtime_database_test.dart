import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseDatabase extends Mock implements FirebaseDatabase {}

class MockDatabaseReference extends Mock implements DatabaseReference {}

void main() {
  late MockFirebaseDatabase mockDatabase;
  late MockDatabaseReference mockRootReference;
  late MockDatabaseReference mockPathReference;

  setUp(() {
    ConfiguredRealtimeDatabase.resetForTest();
    mockDatabase = MockFirebaseDatabase();
    mockRootReference = MockDatabaseReference();
    mockPathReference = MockDatabaseReference();
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
