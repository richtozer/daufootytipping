import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:json_diff/json_diff.dart';

// define  constant for firestore database locations
final tippersPath = dotenv.env['TIPPERS_PATH'];

class TippersViewModel extends ChangeNotifier {
  List<Tipper> _tippers = [];
  late Tipper _linkedTipper;

  Tipper get linkedTipper => _linkedTipper;

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _tippersStream;

  //List<Tipper> get tippers => _tippers;

  bool _savingTipper = false;
  bool get savingTipper => _savingTipper;

  bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  final Completer<void> _initialLoadCompleter = Completer<void>();

  //constructor
  TippersViewModel() {
    log('TippersViewModel() constructor called');
    _listenToTippers();
  }

  // monitor changes to tippers records in DB and notify listeners of any changes
  void _listenToTippers() {
    _tippersStream = _db.child(tippersPath!).onValue.listen((event) {
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
      log('Tipper db Listener: ${_tippers.length} tippers found in database');
    } else {
      log('Tipper db Listener: No tippers found in database');
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

  Future<void> editTipper(Tipper updatedTipper) async {
    try {
      if (!_initialLoadCompleter.isCompleted) {
        log('Waiting for initial Tipper load to complete, edittipper()');
        await _initialLoadCompleter.future;
        log('tipper load complete, editTipper()');
      }

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
        log('Tipper: ${updatedTipper.dbkey} updated in database to $updates');
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
      if (!_initialLoadCompleter.isCompleted) {
        log('Waiting for initial Tipper load to complete, addTipper()');
        await _initialLoadCompleter.future;
        log('tipper load complete, addTipper()');
      }

      _savingTipper = true;
      notifyListeners();

      // prepare a new tipper database entry
      final entry = tipperData.toJson();

      // Get a dbkey for a new Tipper.
      dbkey = _db.child(tippersPath!).push().key;

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
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial tipper load to complete, findtipperbyuid($authuid)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findtipperbyuid($authuid)');
    }

    return _tippers.firstWhereOrNull((tipper) => tipper.authuid == authuid);
  }

  Future<Tipper?> findTipperByEmail(String email) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial tipper load to complete, findtipperbyemail($email)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findtipperbyemail($email)');
    }
    return _tippers.firstWhereOrNull((tipper) => tipper.email == email);
  }

  Future<Tipper?> findTipperByName(String name) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial tipper load to complete, findtipperbyname($name)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findTipperByName($name)');
    }
    return _tippers.firstWhereOrNull((tipper) => tipper.name == name);
  }

  // this function finds the provided Tipper dbKey in the _tipper list and returns it
  Future<Tipper> findTipper(String tipperDbKey) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial Tipper load to complete in findTipper($tipperDbKey)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findTipper($tipperDbKey)');
    }
    return _tippers.firstWhere((tipper) => tipper.dbkey == tipperDbKey);
  }

  //method to sync Tipper changes from Legacy GSheet Tipping Service Tipper sheet to Firebase
  // 1) input parameter is a list of Tippers from the Legacy GSheet Tipping Service
  // 2) compare each Tipper in the list to the Tippers in the Firebase database
  // 3) if the Tipper does not exist in the Firebase database, add it
  // 4) if the Tipper does exist in the Firebase database, update it
  // 5) if the Tipper exists in the Firebase database but not in the Legacy GSheet Tipping Service, delete it

  Future<void> syncTippers() async {
    try {
      _isLegacySyncing = true;
      notifyListeners();

      LegacyTippingService tippingService =
          GetIt.instance<LegacyTippingService>();

      List<Tipper> legacyTippers = [];

      await Future.wait([
        tippingService.getTippers().then((tippers) => legacyTippers = tippers),
        _initialLoadCompleter.future,
      ]);

      log('syncTippers() tipper load complete');

      // loop through each Tipper in the legacyTippers list - skip the header row
      await Future.forEach(legacyTippers.skip(1), (legacyTipper) async {
        // find the Tipper in the Firebase database based on the tipperID
        Tipper? firebaseTipper = _tippers.firstWhereOrNull(
            (tipper) => tipper.tipperID == legacyTipper.tipperID);

        // if the Tipper does not exist in the Firebase database, add it
        if (firebaseTipper == null) {
          log('syncTippers() Tipper: ${legacyTipper.tipperID} for tipper ${legacyTipper.name} does not exist in the database, adding it');
          await addTipper(legacyTipper);
        } else {
          // if the Tipper does exist in the Firebase database, update it
          log('syncTippers() Tipper: ${legacyTipper.tipperID} for tipper ${legacyTipper.name} exists in the database, updating it');
          //to support legacy syncing, reverse copy the dbkey to the legacy record before calling editTipper()
          legacyTipper.dbkey = firebaseTipper.dbkey;
          await editTipper(legacyTipper);
        }
      });

      // loop through each Tipper in the Firebase database
      await Future.forEach(_tippers, ((firebaseTipper) async {
        // find the Tipper in the legacyTippers list
        Tipper? legacyTipper = legacyTippers.firstWhereOrNull(
            (tipper) => tipper.tipperID == firebaseTipper.tipperID);

        // if the Tipper does not exist in the legacyTippers list, investigate it
        if (legacyTipper == null) {
          log('syncTippers() TipperID: ${firebaseTipper.tipperID} for tipper ${firebaseTipper.name} does not exist in the legacyTippers list, investigate it');
          //await deleteTipper(firebaseTipper);
          throw Exception(
              'syncTippers() TipperID: ${firebaseTipper.tipperID} for tipper ${firebaseTipper.name} does not exist in the legacyTippers list, investigate it');
        }
      }));
    } finally {
      _isLegacySyncing = false;
      notifyListeners();
    }
  }

  // method called at logon to find logged in Tipper and return it
  // first try finding the tipper based on authuid
  // if that fails, try finding the tipper based on email
  Future<Tipper> linkUserToTipper(User authenticatedFirebaseUser) async {
    Tipper? currentTipper;

    // first try finding the tipper based on authuid
    currentTipper = await findTipperByUid(authenticatedFirebaseUser.uid);

    if (currentTipper != null) {
      log('linkUserToTipper() Tipper ${currentTipper.name} found using uid: ${authenticatedFirebaseUser.uid}');
      return currentTipper;
    }

    // if that fails, try finding the tipper based on email
    currentTipper ??= await findTipperByEmail(authenticatedFirebaseUser.email!);

    if (currentTipper != null) {
      log('linkUserToTipper() Tipper ${currentTipper.name} found using email: ${authenticatedFirebaseUser.email}. Updating UID in database');
      // update UID in database. create a new Tipper object to submit the change
      Tipper updatedTipper = Tipper(
        dbkey: currentTipper.dbkey,
        tipperID: currentTipper.tipperID,
        name: currentTipper.name,
        email: currentTipper.email,
        authuid: authenticatedFirebaseUser.uid, //make the change here
        tipperRole: currentTipper.tipperRole,
        active: currentTipper.active,
      );

      await editTipper(updatedTipper);

      return updatedTipper;
    } else {
      throw Exception(
          'getLoggedInTipper() Existing Tipper not found for user: ${authenticatedFirebaseUser.email}');
    }
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
