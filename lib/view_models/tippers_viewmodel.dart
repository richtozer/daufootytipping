import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:daufootytipping/services/auth_aware_stream.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:dau_shared/services/identity_keys.dart' show normaliseAlias;

class TippersViewModel extends ChangeNotifier {
  List<Tipper> _tippers = [];
  List<Tipper> get tippers => _tippers;

  late Tipper _selectedTipper;
  Tipper get selectedTipper => _selectedTipper;

  Future<void> changeSelectedTipperAfterRefresh(
    Tipper tipper, {
    required Future<void> Function() refreshSelectedTipperViewModels,
  }) async {
    final previousTipper = _selectedTipper;
    _selectedTipper = tipper;

    try {
      await refreshSelectedTipperViewModels();
    } catch (_) {
      _selectedTipper = previousTipper;
      notifyListeners();
      rethrow;
    }

    notifyListeners();
  }

  // this will be the tipper that is logged in, it should not be changed
  Tipper? _authenticatedTipper;
  Tipper? get authenticatedTipper => _authenticatedTipper;

  bool get inGodMode => _selectedTipper.dbkey != _authenticatedTipper!.dbkey;

  // Lazily access database reference to avoid Firebase initialization in pure unit tests.
  DatabaseReference get _db => configuredDatabaseRef();

  late StreamSubscription<DatabaseEvent> _tippersStream;

  bool _savingTipper = false;
  bool get savingTipper => _savingTipper;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  final Completer<void> _isUserLinked = Completer<void>();
  Future<void> get isUserLinked => _isUserLinked.future;

  final bool _createLinkedTipper;

  /// Whether `AppConfig/createLinkedTipper` allows new tippers to be created. The
  /// server enforces it; this lets the sign-in screen say so instead of asking for
  /// an alias that would be refused.
  bool get canCreateTippers => _createLinkedTipper;

  final Map<String, dynamic> updates = {};

  //constructor
  TippersViewModel(this._createLinkedTipper, {bool skipInit = false}) {
    if (!skipInit) {
      _listenToTippers();
    }
  }

  // monitor changes to tippers records in DB and notify listeners of any changes.
  // The public tipper list needs a session under the R2 rules, so the listener opens
  // once a user is signed in (see authAwareStream), not when this view model is created.
  void _listenToTippers() {
    _tippersStream =
        authAwareStream<DatabaseEvent>(
          signedIn: firebaseSignedInStream,
          open: () => _db.child(p.tippersPath).onValue,
        ).listen((event) {
          _handleEvent(event);
        });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    await _applyTippersSnapshot(event.snapshot);
  }

  Future<void> _applyTippersSnapshot(DataSnapshot snapshot) async {
    final bool isFirstLoad = !_initialLoadCompleter.isCompleted;
    final Stopwatch processingStopwatch = Stopwatch()..start();
    final dynamic rawValue = snapshot.value;
    final int entryCount = rawValue is Map ? rawValue.length : 0;
    final int? payloadBytes = StartupProfiling.estimatePayloadBytes(rawValue);
    StartupProfiling.instant(
      'startup.tippers_snapshot_received',
      arguments: <String, Object?>{
        'exists': snapshot.exists,
        'entryCount': entryCount,
        'payloadBytes': payloadBytes ?? -1,
        'firstLoad': isFirstLoad,
      },
    );

    if (snapshot.exists) {
      List<Tipper?> tippersList = await Tipper.fromJsonList(
        snapshot.value,
        di<DAUCompsViewModel>().resolveCompsList,
      );

      _tippers = tippersList
          .where((tipper) => tipper != null)
          .cast<Tipper>()
          .toList();

      // do a default sort by login date
      _sortTippersByLogin(false);

      // Keep _authenticatedTipper and _selectedTipper in sync with the
      // fresh Tipper objects from the stream. Without this, these
      // references go stale after every Firebase update.
      _refreshAuthenticatedTipperReference();
    } else {
      log(
        'TippersViewModel() Tipper db Listener: No tippers found in database',
      );
    }
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }
    processingStopwatch.stop();
    StartupProfiling.instant(
      'startup.tippers_snapshot_processed',
      arguments: <String, Object?>{
        'elapsedMs': processingStopwatch.elapsedMilliseconds,
        'tippersCount': _tippers.length,
        'firstLoad': isFirstLoad,
      },
    );
    notifyListeners();
  }

  void _sortTippersByLogin(bool ascending) {
    var sortedEntries = _tippers.toList()
      ..sort(
        (a, b) =>
            (ascending ? 1 : -1) *
            (a.acctLoggedOnUTC ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  b.acctLoggedOnUTC ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
      );
    _tippers = sortedEntries;
  }

  /// Updates [_authenticatedTipper] and [_selectedTipper] to point at the
  /// matching objects in the freshly rebuilt [_tippers] list, so that
  /// fields like [compsPaidFor] stay current after Firebase stream updates.
  void _refreshAuthenticatedTipperReference() {
    if (_authenticatedTipper == null) return;
    final String? authDbKey = _authenticatedTipper!.dbkey;
    if (authDbKey == null) return;

    final Tipper? freshTipper = _tippers.firstWhereOrNull(
      (t) => t.dbkey == authDbKey,
    );
    if (freshTipper == null) return;

    final bool isInGodMode =
        _selectedTipper.dbkey != _authenticatedTipper!.dbkey;
    // The public list no longer carries the signed-in tipper's role, login or
    // account id: keep the ones the link established.
    final Tipper refreshed = freshTipper.withIdentityOf(_authenticatedTipper!);
    _authenticatedTipper = refreshed;
    if (!isInGodMode) {
      _selectedTipper = refreshed;
    }
  }

  // method to set or update tipper name. Make sure name is unique in the _tippers list, if not, throw an error
  // Save any changes to the database using updateTipperAttribute
  Future<void> setTipperName(String tipperDbKey, String? newName) async {
    if (!_initialLoadCompleter.isCompleted) {
      log(
        'TippersViewModel() Waiting for initial Tipper load to complete, setTipperName()',
      );
      await _initialLoadCompleter.future;
      log('TippersViewModel() tipper load complete, setTipperName()');
    }

    Tipper? tipperToUpdate = await findTipper(tipperDbKey);

    if (tipperToUpdate == null) {
      log('TippersViewModel() TipperToUpdate is null. Skipping update.');
      return;
    }

    if (tipperToUpdate.name == newName) {
      log('TippersViewModel() Tipper: $tipperDbKey already has name: $newName');
      return;
    }

    if (newName == null || newName.isEmpty) {
      throw 'Tipper name cannot be empty';
    }

    final normalisedNew = normaliseAlias(newName);
    if (_tippers.any(
      (tipper) => normaliseAlias(tipper.name) == normalisedNew,
    )) {
      throw 'Tipper name $newName is too similar to an existing alias.\n\nIf you were a tipper in previous years, then it may be that you have duplicate profiles. This is likely due to changing logon methods.\n\nPlease contact DAU Support to resolve this issue.';
    }

    await updateTipperAttribute(tipperDbKey, "name", newName);
    await saveBatchOfTipperChangesToDb();

    tipperToUpdate.name = newName;
    if (_authenticatedTipper?.dbkey == tipperDbKey) {
      _authenticatedTipper = tipperToUpdate;
    }
    if (_selectedTipper.dbkey == tipperDbKey) {
      _selectedTipper = tipperToUpdate;
    }
    notifyListeners();

    log('TippersViewModel() Tipper: $tipperDbKey name updated to: $newName');
  }

  Future<void> updateTipperAttribute(
    String tipperDbKey,
    String attributeName,
    dynamic attributeValue,
  ) async {
    if (!_initialLoadCompleter.isCompleted) {
      log(
        'TippersViewModel() Waiting for initial Tipper load to complete, updateTipperAttribute()',
      );
      await _initialLoadCompleter.future;
      log('TippersViewModel() tipper load complete, updateTipperAttribute()');
    }

    //find the Tipper in the local list. if it's there, compare the attribute value and update if different
    Tipper? tipperToUpdate = await findTipper(tipperDbKey);

    if (tipperToUpdate == null) {
      log('TippersViewModel() TipperToUpdate is null. Skipping update.');
      return;
    }

    // the Tipper serialization relies on daucompsviewmodel being ready
    // so we need to wait for it to be ready before we can update the tipper

    await di<DAUCompsViewModel>().initialDAUCompLoadComplete;

    dynamic oldValue = tipperToUpdate.toJson()[attributeName];
    if (attributeValue != oldValue) {
      log(
        'TippersViewModel() Tipper: $tipperDbKey needs update for attribute $attributeName: $attributeValue',
      );

      updates['${p.tippersPath}/$tipperDbKey/$attributeName'] = attributeValue;
    } else {
      log(
        'TippersViewModel() Tipper: $tipperDbKey already has $attributeName: $attributeValue',
      );
    }
  }

  /// Writes the pending tipper changes.
  ///
  /// The database only completes a write when the server acknowledges it, so a
  /// stalled connection leaves the caller waiting indefinitely. A caller that
  /// shows a busy indicator passes [acknowledgementLimit]: if the server has not
  /// answered by then, the write stays queued on the device and a
  /// [WriteNotConfirmedException] is thrown so the screen can say so. A write
  /// the server rejects still throws its own error.
  Future<void> saveBatchOfTipperChangesToDb({
    Duration? acknowledgementLimit,
  }) async {
    try {
      if (!_initialLoadCompleter.isCompleted) {
        log(
          'TippersViewModel() Waiting for initial Tipper load to complete, saveBatchOfTipperAttributes()',
        );
        await _initialLoadCompleter.future;
        log(
          'TippersViewModel() tipper load complete, saveBatchOfTipperAttributes()',
        );
      }
      final Map<String, Object?> changes = Map<String, Object?>.of(updates);
      final Future<void> write = AppResumeDiagnostics.trackWrite<void>(
        'tipper_update',
        () => _db.update(changes),
        details: <String, Object?>{'pathCount': changes.length},
      );
      if (acknowledgementLimit == null) {
        await write;
        return;
      }
      final WriteAcknowledgement acknowledgement = await awaitAcknowledgement(
        write,
        limit: acknowledgementLimit,
        onLateError: (Object error, StackTrace stackTrace) {
          log(
            'TippersViewModel() queued tipper update was rejected: $error',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
      if (acknowledgement == WriteAcknowledgement.stillPending) {
        throw const WriteNotConfirmedException('tipper update');
      }
    } finally {
      updates.clear();
      _savingTipper = false;
    }
  }

  /// The signed-in tipper, if [authuid] is the signed-in account. Other tippers'
  /// account ids are private under the R2 rules, so no one else can be found this
  /// way.
  Future<Tipper?> findTipperByUid(String authuid) async {
    final tipper = _authenticatedTipper;
    return tipper != null && tipper.authuid == authuid ? tipper : null;
  }

  // this function finds the provided Tipper dbKey in the _tipper list and returns it
  Future<Tipper?> findTipper(String tipperDbKey) async {
    if (!_initialLoadCompleter.isCompleted) {
      log(
        'TippersViewModel() Waiting for initial Tipper load to complete in findTipper($tipperDbKey)',
      );
      await _initialLoadCompleter.future;
      log('TippersViewModel() tipper load complete, findTipper($tipperDbKey)');
    }
    return _tippers.firstWhereOrNull((tipper) => tipper.dbkey == tipperDbKey);
  }

  Tipper _promoteToFreshTipperReference(Tipper tipper) {
    if (!_initialLoadCompleter.isCompleted || tipper.dbkey == null) {
      return tipper;
    }

    final Tipper? freshTipper = _tippers.firstWhereOrNull(
      (t) => t.dbkey == tipper.dbkey,
    );
    return freshTipper?.withIdentityOf(tipper) ?? tipper;
  }

  Future<void> _completeIsUserLinkedWhenReady({
    required bool awaitMessagingRegistration,
  }) async {
    if (_isUserLinked.isCompleted) {
      return;
    }

    if (_initialLoadCompleter.isCompleted) {
      _isUserLinked.complete();
      if (!kIsWeb) {
        if (awaitMessagingRegistration) {
          await _registerLinkedTipperForMessaging();
        } else {
          unawaited(_registerLinkedTipperForMessaging());
        }
      }
      return;
    }

    unawaited(
      _initialLoadCompleter.future.then((_) async {
        if (_isUserLinked.isCompleted) {
          return;
        }
        _isUserLinked.complete();
        if (!kIsWeb) {
          if (awaitMessagingRegistration) {
            await _registerLinkedTipperForMessaging();
          } else {
            unawaited(_registerLinkedTipperForMessaging());
          }
        }
      }),
    );
  }

  @visibleForTesting
  bool get isUserLinkedCompletedForTest => _isUserLinked.isCompleted;

  @visibleForTesting
  void setLinkedTippersForTest(Tipper tipper) {
    _authenticatedTipper = tipper;
    _selectedTipper = tipper;
  }

  @visibleForTesting
  Future<void> completeIsUserLinkedWhenReadyForTest({
    required bool awaitMessagingRegistration,
  }) {
    return _completeIsUserLinkedWhenReady(
      awaitMessagingRegistration: awaitMessagingRegistration,
    );
  }

  @visibleForTesting
  void applyTippersSnapshotForTest(List<Tipper> tippers) {
    _tippers = List<Tipper>.from(tippers);
    _sortTippersByLogin(false);
    _refreshAuthenticatedTipperReference();
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }
    notifyListeners();
  }

  Future<void> refreshFromServer() async {
    await _applyTippersSnapshot(await _db.child(p.tippersPath).get());
  }

  /// Sets the authenticated tipper immediately after lookup, before the
  /// background DB metadata update completes, so the UI can navigate to
  /// [HomePage] without blocking on Firebase writes.
  ///
  /// When [tipper] is a cached copy (empty [compsPaidFor]) but the
  /// Firebase stream has already populated [_tippers], this method
  /// promotes to the fresh object so downstream consumers see full data.
  ///
  /// The sign-in page calls this whenever it rebuilds, so a call for the
  /// tipper already signed in keeps any god mode selection.
  void setAuthenticatedTipper(Tipper tipper) {
    tipper = _promoteToFreshTipperReference(tipper);
    final bool keepGodModeSelection =
        _authenticatedTipper != null &&
        _authenticatedTipper?.dbkey == tipper.dbkey &&
        inGodMode;
    _authenticatedTipper = tipper;
    if (!keepGodModeSelection) {
      _selectedTipper = tipper;
    }
    // Cached tipper with empty compsPaidFor should not unblock stats until
    // the Firebase tippers stream has populated fresh references.
    unawaited(
      _completeIsUserLinkedWhenReady(awaitMessagingRegistration: false),
    );
    notifyListeners();
  }

  /// Keeps the signed-in tipper's photo in step with their account's. A tipper
  /// writes only their own photo; a guest has no record to write to. Failure is
  /// logged and ignored: a stale photo is not worth interrupting anyone for.
  Future<void> updateOwnPhoto(String? photoUrl) async {
    final tipper = _authenticatedTipper;
    if (tipper == null ||
        tipper.dbkey == null ||
        tipper.isAnonymous ||
        photoUrl == null ||
        photoUrl.isEmpty ||
        tipper.photoURL == photoUrl) {
      return;
    }
    try {
      await _db
          .child('${p.tippersPath}/${tipper.dbkey}/photoURL')
          .set(photoUrl);
    } on Object catch (error) {
      log('TippersViewModel().updateOwnPhoto() failed: $error');
    }
  }

  // mergeTipper method to merge two tippers into one. This is used when a user logs in with a different account
  // to the one in the the legacy tipping service.
  //
  // inputs are original tipper and target tipper. There are 2 bool flags:
  // mergeLogon - if true, the logon of the original tipper will be copied to the target tipper
  // mergeTips - if true, the tips of the original tipper will be copied to the target tipper
  Future<void> mergeTippers(
    Tipper originalTipper,
    Tipper targetTipper,
    bool mergeLogon,
    bool mergeTips, {
    bool trialMode = false,
  }) async {
    if (!_initialLoadCompleter.isCompleted) {
      log(
        'TippersViewModel().Waiting for initial Tipper load to complete in mergeTippers()',
      );
      await _initialLoadCompleter.future;
      log('TippersViewModel().tipper load complete, mergeTippers()');
    }

    try {
      List<DAUComp> comps = await di<DAUCompsViewModel>().getDAUcomps();
      int totalTipsMerged = 0;

      // loop through all comps
      for (DAUComp dauComp in comps) {
        if (mergeTips) {
          int tipsMerged = await mergeTipsForComp(
            originalTipper,
            targetTipper,
            dauComp,
            trialMode: trialMode,
          );
          totalTipsMerged += tipsMerged;
        }
      }

      if (trialMode) {
        log(
          'TippersViewModel() Trial mode: $totalTipsMerged tips would be merged',
        );
        return;
      }

      if (mergeLogon) {
        // update the email of the target tipper to the email of the original tipper
        await updateTipperAttribute(
          targetTipper.dbkey!,
          "logon",
          originalTipper.logon,
        );
        await saveBatchOfTipperChangesToDb();
        log(
          'TippersViewModel() Tipper ${targetTipper.name} logon updated to ${originalTipper.logon}',
        );
      }

      // now delete source tipper
      await _db.child(p.tippersPath).child(originalTipper.dbkey!).remove();
      log('TippersViewModel() Tipper ${originalTipper.name} deleted');

      // copy over the uid
      await updateTipperAttribute(
        targetTipper.dbkey!,
        "authuid",
        originalTipper.authuid,
      ); // update the authuid of the target tipper
      await saveBatchOfTipperChangesToDb();
      log(
        'TippersViewModel() Tipper ${targetTipper.name} authuid updated to ${originalTipper.authuid}',
      );
    } catch (e) {
      log('TippersViewModel().mergeTippers() Error: $e');
      rethrow;
    }
  }

  Future<int> mergeTipsForComp(
    Tipper originalTipper,
    Tipper targetTipper,
    DAUComp dauComp, {
    bool trialMode = false,
  }) async {
    // Init GamesViewModel
    GamesViewModel gamesViewModel = GamesViewModel(
      dauComp,
      di<DAUCompsViewModel>(),
    );
    // get the tips for this comp
    TipsViewModel allTips = TipsViewModel(
      di<TippersViewModel>(),
      dauComp,
      gamesViewModel,
    );

    // wait for the tips to be loaded
    await allTips.initialLoadCompleted;

    log('TippersViewModel() Merging tips in comp ${dauComp.name}');
    // call the getTipsForTipper method to get the list of tips for the original tipper
    List<Tip?> originalTips = allTips.getTipsForTipper(originalTipper);

    if (trialMode) {
      // Return the number of tips that would be merged
      return originalTips.length;
    } else {
      // loop through the list of tips (if any) and update the tipper dbkey to the target tipper dbkey
      await Future.forEach(originalTips, (Tip? tip) async {
        if (tip != null) {
          tip.tipper = targetTipper;
          await allTips.updateTip(tip);
          log(
            'TippersViewModel() Tip ${tip.dbkey} updated to tipper ${targetTipper.dbkey}',
          );
        }
      });
      // delete the tips for the original tipper by deleting the tipper dbkey
      await allTips.deleteAllTipsForTipper(originalTipper);
      log(
        'TippersViewModel() All tips for tipper ${originalTipper.dbkey} deleted',
      );
      return originalTips.length;
    }
  }

  // DeviceTokens are stored in another tree in db
  // this is to keep firebase billing low/nil
  Future<void> _registerLinkedTipperForMessaging() async {
    // loop through any existing device tokens for this tipper, if the token
    // does not exist, add it, otherwise update the timestamp for the existing token
    if (!_initialLoadCompleter.isCompleted) {
      log(
        'TippersViewModel()._registerLinkedTipperForMessaging() Waiting for initial Tipper load to complete',
      );
      await _initialLoadCompleter.future;
      log(
        'TippersViewModel()._registerLinkedTipperForMessaging() tipper load complete.',
      );
    }

    // wait for the token to be populated
    FirebaseMessagingService firebaseService = di<FirebaseMessagingService>();
    await firebaseService.initialLoadComplete;

    await firebaseService.registerTokenForTipper(_authenticatedTipper!);

    log(
      'TippersViewModel().registerLinkedTipperForMessaging() Tipper ${_authenticatedTipper!.name} registered for messaging with token ending in: ${firebaseService.fbmToken?.substring(firebaseService.fbmToken!.length - 5)}',
    );
  }

  // method to delete account
  Future<String?> deleteAccount() async {
    try {
      await FirebaseAuth.instance.currentUser!.delete();
      await _unregisterDeletedAccountToken();
      return null; // Success
    } catch (e) {
      if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
        // reauthenticate the user
        log('TippersViewModel().deleteAccount() - re-authenticating user');
        final String providerId =
            FirebaseAuth.instance.currentUser!.providerData[0].providerId;

        try {
          if (providerId == 'apple.com') {
            await _reauthenticateWithApple();
          } else if (providerId == 'google.com') {
            await _reauthenticateWithGoogle();
          }

          // Retry account deletion after successful re-authentication
          await FirebaseAuth.instance.currentUser!.delete();
          await _unregisterDeletedAccountToken();
          return null; // Success
        } catch (reauthError) {
          log(
            'TippersViewModel().deleteAccount() - re-authentication failed: $reauthError',
          );
          return 'Re-authentication failed. Please try again.';
        }
      } else {
        log('TippersViewModel().deleteAccount() - error: $e');
        return 'Account deletion failed. Please try again.';
      }
    }
  }

  Future<void> _unregisterDeletedAccountToken() async {
    if (!di.isRegistered<FirebaseMessagingService>()) {
      return;
    }
    await di<FirebaseMessagingService>().unregisterCurrentToken(
      tipperId: _authenticatedTipper?.dbkey,
    );
  }

  Future<void> _reauthenticateWithApple() async {
    // If user is not authenticated
    if (FirebaseAuth.instance.currentUser == null) {
      throw 'Cannot reauthenticate with Apple the user is not authenticated';
    }

    final AppleAuthProvider appleProvider = AppleAuthProvider();

    // Try to reauthenticate
    try {
      await FirebaseAuth.instance.currentUser!.reauthenticateWithProvider(
        appleProvider,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-mismatch' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-verification-code' ||
          e.code == 'invalid-verification-id') {
        // Log the error
        log('TippersViewModel()_reauthenticateWithApple() - error: ${e.code}');
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
    try {
      await FirebaseAuth.instance.currentUser!.reauthenticateWithProvider(
        googleProvider,
      );
    } on FirebaseAuthException catch (e) {
      log('TippersViewModel()_reauthenticateWithGoogle() - error: ${e.code}');
      rethrow;
    }
  }

  Future<Tipper?> isEmailOrLogonAlreadyAssigned(
    String email1,
    String email2,
    Tipper? tipper,
  ) async {
    await _initialLoadCompleter.future;
    // if the tipper is supplied then we are checking if the email or logon is already assigned to another tipper
    // if the tipper is null then we are checking if the email or logon is already assigned to any tipper
    Tipper? foundTipper;
    if (tipper != null) {
      foundTipper = _tippers.firstWhereOrNull(
        (otherTipper) =>
            (otherTipper.email == email1 ||
                otherTipper.email == email2 ||
                otherTipper.logon == email1 ||
                otherTipper.logon == email2) &&
            otherTipper.dbkey != tipper.dbkey,
      );
    } else {
      foundTipper = _tippers.firstWhereOrNull(
        (otherTipper) =>
            otherTipper.email == email1 ||
            otherTipper.email == email2 ||
            otherTipper.logon == email1 ||
            otherTipper.logon == email2,
      );
    }
    return foundTipper;
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }

  Future<void> setTipperEmail(String tipperDbKey, String? newEmail) async {
    if (!_initialLoadCompleter.isCompleted) {
      log(
        'TippersViewModel() Waiting for initial Tipper load to complete, setTipperName()',
      );
      await _initialLoadCompleter.future;
      log('TippersViewModel() tipper load complete, setTipperName()');
    }

    Tipper? tipperToUpdate = await findTipper(tipperDbKey);

    if (tipperToUpdate == null) {
      log('TippersViewModel() TipperToUpdate is null. Skipping update.');
      return;
    }

    if (tipperToUpdate.email == newEmail) {
      log('Tipper: $tipperDbKey already has email: $newEmail');
      return;
    }

    if (newEmail == null || newEmail.isEmpty) {
      throw 'Tipper email cannot be empty';
    }

    if (_tippers.any(
      (tipper) => (tipper.email ?? '').toLowerCase() == newEmail.toLowerCase(),
    )) {
      throw 'Tipper email $newEmail already exists';
    }

    await updateTipperAttribute(tipperDbKey, "email", newEmail);
    await saveBatchOfTipperChangesToDb();

    notifyListeners();

    log('TippersViewModel() Tipper: $tipperDbKey email updated to: $newEmail');
  }
}
