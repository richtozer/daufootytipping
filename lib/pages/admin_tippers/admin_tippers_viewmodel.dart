import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:json_diff/json_diff.dart';

// define  constant for firestore database locations
const tippersPath = '/Tippers';

class TippersViewModel extends ChangeNotifier {
  List<Tipper> _tippers = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _tippersStream;

  //List<Tipper> get tippers => _tippers;

  bool _savingTipper = false;
  bool get savingTipper => _savingTipper;

  final Completer<void> _initialLoadCompleter = Completer<void>();

  //constructor
  TippersViewModel() {
    _listenToTippers();
  }

  // monitor changes to tippers records in DB and notify listeners of any changes
  void _listenToTippers() {
    _tippersStream = _db.child(tippersPath).onValue.listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    if (event.snapshot.exists) {
      List<Tipper?> tippersList = Tipper.fromJsonList(event.snapshot.value);

      _tippers =
          tippersList.where((game) => game != null).cast<Tipper>().toList();
      _tippers.sort();

      /* TODO - while the above code works fine, it would not work if we added the
        firebase OrderbyValue() method. 

        https://stackoverflow.com/questions/61333194/flutter-firebase-real-time-database-orderbychild-has-no-impact-on-query-result
      
        The code below does sort of work, but the List[] keeps growing and items get 
        duplicated in the UI. 

      if (event.snapshot.exists) {
        // we need to use a foreach loop here to get data to orderbychild()
        event.snapshot.children.forEach((tipperRecordJSON) {
          String key =
              tipperRecordJSON.key as String; // Retrieve the Firebase key
          dynamic tipperasJSON = tipperRecordJSON.value;

          final tipper =
              Tipper.fromJson(Map<String, dynamic>.from(tipperasJSON), key);
          _tippers.add(tipper);
        });
        */
      log('XXX ${_tippers.length} tippers found in database');
    } else {
      log('XXX No tippers found in database');
    }
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }
    notifyListeners();
  }

  Future<List<Tipper>> getTippers() async {
    await _initialLoadCompleter.future;
    return _tippers;
  }

  void editTipper(Tipper updatedTipper) async {
    try {
      log('Waiting for initial Tipper load to complete, edittipper()');
      await _initialLoadCompleter.future;
      log('tipper load complete, editTipper()');

      _savingTipper = true;
      notifyListeners();

      //the original Tipper record should be in our list of tippers
      Tipper? originalTipper = _tippers.firstWhereOrNull(
          (existingTipper) => existingTipper.dbkey == updatedTipper.dbkey);

      //only edit the tipper record if it already exists, otherwise ignore
      if (originalTipper != null) {
        // Convert the original and updated tippers to JSON
        Map<String, dynamic> originalJson = originalTipper.toJson();
        Map<String, dynamic> updatedJson = updatedTipper.toJson();

        // Use JsonDiffer to get the differences
        JsonDiffer differ = JsonDiffer.fromJson(originalJson, updatedJson);
        DiffNode diff = differ.diff();

        // Initialize an empty map to hold all updates
        Map<String, dynamic> updates = {};

        // transform the changes from JsonDiffer format to Firebase format
        Map changed = diff.changed;
        changed.keys.toList().forEach((key) {
          if (changed[key] is List && (changed[key] as List).isNotEmpty) {
            // Add the update to the updates map
            updates['$tippersPath/${updatedTipper.dbkey}/$key'] =
                changed[key][1];
          }
        });

        // Apply any updates to Firebase
        await _db.update(updates);
      } else {
        log('Tipper: ${updatedTipper.dbkey} does not exist in the database, ignoring edit request');
      }
    } finally {
      _savingTipper = false;
      notifyListeners();
    }
  }

  Future<String?> addTipper(Tipper tipperData) async {
    final String? dbkey;
    try {
      log('Waiting for initial Tipper load to complete, addTipper()');
      await _initialLoadCompleter.future;
      log('tipper load complete, addTipper()');
      _savingTipper = true;
      notifyListeners();

      // prepare a new tipper database entry
      final entry = tipperData.toJson();

      // Get a dbkey for a new Tipper.
      dbkey = _db.child(tippersPath).push().key;

      // write to database
      final Map<String, Map> updates = {};
      updates['$tippersPath/$dbkey'] = entry;

      await _db.update(updates);

      return dbkey;
    } finally {
      _savingTipper = false;
      notifyListeners();
    }
  }

  Future<Tipper?> findTipperByUid(String authuid) async {
    log('Waiting for initial tipper load to complete, findtipperbyuid()');
    await _initialLoadCompleter.future;
    log('tipper load complete, findtipperbyuid()');
    return _tippers.firstWhereOrNull((tipper) => tipper.authuid == authuid);
  }

  Future<Tipper?> findTipperByEmail(String email) async {
    log('Waiting for initial tipper load to complete, findtipperbyemail()');
    await _initialLoadCompleter.future;
    log('tipper load complete, findtipperbyemail()');
    return _tippers.firstWhereOrNull((tipper) => tipper.email == email);
  }

  // this function finds the provided Tipper dbKey in the _tipper list and returns it
  Future<Tipper> findTipper(String tipperDbKey) async {
    log('Waiting for initial Tipper load to complete in findTipper()');
    await _initialLoadCompleter.future;
    return _tippers.firstWhere((tipper) => tipper.dbkey == tipperDbKey);
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
