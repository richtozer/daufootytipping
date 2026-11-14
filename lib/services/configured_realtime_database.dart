import 'dart:async';

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

/// Reads [reference] once, as a listener on it would see it.
///
/// Use this, not `get()`, to read under a path the app may be listening to: on
/// iOS, while a listener was active on a parent, `get()` on a child answered with
/// the whole parent. A snapshot of any other path is refused with a
/// [StateError], so it is never taken for the value asked for.
Future<DataSnapshot> readOnce(DatabaseReference reference) async {
  final DataSnapshot snapshot = (await reference.once()).snapshot;
  if (snapshot.key != reference.key) {
    throw StateError(
      'Read of ${reference.key ?? 'the root'} answered with '
      '${snapshot.key ?? 'the root'}',
    );
  }
  return snapshot;
}

/// Whether the database has a live connection to the server, as it changes: true
/// or false, or null if the database reports something else.
Stream<bool?> realtimeDatabaseConnectionStates([FirebaseDatabase? database]) {
  return (database ?? configuredRealtimeDatabase)
      .ref('.info/connected')
      .onValue
      .map<bool?>(
        (DatabaseEvent event) =>
            event.snapshot.value is bool ? event.snapshot.value as bool : null,
      );
}

/// Restarts the native Realtime Database transport and waits until the SDK
/// reports a live server connection. Listeners and queued writes are retained.
Future<void> restartRealtimeDatabaseConnection({
  FirebaseDatabase? database,
  Duration connectionTimeout = const Duration(seconds: 10),
}) async {
  final FirebaseDatabase target = database ?? configuredRealtimeDatabase;
  await target.goOffline();
  await target.goOnline();
  await _waitUntilRealtimeDatabaseConnected(target, timeout: connectionTimeout);
}

Future<void> _waitUntilRealtimeDatabaseConnected(
  FirebaseDatabase database, {
  required Duration timeout,
}) async {
  final Completer<void> connected = Completer<void>();
  late final StreamSubscription<DatabaseEvent> subscription;
  subscription = database
      .ref('.info/connected')
      .onValue
      .listen(
        (event) {
          if (event.snapshot.value == true && !connected.isCompleted) {
            connected.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!connected.isCompleted) {
            connected.completeError(error, stackTrace);
          }
        },
      );

  try {
    await connected.future.timeout(timeout);
  } finally {
    await subscription.cancel();
  }
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
