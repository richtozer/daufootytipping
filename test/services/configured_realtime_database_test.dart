import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';
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
}
