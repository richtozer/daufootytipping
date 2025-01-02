import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
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

  final bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  double _tipperListScrollPosition = 0;
  double get tipperListScrollPosition => _tipperListScrollPosition;
  set tipperListScrollPosition(double value) {
    _tipperListScrollPosition = value;
    notifyListeners();
  }

  //

  final Completer<void> _initialLoadCompleter = Completer<void>();

  final Completer<void> _isUserLinked = Completer<void>();
  get isUserLinked => _isUserLinked.future;

  final bool _createLinkedTipper;

  //constructor
  TippersViewModel(this._createLinkedTipper) {
    log('TippersViewModel() constructor called');
    _listenToTippers();
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
      log('Tippers db Listener called');
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
    // that matched the supplied comp
    return _tippers.where((tipper) => tipper.activeInComp(thisComp)).toList();
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

    // the Tipper serialisation relies on daucompsviewmodel being ready
    // so we need to wait for it to be ready before we can update the tipper

    await di<DAUCompsViewModel>().initialLoadComplete;

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

  Future<Tipper?> _findTipperByUid(String authuid) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial tipper load to complete, findtipperbyuid($authuid)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findtipperbyuid($authuid)');
    }

    return _tippers.firstWhereOrNull((tipper) => tipper.authuid == authuid);
  }

  Future<Tipper?> _findTipperByEmail(String email) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial tipper load to complete, findtipperbyemail($email)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findtipperbyemail($email)');
    }
    return _tippers.firstWhereOrNull((tipper) => tipper.email == email);
  }

  Future<Tipper?> _findTipperByLogon(String logon) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for initial tipper load to complete, findtipperbylogon($logon)');
      await _initialLoadCompleter.future;
      log('tipper load complete, findtipperbylogon($logon)');
    }
    return _tippers.firstWhereOrNull((tipper) => tipper.logon == logon);
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

  Future<void> _createNewTipper(
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

  bool _isValidEmail(String? email) {
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
      foundTipper = await _findTipperByUid(authenticatedFirebaseUser.uid);

      if (foundTipper != null) {
        log('linkUserToTipper() Tipper ${foundTipper.name} found using uid: ${authenticatedFirebaseUser.uid}');

        // make sure login email is up to date
        // update the authuid and logon in the database
        await updateTipperAttribute(
            foundTipper.dbkey!, "logon", authenticatedFirebaseUser.email);

        // check if tipper.email is a valid email address, if not make it the sane as logon
        if (!_isValidEmail(foundTipper.email)) {
          await updateTipperAttribute(
              foundTipper.dbkey!, "email", authenticatedFirebaseUser.email);
        }

        await saveBatchOfTipperAttributes();
      } else {
        // if that fails, try finding the tipper based on logon email
        foundTipper ??=
            await _findTipperByLogon(authenticatedFirebaseUser.email!);

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
              await _findTipperByEmail(authenticatedFirebaseUser.email!);

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
        if (!_isUserLinked.isCompleted) {
          _isUserLinked.complete();
        }

        //update photoURL if it has changed
        if (foundTipper.photoURL != authenticatedFirebaseUser.photoURL) {
          await updateTipperAttribute(foundTipper.dbkey!, "photoURL",
              authenticatedFirebaseUser.photoURL);
          await saveBatchOfTipperAttributes();
        }

        if (!kIsWeb) {
          await _registerLinkedTipperForMessaging();
        }
      } else {
        log('linkUserToTipper() Tipper not found for user ${authenticatedFirebaseUser.email}');

        if (_createLinkedTipper == false) {
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

        await _createNewTipper(newTipper);

        await saveBatchOfTipperAttributes();
        log('linkUserToTipper() Tipper ${newTipper.dbkey} created for user ${authenticatedFirebaseUser.email}');

        _authenticatedTipper = newTipper;
        _selectedTipper = newTipper;
        userIsLinked = true;
        if (!_isUserLinked.isCompleted) {
          _isUserLinked.complete();
        }
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
  Future<void> _registerLinkedTipperForMessaging() async {
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
    String token = firebaseService.fbmToken ?? '';

    if (token.isEmpty) {
      log('registerLinkedTipperForMessaging() FBM token is empty, skipping registration');
      return;
    }
    String timeNow = DateTime.now().toIso8601String();

    _db
        .child(tokensPath)
        .child(_authenticatedTipper!.dbkey!)
        .update({token: timeNow});

    log('registerLinkedTipperForMessaging() Tipper ${_authenticatedTipper!.name} registered for messaging with token ending in: ${token.substring(token.length - 5)}');
  }

  //this is the callback method when there are changes in the FBM token
  // Future<void> _updateFbmToken() async {
  //   await _registerLinkedTipperForMessaging();
  // }

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
