import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:flutter/material.dart';
import 'package:json_diff/json_diff.dart';

// define  constant for firestore database locations
const tippersPath = '/Tippers';

class TippersViewModel extends ChangeNotifier {
  List<Tipper> _tippers = [];

  bool _initialLoadComplete = false;
  bool _linkingUnderway = false;
  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _tippersStream;
  //int _currentTipperIndex =
  //  -1; //we need to use an index to track the current tipper -
  // our consumers in the widget tree are only listening for changes to the List<Tipper> _tippers

  List<Tipper> get tippers => _tippers;

  bool _savingTipper = false;
  bool get savingTipper => _savingTipper;
  bool get initialLoadComplete => _initialLoadComplete;
  int _currentTipperIndex =
      -1; //assume we dont know the current tipper index at startup

  int get currentTipperIndex {
    return _currentTipperIndex;
  }

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
      final allTippers =
          Map<String, dynamic>.from(event.snapshot.value as dynamic);

      List<Tipper?> tippersList =
          await Future.wait(allTippers.entries.map((entry) async {
        String key = entry.key; // Retrieve the Firebase key
        dynamic tipperasJSON = entry.value;

        return Tipper.fromJson(Map<String, dynamic>.from(tipperasJSON), key);
      }).toList());

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
    } else {
      log('XXX No tippers found in database');
    }
    _initialLoadComplete = true;
    notifyListeners();
  }

  void linkTipper(User? firebaseUser) async {
    try {
      if (_linkingUnderway) {
        log('linking is already underway');
        return; // do nothing if linking is already underway
      } else {
        _linkingUnderway = true;
      }

      while (!_initialLoadComplete) {
        log('Waiting for initial Tipper load to complete, linktipper()');
        await Future.delayed(const Duration(seconds: 1));
      }
      log('tipper load complete, linkTipper()');
      //see if we can find an existing Tipper record using uid
      Tipper? foundTipper = findTipperByUid(firebaseUser!.uid);

      if (foundTipper != null) {
        //we found an existing Tipper record using uid, so use it
        _currentTipperIndex = (_tippers.indexOf(foundTipper));
      } else {
        //if we can't find an existing Tipper record using uid, see if we can find an existing Tipper record using email

        Tipper? foundTipper = findTipperByEmail(firebaseUser.email!);
        if (foundTipper != null) {
          //update the tipper record to use the firebase uid
          Tipper updateTipper = Tipper(
            dbkey: foundTipper.dbkey,
            authuid: firebaseUser.uid,
            email: foundTipper.email,
            name: foundTipper.name,
            active: foundTipper.active,
            tipperRole: foundTipper.tipperRole,
          );

          //update the tipper record in the database
          editTipper(updateTipper);

          //save the current logged on tipper to the model for later use
          _currentTipperIndex = (_tippers.indexOf(updateTipper));
          //otherwise create a new tipper record and link it to the firebase user, set active to false and tipperrole to tipper
          Tipper newTipper = Tipper(
            name: firebaseUser.email!,
            email: firebaseUser.email!,
            authuid: firebaseUser.uid,
            active: false,
            tipperRole: TipperRole.tipper,
          );
          addTipper(newTipper);
          _currentTipperIndex = (_tippers.indexOf(newTipper));
        }
      }
    } finally {
      _linkingUnderway = false;
    }
  }

  void editTipper(Tipper updatedTipper) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial Tipper load to complete, edittipper()');
        await Future.delayed(const Duration(seconds: 1));
      }
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
        _db.update(updates);
      } else {
        log('Tipper: ${updatedTipper.dbkey} does not exist in the database, ignoring edit request');
      }
    } finally {
      _savingTipper = false;
      notifyListeners();
    }
  }

  String? addTipper(Tipper tipperData) {
    final String? dbkey;
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial Tipper load to complete, addTipper()');
        Future.delayed(const Duration(seconds: 1));
      }
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
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);

      if (dbkey != null) {
        return dbkey;
      } else {
        return null;
      }
    } finally {
      _savingTipper = false;
      notifyListeners();
    }
  }

  Tipper? findTipperByUid(String authuid) {
    while (!_initialLoadComplete) {
      log('Waiting for initial tipper load to complete, findtipperbyuid()');
      Future.delayed(const Duration(seconds: 1));
    }
    log('tipper load complete, findtipperbyuid()');
    return _tippers.firstWhereOrNull((tipper) => tipper.authuid == authuid);
  }

  Tipper? findTipperByEmail(String email) {
    while (!_initialLoadComplete) {
      log('Waiting for initial tipper load to complete, findtipperbyemail()');
      Future.delayed(const Duration(seconds: 1));
    }
    log('tipper load complete, findtipperbyemail()');
    return _tippers.firstWhereOrNull((tipper) => tipper.email == email);
  }

  // this function finds the provided Tipper dbKey in the _tipper list and returns it
  Future<Tipper> findTipper(String tipperDbKey) async {
    while (!_initialLoadComplete) {
      log('Waiting for initial Tipper load to complete in findTipper()');
      await Future.delayed(const Duration(seconds: 1));
    }
    return _tippers.firstWhere((tipper) => tipper.dbkey == tipperDbKey);
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
