import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';

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

  FirebaseService? firebaseService;

  //constructor
  TippersViewModel(this.firebaseService) {
    log('TippersViewModel() constructor called');

    if (firebaseService != null) {
      firebaseService!.addListener(handleFirebaseServiceChange);
    }
    _listenToTippers();
  }

  void handleFirebaseServiceChange() {
    registerLinkedTipperForMessaging();
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
          tippersList.where((tipper) => tipper != null).cast<Tipper>().toList();
      _tippers.sort();

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

  final Map<String, dynamic> updates = {};

  Future<void> updateTipperAttribute(
      String tipperDbKey, String attributeName, dynamic attributeValue) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial Tipper load to complete, updateTipperAttribute()');
      await _initialLoadCompleter.future;
      log('tipper load complete, updateTipperAttribute()');
    }

    //find the Tipper in the local list. it it's there, compare the attribute value and update if different
    Tipper? tipperToUpdate = await findTipper(tipperDbKey);

    dynamic oldValue = tipperToUpdate.toJson()[attributeName];
    if (attributeValue != oldValue) {
      log('Tipper: $tipperDbKey needs update for attribute $attributeName: $attributeValue');
      updates['$tippersPath/$tipperDbKey/$attributeName'] = attributeValue;
    } else {
      log('Tipper: $tipperDbKey already has $attributeName: $attributeValue');
    }
  }

  Future<void> saveBatchOfTipperAttributes() async {
    try {
      if (!_initialLoadCompleter.isCompleted) {
        log('Waiting for initial Tipper load to complete, saveBatchOfTipperAttributes()');
        await _initialLoadCompleter.future;
        log('tipper load complete, saveBatchOfTipperAttributes()');
      }
      await _db.update(updates);
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

  Future<Tipper?> findTipperByLegayTipperID(String tipperId) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial tipper load to complete, findTipperByLegayTipperID($tipperId)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findTipperByName($tipperId)');
    }
    return _tippers.firstWhereOrNull((tipper) => tipper.tipperID == tipperId);
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
        tippingService
            .getLegacyTippers()
            .then((tippers) => legacyTippers = tippers),
        _initialLoadCompleter.future,
      ]);

      log('syncTippers() legacy tipper sheet load complete');

      if (!_initialLoadCompleter.isCompleted) {
        log('Waiting for initial Tipper load to complete in syncTippers()');
        await _initialLoadCompleter.future;
        log('tipper load complete, syncTippers()');
      }

      // loop through each Tipper in the legacyTippers list - skip the header row
      await Future.forEach(legacyTippers.skip(1), (legacyTipper) async {
        // if the Tipper does not exist in the Firebase database, add it
        Tipper? existingTipper =
            await findTipperByLegayTipperID(legacyTipper.tipperID);
        if (existingTipper == null) {
          log('syncTippers() TipperID: ${legacyTipper.tipperID} for tipper ${legacyTipper.name} does not exist in the Firebase database, adding it');
          // newTipper() will create a new db key for the new record and return a modified Tipper object with the new db key
          await newTipper(legacyTipper);
        } else {
          log('syncTippers() TipperID: ${legacyTipper.tipperID} for tipper ${legacyTipper.name} exists in the Firebase database, updating it');

          // submit each attribute of the legacyTipper to the updateTipperAttribute method,
          // it will take care of only submitteing the attributes that have changed to db
          await updateTipperAttribute(
              existingTipper.dbkey!, 'name', legacyTipper.name);
          await updateTipperAttribute(
              existingTipper.dbkey!, 'email', legacyTipper.email);
          await updateTipperAttribute(
              existingTipper.dbkey!, 'tipperID', legacyTipper.tipperID);
          await updateTipperAttribute(
              existingTipper.dbkey!, 'active', legacyTipper.active);
          await updateTipperAttribute(existingTipper.dbkey!, 'tipperRole',
              legacyTipper.tipperRole.toString().split('.').last);
        }
      });

      await saveBatchOfTipperAttributes();

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

  Future<void> newTipper(
    Tipper newTipper,
  ) async {
    await _initialLoadCompleter.future;

    if (newTipper.dbkey == null) {
      log('Adding new Tipper record');
      // add new record to updates Map, create a new db key first
      DatabaseReference newTipperRecordKey = _db.child(tippersPath!).push();
      newTipper.dbkey = newTipperRecordKey.key;
      updates['$tippersPath/${newTipper.dbkey}'] = newTipper.toJson();
    } else {
      throw 'newTipper() called with existing Tipper dbkey, should be an update';
    }
  }

  Future<Tipper> getLinkedTipper() async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial Tipper load to complete in getLinkedTipper()');
      await _initialLoadCompleter.future;
      log('tipper load complete, getLinkedTipper()');
    }
    await linkUserToTipper(FirebaseAuth.instance.currentUser!);
    return _linkedTipper;
  }

  // method called at logon to find logged in Tipper and return it
  // first try finding the tipper based on authuid
  // if that fails, try finding the tipper based on email
  Future<void> linkUserToTipper(User authenticatedFirebaseUser) async {
    Tipper? currentTipper;

    // first try finding the tipper based on authuid
    currentTipper = await findTipperByUid(authenticatedFirebaseUser.uid);

    if (currentTipper != null) {
      log('linkUserToTipper() Tipper ${currentTipper.name} found using uid: ${authenticatedFirebaseUser.uid}');
      _linkedTipper = currentTipper;
      await registerLinkedTipperForMessaging();
    }

    // if that fails, try finding the tipper based on email
    currentTipper ??= await findTipperByEmail(authenticatedFirebaseUser.email!);

    if (currentTipper != null) {
      log('linkUserToTipper() Tipper ${currentTipper.name} found using email: ${authenticatedFirebaseUser.email}. Updating UID in database');

      await updateTipperAttribute(
          currentTipper.dbkey!, "authuid", authenticatedFirebaseUser.uid);

      await saveBatchOfTipperAttributes();

      await registerLinkedTipperForMessaging();
    } else {
      throw Exception(
          'getLoggedInTipper() Existing Tipper record not found for email: ${authenticatedFirebaseUser.email}. Try logging in with an email you provided for tipping or contact DAU support.');
    }
  }

  Future<void> registerLinkedTipperForMessaging() async {
    // loop through any existing device tokens for this tipper, if the token
    // does not exist, add it, otherwise update the timestamp for the existing token
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial Tipper load to complete in registerLinkedTipperForMessaging()');
      await _initialLoadCompleter.future;
      log('tipper load complete, registerLinkedTipperForMessaging()');
    }

    String? token = firebaseService?.fbmToken;

    if (_linkedTipper.deviceTokens != null) {
      if (_linkedTipper.deviceTokens!
          .every((element) => element!.token != token!)) {
        //it does not exist, add it
        _linkedTipper.deviceTokens!
            .add(DeviceToken(token: token!, timestamp: DateTime.now()));
      } else {
        //it does exist, update the timestamp
        _linkedTipper.deviceTokens!
            .firstWhere((element) => element!.token == token)
            ?.timestamp = DateTime.now();
      }
    } else {
      _linkedTipper.deviceTokens = [
        DeviceToken(token: token!, timestamp: DateTime.now().toUtc())
      ];
    }

    List deviceTokenList = _linkedTipper.deviceTokens
            ?.map((deviceToken) => deviceToken?.toJson())
            .toList() ??
        [];

    await updateTipperAttribute(
        _linkedTipper.dbkey!, "deviceTokens", deviceTokenList);

    await saveBatchOfTipperAttributes();
  }

  //monitor change to fbm token and update the tipper record in the database
/*   void updateFbmToken(String? token) {
    if (newToken != null) {
      log('New messaging token received, updating database: $newToken');
      _linkedTipper.deviceTokens!
          .add(DeviceToken(token: newToken, timestamp: DateTime.now()));
      // save to database
      editTipper(_linkedTipper);
      //notifyListeners();
    }
  } */

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
