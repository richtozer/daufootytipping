import 'package:firebase_database/firebase_database.dart';

abstract class DauCompsRepository {
  Stream<DatabaseEvent> streamDauComps(String daucompsPath);
  Future<void> update(Map<String, dynamic> updates);
  Future<String> newCompKey(String daucompsPath);
}

class FirebaseDauCompsRepository implements DauCompsRepository {
  FirebaseDatabase? _db;
  FirebaseDauCompsRepository({FirebaseDatabase? db}) : _db = db;

  FirebaseDatabase get _database => _db ?? FirebaseDatabase.instance;

  @override
  Stream<DatabaseEvent> streamDauComps(String daucompsPath) {
    return _database.ref().child(daucompsPath).onValue;
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
