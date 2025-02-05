import 'dart:async';
import 'dart:developer';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConfigViewModel extends ChangeNotifier {
  final DatabaseReference _database =
      FirebaseDatabase.instance.ref().child('/AppConfig');
  late StreamSubscription<DatabaseEvent> _configStream;

  String? _activeDAUComp;
  String? get activeDAUComp => _activeDAUComp;

  String? _minAppVersion;
  String? get minAppVersion => _minAppVersion;

  bool? _createLinkedTipper;
  bool? get createLinkedTipper => _createLinkedTipper;

  ConfigViewModel() {
    _initialize();
    _listenToConfigChanges();
  }

  Future<void> _initialize() async {
    log('ConfigViewModel._initialize()');

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
      } else {
        _processSnapshot(dbEvent.snapshot);
      }
    } on TimeoutException catch (e) {
      log('Cannot connect to database. Operation timed out: $e');
      rethrow;
    } catch (e) {
      log('An unexpected error occurred: $e');
      rethrow;
    }
  }

  void _listenToConfigChanges() {
    _configStream = _database.onValue.listen((event) {
      if (event.snapshot.exists) {
        _processSnapshot(event.snapshot);
      } else {
        log('ConfigViewModel._listenToConfigChanges() No config found in database');
      }
    }, onError: (error) {
      log('ConfigViewModel._listenToConfigChanges() Error: $error');
    });
  }

  void _processSnapshot(DataSnapshot snapshot) {
    _activeDAUComp = snapshot.child('currentDAUComp').value.toString();
    _minAppVersion = snapshot.child('minAppVersion').value.toString();
    _createLinkedTipper = snapshot.child('createLinkedTipper').value as bool;
    notifyListeners();
  }

  Future<void> setConfigCurrentDAUComp(String value) async {
    await _database.child('currentDAUComp').set(value);
  }

  Future<void> setConfigMinAppVersion(String value) async {
    await _database.child('minAppVersion').set(value);
  }

  Future<void> setCreateLinkedTipper(bool value) async {
    await _database.child('createLinkedTipper').set(value);
  }

  @override
  void dispose() {
    _configStream.cancel();
    super.dispose();
  }
}
