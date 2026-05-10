import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

const int realtimeDatabasePersistenceCacheSizeBytes = 100 * 1024 * 1024;

/// Provides the app's single configured Realtime Database instance.
class ConfiguredRealtimeDatabase {
  ConfiguredRealtimeDatabase._();

  static FirebaseDatabase? _instance;

  static FirebaseDatabase get instance {
    final FirebaseDatabase? database = _instance;
    if (database == null) {
      throw StateError(
        'Realtime Database was accessed before main() configured it.',
      );
    }
    return database;
  }

  static void configure(FirebaseDatabase database) {
    _instance = database;
  }

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }
}

FirebaseDatabase get configuredRealtimeDatabase =>
    ConfiguredRealtimeDatabase.instance;

DatabaseReference configuredDatabaseRef([String? path]) {
  final FirebaseDatabase database = configuredRealtimeDatabase;
  return path == null ? database.ref() : database.ref(path);
}

/// Applies native Realtime Database persistence settings in platform-specific
/// order. Android requires the cache size before persistence is enabled; iOS
/// and macOS currently require the opposite order.
void configureRealtimeDatabasePersistence(
  FirebaseDatabase database, {
  required TargetPlatform platform,
  int cacheSizeBytes = realtimeDatabasePersistenceCacheSizeBytes,
}) {
  if (platform == TargetPlatform.android) {
    database.setPersistenceCacheSizeBytes(cacheSizeBytes);
    database.setPersistenceEnabled(true);
    return;
  }

  database.setPersistenceEnabled(true);
  database.setPersistenceCacheSizeBytes(cacheSizeBytes);
}
