import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:watch_it/watch_it.dart';

// define  constant for firestore database locations
final String tippersPath = dotenv.env['TIPPERS_PATH'] as String;
final String tokensPath = dotenv.env['TOKENS_PATH'] as String;

class TippersViewModel extends ChangeNotifier {
  List<Tipper> _tippers = [];

  Tipper? _selectedTipper;
  Tipper? get selectedTipper => _selectedTipper;

  // this setter is to support god mode, where the admin can select a tipper to act as
  set selectedTipper(Tipper? tipper) {
    _selectedTipper = tipper;
    notifyListeners();
  }

  // this will be the tipper that is logged in, it should not be changed
  Tipper? _authenticatedTipper;
  Tipper? get authenticatedTipper => _authenticatedTipper;

  bool get inGodMode => _selectedTipper!.dbkey != _authenticatedTipper!.dbkey;

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _tippersStream;

  bool _savingTipper = false;
  bool get savingTipper => _savingTipper;

  bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  double _tipperListScrollPosition = 0;
  double get tipperListScrollPosition => _tipperListScrollPosition;
  set tipperListScrollPosition(double value) {
    _tipperListScrollPosition = value;
    notifyListeners();
  }

  //

  final Completer<void> _initialLoadCompleter = Completer<void>();

  bool createLinkedTipper;

  //constructor
  TippersViewModel(this.createLinkedTipper) {
    log('TippersViewModel() constructor called');
    _listenToTippers();
  }

  void handleFirebaseServiceChange() {
    if (!kIsWeb) {
      registerLinkedTipperForMessaging();
    }
  }

  // monitor changes to tippers records in DB and notify listeners of any changes
  void _listenToTippers() {
    _tippersStream = _db.child(tippersPath).onValue.listen((event) {
      _handleEvent(event);
    });
    log('Tippers db Listener: Listening to tippers in database on path $tippersPath');
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

  Future<List<Tipper>> getAllTippers() async {
    await _initialLoadCompleter.future;
    return _tippers;
  }

  Future<List<Tipper>> getActiveTippers(DAUComp thisComp) async {
    await _initialLoadCompleter.future;
    // filter the _tipper list to only include tippers who have an daucomp in compsParticipatedIn list
    // that matched the current comp
    return _tippers
        .where((tipper) => tipper.activeInComp(thisComp.dbkey!))
        .toList();
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

    if (tipperToUpdate == null) {
      log('TipperToUpdate is null. Skipping update.');
      return;
    }

    // if the attribute name is deviceTokens store the token in another tree
    // this is to avoid the need to update the entire tipper record every time a new token is added
    // this is due to firebase billing

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

  Future<Tipper?> findTipperByLogon(String logon) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial tipper load to complete, findtipperbylogon($logon)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findtipperbylogon($logon)');
    }
    return _tippers.firstWhereOrNull((tipper) => tipper.logon == logon);
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
  Future<Tipper?> findTipper(String tipperDbKey) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial Tipper load to complete in findTipper($tipperDbKey)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findTipper($tipperDbKey)');
    }
    return _tippers.firstWhereOrNull((tipper) => tipper.dbkey == tipperDbKey);
  }

  //method to sync Tipper changes from Legacy GSheet Tipping Service Tipper sheet to Firebase
  // 1) input parameter is a list of Tippers from the Legacy GSheet Tipping Service
  // 2) compare each Tipper in the list to the Tippers in the Firebase database
  // 3) if the Tipper does not exist in the Firebase database, add it
  // 4) if the Tipper does exist in the Firebase database, update it
  // 5) if the Tipper exists in the Firebase database but not in the Legacy GSheet Tipping Service, delete it

  Future<String> syncTippers() async {
    try {
      _isLegacySyncing = true;
      notifyListeners();

      LegacyTippingService tippingService =
          GetIt.instance<LegacyTippingService>();

      List<Tipper> legacyTippers = [];

      await Future.wait([
        tippingService
            .getLegacyTippers(di<DAUCompsViewModel>().selectedDAUComp!)
            .then((tippers) => legacyTippers = tippers),
        _initialLoadCompleter.future,
      ]);

      log('syncTippers() legacy tipper sheet load complete');

      if (!_initialLoadCompleter.isCompleted) {
        log('Waiting for initial App Tipper load to complete in syncTippers()');
        await _initialLoadCompleter.future;
        log('App tipper load complete, syncTippers()');
      }

      // loop through each Tipper in the legacyTippers list - skip the header row
      await Future.forEach(legacyTippers.skip(1), (legacyTipper) async {
        // if the Tipper does not exist in the Firebase database, add it
        Tipper? existingTipper =
            await findTipperByLegayTipperID(legacyTipper.tipperID);
        if (existingTipper == null) {
          log('syncTippers() TipperID: ${legacyTipper.tipperID} for tipper ${legacyTipper.name} does not exist in the Firebase database, adding it');
          // newTipper() will create a new db key for the new record and return a modified Tipper object with the new db key
          await createNewTipper(legacyTipper);
        } else {
          log('syncTippers() TipperID: ${legacyTipper.tipperID} for tipper ${legacyTipper.name} exists in the Firebase database, updating it');

          // submit each attribute of the legacyTipper to the updateTipperAttribute method,
          // it will take care of only submitting the attributes that have changed to db
          await updateTipperAttribute(
              existingTipper.dbkey!, 'name', legacyTipper.name);
          await updateTipperAttribute(
              existingTipper.dbkey!, 'email', legacyTipper.email);
          await updateTipperAttribute(
              existingTipper.dbkey!, 'tipperID', legacyTipper.tipperID);
          await updateTipperAttribute(existingTipper.dbkey!, 'tipperRole',
              legacyTipper.tipperRole.name);

          // make the existing tipper logon be the same as email, only if it's null
          if (existingTipper.logon == null) {
            await updateTipperAttribute(
                existingTipper.dbkey!, 'logon', existingTipper.email);
          }

          //
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
        }
      }));
      return 'Successfully synced ${legacyTippers.length} tippers from the legacy tipping sheet';
    } finally {
      _isLegacySyncing = false;
      notifyListeners();
    }
  }

  Future<void> createNewTipper(
    Tipper newTipper,
  ) async {
    await _initialLoadCompleter.future;

    if (newTipper.dbkey == null) {
      log('Adding new Tipper record');
      // add new record to updates Map, create a new db key first
      DatabaseReference newTipperRecordKey = _db.child(tippersPath).push();
      newTipper.dbkey = newTipperRecordKey.key;
      updates['$tippersPath/${newTipper.dbkey}'] = newTipper.toJson();
    } else {
      throw 'newTipper() called with existing Tipper dbkey, should be an update';
    }
  }

  bool isValidEmail(String? email) {
    if (email == null) {
      return false;
    }

    final RegExp regex =
        RegExp(r'^[a-zA-Z0-9.a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$');

    return regex.hasMatch(email);
  }

  // method called at logon to find logged in Tipper and link it if required
  // first try finding the tipper based on authuid
  // if that fails, try finding the tipper based on email
  Future<bool> linkUserToTipper() async {
    Tipper? foundTipper;
    User authenticatedFirebaseUser = FirebaseAuth.instance.currentUser!;
    bool userIsLinked = false;

    try {
      // first try finding the tipper based on authuid
      foundTipper = await findTipperByUid(authenticatedFirebaseUser.uid);

      if (foundTipper != null) {
        log('linkUserToTipper() Tipper ${foundTipper.name} found using uid: ${authenticatedFirebaseUser.uid}');

        // make sure login email is up to date
        // update the authuid and logon in the database
        await updateTipperAttribute(
            foundTipper.dbkey!, "logon", authenticatedFirebaseUser.email);

        // check if tipper.email is a valid email address, if not make it the sane as logon
        if (!isValidEmail(foundTipper.email)) {
          await updateTipperAttribute(
              foundTipper.dbkey!, "email", authenticatedFirebaseUser.email);
        }

        await saveBatchOfTipperAttributes();
      } else {
        // if that fails, try finding the tipper based on logon email
        foundTipper ??=
            await findTipperByLogon(authenticatedFirebaseUser.email!);

        if (foundTipper != null) {
          log('linkUserToTipper() Tipper ${foundTipper.name} found using logon: ${authenticatedFirebaseUser.email}. Updating UID in database');

          await updateTipperAttribute(
              foundTipper.dbkey!, "authuid", authenticatedFirebaseUser.uid);

          // if email is null, update that to match logon
          if (foundTipper.email == null) {
            await updateTipperAttribute(
                foundTipper.dbkey!, "email", authenticatedFirebaseUser.email);
            await saveBatchOfTipperAttributes();
          }

          await saveBatchOfTipperAttributes();
        } else {
          // try finding using email address
          foundTipper =
              await findTipperByEmail(authenticatedFirebaseUser.email!);

          if (foundTipper != null) {
            log('linkUserToTipper() Tipper ${foundTipper.name} found using email: ${authenticatedFirebaseUser.email}');

            // update the authuid and logon in the database
            await updateTipperAttribute(
                foundTipper.dbkey!, "logon", authenticatedFirebaseUser.email);
            await updateTipperAttribute(
                foundTipper.dbkey!, "authuid", authenticatedFirebaseUser.uid);
            await saveBatchOfTipperAttributes();
          } else {
            log('getLoggedInTipper() Existing Tipper record not found for email: ${authenticatedFirebaseUser.email}. Try logging in with an email you provided for tipping or contact DAU support.');
          }
        }
      }
      if (foundTipper != null) {
        _authenticatedTipper = foundTipper;
        // for now the selected tipper is the same as the authenticated tipper
        // in god mode this can be changed
        _selectedTipper = foundTipper;
        userIsLinked = true;

        //update photoURL if it has changed
        if (foundTipper.photoURL != authenticatedFirebaseUser.photoURL) {
          await updateTipperAttribute(foundTipper.dbkey!, "photoURL",
              authenticatedFirebaseUser.photoURL);
          await saveBatchOfTipperAttributes();
        }

        if (!kIsWeb) {
          await registerLinkedTipperForMessaging();
        }

        //TODO init an instance of ScoresViewModel focusing on their scores here?
      } else {
        log('linkUserToTipper() Tipper not found for user ${authenticatedFirebaseUser.email}');

        if (createLinkedTipper == false) {
          log('linkUserToTipper() createLinkedTipper is false, not creating a new tipper');
          return false;
        }

        log('linkUserToTipper() createLinkedTipper is true, creating a new tipper for user ${authenticatedFirebaseUser.email}');

        // create them a tipper record
        Tipper newTipper = Tipper(
          name: authenticatedFirebaseUser.displayName ??
              authenticatedFirebaseUser.email!.split('@').first,
          email: authenticatedFirebaseUser.email!,
          authuid: authenticatedFirebaseUser.uid,
          photoURL: authenticatedFirebaseUser.photoURL,
          tipperRole: TipperRole.tipper,
          tipperID: 'non-legacy-tipper-${authenticatedFirebaseUser.uid}',
          compsParticipatedIn: [], // do not assign tippers created this way to any comps
        );

        await createNewTipper(newTipper);

        await saveBatchOfTipperAttributes();
        log('linkUserToTipper() Tipper ${newTipper.dbkey} created for user ${authenticatedFirebaseUser.email}');

        _authenticatedTipper = newTipper;
        _selectedTipper = newTipper;
        userIsLinked = true;
      }

      return userIsLinked;
    } catch (e) {
      log('linkUserToTipper() Error: $e');
      // rethow the error
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  // DeviceTokens are stored in another tree in db
  // this is to keep firebase billing low/nil
  Future<void> registerLinkedTipperForMessaging() async {
    // loop through any existing device tokens for this tipper, if the token
    // does not exist, add it, otherwise update the timestamp for the existing token
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial Tipper load to complete in registerLinkedTipperForMessaging()');
      await _initialLoadCompleter.future;
      log('tipper load complete, registerLinkedTipperForMessaging()');
    }

    // wait for the token to be populated
    FirebaseMessagingService? firebaseService = di<FirebaseMessagingService>();
    await firebaseService.initialLoadComplete;
    String? token = firebaseService.fbmToken;

    // write the token to the database using the token as the the path
    // update the timestamp if the token already exists

    if (token == null) {
      log('registerLinkedTipperForMessaging() Token is null, cannot register for messaging');
      return;
    }

    _db
        .child(tokensPath)
        .child(_authenticatedTipper!.dbkey!)
        .update({token: DateTime.now().toIso8601String()});

    log('registerLinkedTipperForMessaging() Tipper ${_authenticatedTipper!.name} registered for messaging with token ending in: ${token.substring(token.length - 5)}');
  }

  //this is the callback method when there are changes in the FBM token
  Future<void> updateFbmToken() async {
    await registerLinkedTipperForMessaging();
  }

  // method to delete acctount
  void deleteAccount() async {
    try {
      await FirebaseAuth.instance.currentUser!.delete();
    } catch (e) {
      if ((e as FirebaseAuthException).code == 'requires-recent-login') {
        // reauthenticate the user
        log('UserAuthPage.deleteAccount() - reauthenticating user');
        final String providerId =
            FirebaseAuth.instance.currentUser!.providerData[0].providerId;

        if (providerId == 'apple.com') {
          await _reauthenticateWithApple();
        } else if (providerId == 'google.com') {
          await _reauthenticateWithGoogle();
        }
      }

      await FirebaseAuth.instance.currentUser!.delete();
    }
  }

  Future<void> _reauthenticateWithApple() async {
    // If user is not authenticated
    if (FirebaseAuth.instance.currentUser == null) {
      throw 'Cannot reauthenticate with Apple the user is not authenticated';
    }

    final AppleAuthProvider appleProvider = AppleAuthProvider();

    // Try to reauthenticate
    try {
      await FirebaseAuth.instance.currentUser!
          .reauthenticateWithProvider(appleProvider);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-mismatch' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-verification-code' ||
          e.code == 'invalid-verification-id') {
        // Show a Snackbar
        log('UserAuthPage._reauthenticateWithApple() - error: ${e.code}');
      } else {
        rethrow;
      }
    }
  }

  Future<void> _reauthenticateWithGoogle() async {
    // If user is not authenticated
    if (FirebaseAuth.instance.currentUser == null) {
      throw 'Cannot reauthenticate with Google the user is not authenticated';
    }

    final GoogleAuthProvider googleProvider = GoogleAuthProvider();

    // Tries to reauthenticate
    await FirebaseAuth.instance.currentUser!
        .reauthenticateWithProvider(googleProvider);
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }

  Future<Tipper?> isEmailOrLogonAlreadyAssigned(
      String email1, String email2, Tipper? tipper) async {
    await _initialLoadCompleter.future;
    // if the tipper is supplied then we are checking if the email or logon is already assigned to another tipper
    // if the tipper is null then we are checking if the email or logon is already assigned to any tipper
    Tipper? foundTipper;
    if (tipper != null) {
      foundTipper = _tippers.firstWhereOrNull((otherTipper) =>
          (otherTipper.email == email1 ||
              otherTipper.email == email2 ||
              otherTipper.logon == email1 ||
              otherTipper.logon == email2) &&
          otherTipper.dbkey != tipper.dbkey);
    } else {
      foundTipper = _tippers.firstWhereOrNull((otherTipper) =>
          otherTipper.email == email1 ||
          otherTipper.email == email2 ||
          otherTipper.logon == email1 ||
          otherTipper.logon == email2);
    }
    return foundTipper;
  }
}

class Log {}
