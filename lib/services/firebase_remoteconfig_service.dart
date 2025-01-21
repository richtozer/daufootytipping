import 'dart:async';
import 'dart:developer';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RemoteConfigService {
  final DatabaseReference _database =
      FirebaseDatabase.instance.ref().child('/AppConfig');

  RemoteConfigService() {
    initialize();
  }

  Future<String> getConfigCurrentDAUComp() async {
    DatabaseEvent dbEvent = await _database.child('currentDAUComp').once();
    return dbEvent.snapshot.value.toString();
  }

  void setConfigCurrentDAUComp(String value) async {
    await _database.child('currentDAUComp').set(value);
  }

  Future<String> getConfigMinAppVersion() async {
    DatabaseEvent dbEvent = await _database.child('minAppVersion').once();
    return dbEvent.snapshot.value.toString();
  }

  Future<bool> getCreateLinkedTipper() async {
    DatabaseEvent dbEvent = await _database.child('createLinkedTipper').once();
    return dbEvent.snapshot.value as bool;
  }

  Future<void> initialize() async {
    log('RemoteConfigService.initialize()');

    try {
      DatabaseEvent dbEvent =
          await _database.once().timeout(const Duration(seconds: 5));

      if (!dbEvent.snapshot.exists) {
        // New DB? Set default values in db from ENV file if needed
        await _database.set({
          "currentDAUComp": dotenv.env['CURRENT_DAU_COMP'],
          "minAppVersion": dotenv.env['MIN_APP_VERSION'],
          "createLinkedTipper":
              dotenv.env['CREATELINKEDTIPPER']!.toLowerCase() == 'true'
                  ? true
                  : false,
        });
      }
    } on TimeoutException catch (e) {
      log('Cannot connect to database. Operation timed out: $e');
      rethrow;
    } catch (e) {
      log('An unexpected error occurred: $e');
      rethrow;
    }
  }
}
