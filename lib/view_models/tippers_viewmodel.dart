import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/account_deletion.dart';
import 'package:daufootytipping/services/auth_aware_stream.dart';
import 'package:daufootytipping/services/firebase_deletable_account.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class TippersViewModel extends ChangeNotifier {
  List<Tipper> _tippers = [];
  List<Tipper> get tippers => _tippers;

  /// The public tipper list as read, before an administrator's private records
  /// are laid over it. [_tippers] is always rebuilt from this.
  List<Tipper> _publicTippers = [];

  /// Every tipper's private record, read only while the signed-in tipper is an
  /// administrator (nobody else may). The admin screens need each tipper's login,
  /// email, role and last login, which the public list no longer carries.
  Map<String, Map<String, dynamic>> _adminPrivateRecords = {};
  StreamSubscription<DatabaseEvent>? _adminPrivateStream;

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
  DatabaseReference get _db => _database ?? configuredDatabaseRef();

  final DatabaseReference? _database;
  final Stream<bool> Function() _signedIn;

  StreamSubscription<DatabaseEvent>? _tippersStream;

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
  TippersViewModel(
    this._createLinkedTipper, {
    bool skipInit = false,
    DatabaseReference? database,
    Stream<bool> Function()? signedIn,
  }) : _database = database,
       _signedIn = signedIn ?? firebaseSignedInStream {
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
          signedIn: _signedIn,
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

      _publicTippers = tippersList
          .where((tipper) => tipper != null)
          .cast<Tipper>()
          .toList();

      // lay an administrator's private records over it, and sort by login date
      _rebuildTippers();

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

  /// The working list: the public list, with each tipper's private record laid
  /// over it where an administrator has read them, most recent login first.
  void _rebuildTippers() {
    _tippers = <Tipper>[
      for (final Tipper tipper in _publicTippers) _withPrivateRecord(tipper),
    ];
    _sortTippersByLogin(false);
  }

  Tipper _withPrivateRecord(Tipper tipper) {
    final String? key = tipper.dbkey;
    final Map<String, dynamic>? record = key == null
        ? null
        : _adminPrivateRecords[key];
    if (record == null) {
      return tipper;
    }
    try {
      return tipper.withPrivateRecord(record);
    } on Object catch (error) {
      log('TippersViewModel() ignoring an unreadable private record: $error');
      return tipper;
    }
  }

  /// An administrator reads every private record, so that the admin screens can
  /// show and check logins, emails and roles. Anyone else does not listen (the
  /// rules would refuse), and what an administrator read is dropped as soon as
  /// the signed-in tipper is no longer one. Called whenever that may have changed.
  void _syncAdminPrivateListener() {
    final Tipper? signedIn = _authenticatedTipper;
    final bool isAdmin =
        signedIn != null &&
        !signedIn.isAnonymous &&
        signedIn.tipperRole == TipperRole.admin;
    if (!isAdmin) {
      unawaited(_adminPrivateStream?.cancel());
      _adminPrivateStream = null;
      if (_adminPrivateRecords.isNotEmpty) {
        _adminPrivateRecords = {};
        _rebuildTippers();
        _refreshAuthenticatedTipperReference();
      }
      return;
    }
    _adminPrivateStream ??= authAwareStream<DatabaseEvent>(
      signedIn: _signedIn,
      open: () => _db.child(p.tipperPrivatePath).onValue,
      onSourceError: (Object error, StackTrace stackTrace) => log(
        'TippersViewModel() cannot read the private tipper records: $error',
      ),
    ).listen(_applyAdminPrivateSnapshot);
  }

  void _applyAdminPrivateSnapshot(DatabaseEvent event) {
    final Object? value = event.snapshot.exists ? event.snapshot.value : null;
    _adminPrivateRecords = <String, Map<String, dynamic>>{
      if (value is Map)
        for (final MapEntry<Object?, Object?> entry in value.entries)
          if (entry.value is Map)
            entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
    };
    _rebuildTippers();
    _refreshAuthenticatedTipperReference();
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

  /// The server has changed the signed-in tipper's alias to [alias] (the
  /// `update-tipper-alias` callable has answered). Shows it at once, on the
  /// public record and on the signed-in copy that carries the private fields,
  /// rather than when the tippers stream next delivers it.
  void applyOwnAlias(String tipperDbKey, String alias) {
    final Tipper? listed = _tippers.firstWhereOrNull(
      (tipper) => tipper.dbkey == tipperDbKey,
    );
    final Tipper? signedIn = _authenticatedTipper?.dbkey == tipperDbKey
        ? _authenticatedTipper
        : null;
    final Tipper? selected = _selectedTipper.dbkey == tipperDbKey
        ? _selectedTipper
        : null;
    for (final Tipper? tipper in <Tipper?>[listed, signedIn, selected]) {
      tipper?.name = alias;
    }
    notifyListeners();
    log('TippersViewModel() Tipper: $tipperDbKey alias is now: $alias');
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
      final Future<void> write = _db.update(changes);
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
  void syncAdminPrivateListenerForTest() => _syncAdminPrivateListener();

  @visibleForTesting
  void applyTippersSnapshotForTest(List<Tipper> tippers) {
    _publicTippers = List<Tipper>.from(tippers);
    _rebuildTippers();
    _refreshAuthenticatedTipperReference();
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }
    notifyListeners();
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
    _syncAdminPrivateListener();
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

    await firebaseService.registerCurrentToken();

    log(
      'TippersViewModel().registerLinkedTipperForMessaging() Tipper ${_authenticatedTipper!.name} registered for messaging with token ending in: ${firebaseService.fbmToken?.substring(firebaseService.fbmToken!.length - 5)}',
    );
  }

  /// Deletes the signed-in person's account: signs in again if the sign-in is
  /// old, removes this device's push token, unlinks the tipper record from the
  /// account, then deletes the sign-in account. Null on success, otherwise what to
  /// tell the person. Safe to run again after a failure.
  Future<String?> deleteAccount() => AccountDeletion(
    identity: di<IdentityService>(),
    account: FirebaseDeletableAccount(),
    unregisterPushToken: _unregisterDeletedAccountToken,
  ).run();

  Future<void> _unregisterDeletedAccountToken() async {
    if (!di.isRegistered<FirebaseMessagingService>()) {
      return;
    }
    await di<FirebaseMessagingService>().unregisterCurrentToken();
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
    unawaited(_tippersStream?.cancel()); // stop listening to stream
    unawaited(_adminPrivateStream?.cancel());
    super.dispose();
  }
}
