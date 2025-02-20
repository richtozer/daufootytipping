import 'dart:async';
import 'dart:developer';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

const configPathRoot = '/AppConfig';

class ConfigViewModel extends ChangeNotifier {
  final DatabaseReference _db = FirebaseDatabase.instance.ref(configPathRoot);
  late StreamSubscription<DatabaseEvent> _configStream;

  String? _activeDAUComp;
  String? get activeDAUComp => _activeDAUComp;

  String? _minAppVersion;
  String? get minAppVersion => _minAppVersion;

  bool? _createLinkedTipper;
  bool? get createLinkedTipper => _createLinkedTipper;

  String? _googleClientId;
  String? get googleClientId => _googleClientId;

  final Completer<void> _initialLoadCompleter = Completer<void>();

  get initialLoadComplete => _initialLoadCompleter.future;

  ConfigViewModel() {
    _listenToConfigChanges();
  }

  void _listenToConfigChanges() {
    _configStream = _db.onValue.listen((event) {
      if (event.snapshot.exists) {
        _processSnapshot(event.snapshot);
      } else {
        log('ConfigViewModel._listenToConfigChanges() No config found in database');
      }

      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
    }, onError: (error) {
      log('ConfigViewModel._listenToConfigChanges() Error: $error');
    });
  }

  void _processSnapshot(DataSnapshot snapshot) {
    _activeDAUComp = snapshot.child('currentDAUComp').value.toString();
    _minAppVersion = snapshot.child('minAppVersion').value.toString();
    _createLinkedTipper = snapshot.child('createLinkedTipper').value as bool;
    _googleClientId = snapshot.child('googleClientId').value.toString();
  }

  Future<void> setConfigCurrentDAUComp(String value) async {
    await _db.child('currentDAUComp').set(value);
  }

  Future<void> setConfigMinAppVersion(String value) async {
    await _db.child('minAppVersion').set(value);
  }

  Future<void> setCreateLinkedTipper(bool value) async {
    await _db.child('createLinkedTipper').set(value);
  }

  @override
  void dispose() {
    _configStream.cancel();
    super.dispose();
  }
}
