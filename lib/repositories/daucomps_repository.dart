import 'package:daufootytipping/services/auth_aware_stream.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';

abstract class DauCompsRepository {
  Stream<DatabaseEvent> streamDauComps(String daucompsPath);
  Future<void> update(Map<String, dynamic> updates);
  Future<String> newCompKey(String daucompsPath);
}

class FirebaseDauCompsRepository implements DauCompsRepository {
  final FirebaseDatabase? _db;
  FirebaseDauCompsRepository({FirebaseDatabase? db}) : _db = db;

  FirebaseDatabase get _database => _db ?? configuredRealtimeDatabase;

  /// Opens the listener only once a user is signed in: the competitions need a
  /// session under the R2 rules, and a listener attached before one is cancelled
  /// for good (see [authAwareStream]).
  @override
  Stream<DatabaseEvent> streamDauComps(String daucompsPath) {
    return authAwareStream<DatabaseEvent>(
      signedIn: firebaseSignedInStream,
      open: () => _database.ref().child(daucompsPath).onValue,
    );
  }

  @override
  Future<void> update(Map<String, dynamic> updates) async {
    await _database.ref().update(updates);
  }

  @override
  Future<String> newCompKey(String daucompsPath) async {
    return _database.ref().child(daucompsPath).push().key!;
  }
}
