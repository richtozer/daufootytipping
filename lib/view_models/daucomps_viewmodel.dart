import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/ladder_calculation_service.dart'; // Added import
import 'package:daufootytipping/models/league_ladder.dart'; // Added import
import 'package:daufootytipping/services/combined_rounds_service.dart';
import 'package:daufootytipping/services/daucomps_rounds_parser.dart';
import 'package:daufootytipping/services/combined_rounds_persistence.dart';
import 'package:daufootytipping/services/fixture_update_policy.dart';
import 'package:daufootytipping/services/lock_manager.dart';
import 'package:daufootytipping/services/timer_scheduler.dart';
import 'package:daufootytipping/services/url_health_checker.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';

const daucompsPath = '/AllDAUComps';
const combinedRoundsPath = 'combinedRounds2';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];
  List<DAUComp> get daucomps => _daucomps;
  final fixtureUpdateTimerDuration = Duration(
    hours: 24,
  ); // how often we check for fixture updates

  // Lazily access database reference to avoid Firebase initialization during pure unit tests
  DatabaseReference get _db => FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _daucompsStream;

  final String?
  _initDAUCompDbKey; // this is the comp to init with. typically the active comp, but can be any comp when in admin mode
  String? get initDAUCompDbKey => _initDAUCompDbKey;

  DAUComp? _activeDAUComp;
  DAUComp? get activeDAUComp =>
      _activeDAUComp; // this is the comp flagged by admins in the daucomp list as the active comp

  DAUComp? _selectedDAUComp;
  DAUComp? get selectedDAUComp =>
      _selectedDAUComp; // this is the comp that folks are currently viewing

  bool _savingDAUComp = false;
  bool get savingDAUComp => _savingDAUComp;

  final Completer<void> _initialDAUCompLoadCompleter = Completer<void>();
  Future<void> get initialDAUCompLoadComplete =>
      _initialDAUCompLoadCompleter.future;

  final Completer<void> _otherViewModels = Completer<void>();
  Future<void> get otherViewModelsLoadComplete => _otherViewModels.future;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  final bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  GamesViewModel? gamesViewModel;
  StatsViewModel? statsViewModel;
  TipsViewModel? selectedTipperTipsViewModel;

  final Map<String, dynamic> updates = {};
  final bool _adminMode;
  bool get adminMode => _adminMode;

  Timer? _dailyTimer;

  List<Game> unassignedGames = []; // List to store unassigned games
  final Map<League, LeagueLadder> _cachedLadders = {}; // Added cache storage
  final DaucompsRoundsParser _roundsParser = const DaucompsRoundsParser();
  final CombinedRoundsPersistence _roundsPersistence = const CombinedRoundsPersistence();
  final FixtureUpdatePolicy _fixturePolicy = const FixtureUpdatePolicy();
  final LockManager _lockManager = const LockManager();
  final TimerScheduler _timerScheduler = const TimerSchedulerDefault();
  final UrlHealthChecker _urlHealthChecker = UrlHealthChecker();

  DAUCompsViewModel(this._initDAUCompDbKey, this._adminMode, {bool skipInit = false}) {
    log(
      'DAUCompsViewModel() created with comp: $_initDAUCompDbKey, adminMode: $_adminMode',
    );
    if (!skipInit) {
      _init();
    }
  }

  // --- Testability additions ---
  @visibleForTesting
  void setSelectedCompForTest(DAUComp comp) {
    _selectedDAUComp = comp;
  }

  @visibleForTesting
  void completeOtherViewModelsForTest() {
    if (!_otherViewModels.isCompleted) {
      _otherViewModels.complete();
    }
  }
  // --- End Testability additions ---

  Future<void> _init() async {
    _listenToDAUComps();
    await initialDAUCompLoadComplete;

    if (_initDAUCompDbKey != null) {
      DAUComp? foundComp = await findComp(_initDAUCompDbKey);
      if (foundComp != null) {
        _activeDAUComp = foundComp;
        await changeDisplayedDAUComp(foundComp, false);
      }
    } else {
      if (!adminMode) {
        // if no comp is set as the active comp then we will default to the first comp in the list
        _activeDAUComp = _daucomps.first;
        if (_activeDAUComp != null) {
          await changeDisplayedDAUComp(_daucomps.first, false);
        } else {
          log(
            'No DAUComps found. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.',
          );
        }
      } else {
        log('In admin mode');
      }
    }

    _startDailyTimer();
  }

  void _startDailyTimer() {
    final role = di<TippersViewModel>().authenticatedTipper?.tipperRole;
    final shouldStart = _fixturePolicy.shouldStartDailyTimer(
      isWeb: kIsWeb,
      isAdminMode: _adminMode,
      authenticatedRole: role,
    );
    if (!shouldStart) {
      log('DAUCompsViewModel_startDailyTimer() Daily timer not started due to policy.');
      return;
    }
    _dailyTimer = _timerScheduler.schedulePeriodic(fixtureUpdateTimerDuration, (timer) {
      triggerDailyEvent();
    });

    // always trigger the daily event when the timer is started
    triggerDailyEvent();
  }

  void triggerDailyEvent() async {
    log(
      "DAUCompsViewModel_triggerDailyEvent()  Daily event triggered at ${DateTime.now()}",
    );
    // make sure we are using the current database state for this comp
    _activeDAUComp = await findComp(_activeDAUComp!.dbkey!);
    final shouldTrigger = _fixturePolicy.shouldTriggerFixtureUpdate(
      activeComp: _activeDAUComp,
      now: DateTime.now(),
      threshold: fixtureUpdateTimerDuration,
    );
    if (shouldTrigger) {
      log('DAUCompsViewModel_triggerDailyEvent()  Triggering fixture update');
      _fixtureUpdate();
    } else {
      log(
        'DAUCompsViewModel_triggerDailyEvent() Looks like another client did an update in the last ${fixtureUpdateTimerDuration.inHours} hours. Skipping fixture update.',
      );
    }
  }

  Future<void> changeDisplayedDAUComp(
    DAUComp? changeToDAUComp,
    bool changingActiveComp,
  ) async {
    _selectedDAUComp = changeToDAUComp;

    if (changingActiveComp) {
      _activeDAUComp = _selectedDAUComp;
    }

    await _initializeAndResetViewModels(_adminMode);
    notifyListeners();
  }

  Future<void> selectedTipperChanged() async {
    await _initializeAndResetViewModels(false);
    notifyListeners();
  }

  bool isSelectedCompActiveComp() {
    return _selectedDAUComp == _activeDAUComp;
  }

  Future<void> _initializeAndResetViewModels(bool adminDAUCompMode) async {
    if (di<DAUCompsViewModel>()._selectedDAUComp == null) {
      log(
        'Cannot determine current DAUComp. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.',
      );
      return;
    }

    if (!adminDAUCompMode) {
      await _initializeUserViewModels();
    } else {
      await _initializeAdminViewModels();
    }
    // mark completed
    if (!_otherViewModels.isCompleted) {
      _otherViewModels.complete();
    }
  }

  Future<void> _initializeUserViewModels() async {
    await initialDAUCompLoadComplete;

    gamesViewModel = GamesViewModel(_selectedDAUComp!, this);

    //await the TippersViewModel to be initialized
    await di<TippersViewModel>().initialLoadComplete;

    await di<TippersViewModel>().isUserLinked;

    if (di.isRegistered<StatsViewModel>()) {
      di.unregister<StatsViewModel>();
    }
    di.registerSingleton<StatsViewModel>(
      StatsViewModel(_selectedDAUComp!, gamesViewModel!),
    );
    statsViewModel = di<StatsViewModel>();

    gamesViewModel!.addListener(_otherViewModelUpdated);
    statsViewModel!.addListener(_otherViewModelUpdated);

    selectedTipperTipsViewModel = TipsViewModel.forTipper(
      di<TippersViewModel>(),
      _selectedDAUComp!,
      gamesViewModel!,
      di<TippersViewModel>().selectedTipper,
    );
    selectedTipperTipsViewModel!.addListener(_otherViewModelUpdated);
  }

  Future<void> _initializeAdminViewModels() async {
    gamesViewModel = GamesViewModel(_selectedDAUComp!, this);

    if (di.isRegistered<StatsViewModel>()) {
      di.unregister<StatsViewModel>();
    }
    di.registerSingleton<StatsViewModel>(
      StatsViewModel(_selectedDAUComp!, gamesViewModel!),
    );
    statsViewModel = di<StatsViewModel>();

    gamesViewModel!.addListener(_otherViewModelUpdated);
    statsViewModel!.addListener(_otherViewModelUpdated);
  }

  void _listenToDAUComps() {
    _daucompsStream = _db.child(daucompsPath).onValue.listen(_handleEvent);
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('DAUCompsViewModel_handleEvent()');
      if (event.snapshot.exists) {
        await _processSnapshot(event.snapshot);
      } else {
        log('No DAUComps found at database location: $daucompsPath');
        _daucomps = [];
      }

      if (!_initialDAUCompLoadCompleter.isCompleted) {
        _initialDAUCompLoadCompleter.complete();
      }

      notifyListeners();
    } catch (e) {
      log('Error listening to $daucompsPath: $e');
      rethrow;
    }
  }

  Future<void> _processSnapshot(DataSnapshot snapshot) async {
    final databaseDAUComps = Map<String, dynamic>.from(
      snapshot.value as dynamic,
    );

    // Create a map of existing comps for quick lookup
    Map<String, DAUComp> existingDAUCompsMap = {
      for (var daucomp in _daucomps) daucomp.dbkey!: daucomp,
    };

    // Track which database comps we've processed
    Set<String> processedDbKeys = <String>{};

    // Process each comp from database
    for (var entry in databaseDAUComps.entries) {
      String dbKey = entry.key;
      dynamic daucompAsJSON = entry.value;
      processedDbKeys.add(dbKey);

      if (existingDAUCompsMap.containsKey(dbKey)) {
        // Update existing comp incrementally
        DAUComp? replacementComp = await _updateExistingComp(
          existingDAUCompsMap[dbKey]!,
          daucompAsJSON,
        );
        if (replacementComp != null) {
          // Replace the existing comp with the new one (final fields changed)
          existingDAUCompsMap[dbKey] = replacementComp;
          log('Replaced DAUComp object due to final field changes: $dbKey');

          // Update references if needed
          if (dbKey == _activeDAUComp?.dbkey) {
            _activeDAUComp = replacementComp;
          }
          if (dbKey == _selectedDAUComp?.dbkey) {
            _selectedDAUComp = replacementComp;
            await linkGamesWithRounds(_selectedDAUComp!.daurounds);
          }
        }
      } else {
        // Add new comp
        await _addNewComp(dbKey, daucompAsJSON, existingDAUCompsMap);
      }
    }

    // Remove comps that are no longer in database
    List<String> keysToRemove = existingDAUCompsMap.keys
        .where((key) => !processedDbKeys.contains(key))
        .toList();

    for (String keyToRemove in keysToRemove) {
      existingDAUCompsMap.remove(keyToRemove);
      log('Removed DAUComp from memory: $keyToRemove');
    }

    _daucomps = existingDAUCompsMap.values.toList();
  }

  Future<DAUComp?> _updateExistingComp(
    DAUComp existingComp,
    dynamic daucompAsJSON,
  ) async {
    // Create a temporary DAUComp from database data for comparison
    List<DAURound> databaseRounds = _roundsParser.parseRounds(daucompAsJSON, combinedRoundsPath: combinedRoundsPath);
    DAUComp databaseComp = DAUComp.fromJson(
      Map<String, dynamic>.from(daucompAsJSON),
      existingComp.dbkey!,
      databaseRounds,
    );

    // Apply cutoff filter to database rounds
    _roundsParser.applyCutoffFilter(databaseComp);

    bool finalFieldsChanged = false;
    bool mutableFieldsChanged = false;

    // Check if final fields have changed (these require object replacement)
    if (existingComp.name != databaseComp.name ||
        existingComp.aflFixtureJsonURL != databaseComp.aflFixtureJsonURL ||
        existingComp.nrlFixtureJsonURL != databaseComp.nrlFixtureJsonURL) {
      finalFieldsChanged = true;
    }

    // If final fields changed, we need to replace the entire object
    if (finalFieldsChanged) {
      log(
        'Final fields changed for DAUComp ${existingComp.dbkey}, replacing object',
      );
      return databaseComp; // Return the new object to replace the existing one
    }

    // Update mutable fields
    if (existingComp.aflRegularCompEndDateUTC !=
        databaseComp.aflRegularCompEndDateUTC) {
      existingComp.aflRegularCompEndDateUTC =
          databaseComp.aflRegularCompEndDateUTC;
      mutableFieldsChanged = true;
    }
    if (existingComp.nrlRegularCompEndDateUTC !=
        databaseComp.nrlRegularCompEndDateUTC) {
      existingComp.nrlRegularCompEndDateUTC =
          databaseComp.nrlRegularCompEndDateUTC;
      mutableFieldsChanged = true;
    }
    if (existingComp.lastFixtureUpdateTimestampUTC !=
        databaseComp.lastFixtureUpdateTimestampUTC) {
      existingComp.lastFixtureUpdateTimestampUTC =
          databaseComp.lastFixtureUpdateTimestampUTC;
      mutableFieldsChanged = true;
    }

    // Update rounds using CRUD operations
    bool roundsChanged = await _updateDauRounds(
      existingComp,
      databaseComp.daurounds,
    );

    if (mutableFieldsChanged || roundsChanged) {
      log('Updated DAUComp attributes from database: ${existingComp.dbkey}');

      // Update active comp reference if it matches
      if (existingComp.dbkey == _activeDAUComp?.dbkey) {
        _activeDAUComp = existingComp;
      }

      // Update selected comp reference and link games if it matches
      if (existingComp.dbkey == _selectedDAUComp?.dbkey) {
        _selectedDAUComp = existingComp;
        if (roundsChanged) {
          await linkGamesWithRounds(_selectedDAUComp!.daurounds);
        }
      }
    }

    return null; // Return null to indicate no replacement needed
  }

  Future<void> _addNewComp(
    String dbKey,
    dynamic daucompAsJSON,
    Map<String, DAUComp> existingDAUCompsMap,
  ) async {
    List<DAURound> daurounds = _roundsParser.parseRounds(daucompAsJSON, combinedRoundsPath: combinedRoundsPath);
    DAUComp newComp = DAUComp.fromJson(
      Map<String, dynamic>.from(daucompAsJSON),
      dbKey,
      daurounds,
    );

    // Apply cutoff filter
    _roundsParser.applyCutoffFilter(newComp);

    existingDAUCompsMap[dbKey] = newComp;
    log('Added new DAUComp to memory: $dbKey');
  }

  Future<bool> _updateDauRounds(
    DAUComp existingComp,
    List<DAURound> databaseRounds,
  ) async {
    bool roundsChanged = false;

    // Create maps for efficient lookup
    Map<int, DAURound> existingRoundsMap = {
      for (var round in existingComp.daurounds) round.dAUroundNumber: round,
    };
    Map<int, DAURound> databaseRoundsMap = {
      for (var round in databaseRounds) round.dAUroundNumber: round,
    };

    // Update existing rounds and add new ones
    for (var databaseRound in databaseRounds) {
      int roundNumber = databaseRound.dAUroundNumber;

      if (existingRoundsMap.containsKey(roundNumber)) {
        // Update existing round
        if (await _updateSingleRound(
          existingRoundsMap[roundNumber]!,
          databaseRound,
        )) {
          roundsChanged = true;
        }
      } else {
        // Add new round
        existingComp.daurounds.add(databaseRound);
        roundsChanged = true;
        log('Added new round $roundNumber to comp ${existingComp.dbkey}');
      }
    }

    // Remove rounds that no longer exist in database
    List<DAURound> roundsToRemove = existingComp.daurounds
        .where((round) => !databaseRoundsMap.containsKey(round.dAUroundNumber))
        .toList();

    for (var roundToRemove in roundsToRemove) {
      existingComp.daurounds.remove(roundToRemove);
      roundsChanged = true;
      log(
        'Removed round ${roundToRemove.dAUroundNumber} from comp ${existingComp.dbkey}',
      );
    }

    // Sort rounds by round number
    if (roundsChanged) {
      existingComp.daurounds.sort(
        (a, b) => a.dAUroundNumber.compareTo(b.dAUroundNumber),
      );
    }

    return roundsChanged;
  }

  Future<bool> _updateSingleRound(
    DAURound existingRound,
    DAURound databaseRound,
  ) async {
    bool roundChanged = false;

    // Compare and update round attributes
    if (existingRound.firstGameKickOffUTC !=
        databaseRound.firstGameKickOffUTC) {
      existingRound.firstGameKickOffUTC = databaseRound.firstGameKickOffUTC;
      roundChanged = true;
    }
    if (existingRound.lastGameKickOffUTC != databaseRound.lastGameKickOffUTC) {
      existingRound.lastGameKickOffUTC = databaseRound.lastGameKickOffUTC;
      roundChanged = true;
    }
    if (existingRound.adminOverrideRoundStartDate !=
        databaseRound.adminOverrideRoundStartDate) {
      existingRound.adminOverrideRoundStartDate =
          databaseRound.adminOverrideRoundStartDate;
      roundChanged = true;
    }
    if (existingRound.adminOverrideRoundEndDate !=
        databaseRound.adminOverrideRoundEndDate) {
      existingRound.adminOverrideRoundEndDate =
          databaseRound.adminOverrideRoundEndDate;
      roundChanged = true;
    }

    if (roundChanged) {
      log('Updated round ${existingRound.dAUroundNumber} attributes');
    }

    return roundChanged;
  }

  // parsing and cutoff logic is now handled by DaucompsRoundsParser service

  void _initRoundState(DAURound round) {
    if (round.games.isEmpty) {
      round.roundState = RoundState.noGames;
      log(
        'Round ${round.dAUroundNumber} has no games. Check the fixture data and date ranges for each round.',
      );
      return;
    }

    bool anyGamesStarted = round.games.any(
      (game) =>
          game.gameState == GameState.startedResultKnown ||
          game.gameState == GameState.startedResultNotKnown,
    );
    bool allGamesEnded = round.games.every(
      (game) => game.gameState == GameState.startedResultKnown,
    );

    if (allGamesEnded) {
      round.roundState = RoundState.allGamesEnded;
    } else if (anyGamesStarted) {
      round.roundState = RoundState.started;
    } else {
      round.roundState = RoundState.notStarted;
    }
  }

  Future<void> _fixtureUpdate() async {
    await initialDAUCompLoadComplete;
    await gamesViewModel!.initialLoadComplete;

    if (_activeDAUComp == null) {
      log(
        '_fixtureUpdate() Active comp is null. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.',
      );
      return;
    }

    // if selected comp is not the active comp then we don't want to trigger the fixture update
    if (!isSelectedCompActiveComp()) {
      log(
        '_fixtureUpdate() Selected comp ${_selectedDAUComp?.name} is not the active comp. No fixture update will be triggered.',
      );
      return;
    }

    // if we are at the end of the competition, then don't trigger the fixture update
    if (_isCompOver(_activeDAUComp!)) {
      log(
        '_fixtureUpdate() End of competition detected for active comp: ${_activeDAUComp!.name}. Going forward only manual downloads by Admin will trigger an update.',
      );
      return;
    }

    try {
      log(
        '_fixtureUpdate() Starting fixture update for comp: ${_activeDAUComp!.name}',
      );
      // create an analytics event to track the fixture update trigger
      FirebaseAnalytics.instance.logEvent(
        name: 'fixture_trigger',
        parameters: {
          'comp': _activeDAUComp!.name,
          'tipperHandlingUpdate':
              di<TippersViewModel>().authenticatedTipper?.name ??
              'unknown tipper',
        },
      );
      await getNetworkFixtureData(_activeDAUComp!);
    }
    // ignore: avoid_catches_without_on_clauses
    catch (e) {
      log('_fixtureUpdateTrigger() Error fetching fixture data: $e');
    }
    // use this daily opportunity to delete stale tokens
    // this is done after the fixture update is complete
    await di<FirebaseMessagingService>().deleteStaleTokens(
      di<TippersViewModel>(),
    );
  }

  Future<bool> _acquireLock(DAUComp daucompToUpdate) async {
    DatabaseReference lockRef = _db.child(
      _lockManager.lockPathForComp(daucompsPath, daucompToUpdate.dbkey!),
    );
    DataSnapshot snapshot = await lockRef.get();

    if (snapshot.exists) {
      DateTime? lockTimestamp;
      if (snapshot.value is String) {
        lockTimestamp = DateTime.tryParse(snapshot.value as String);
      } else {
        lockTimestamp = null;
      }
      if (_lockManager.isLockFresh(lockTimestamp, DateTime.now(), const Duration(hours: 24))) {
        return false; // Lock is already held by another instance
      }
    }

    await lockRef.set(DateTime.now().toIso8601String());
    return true; // Lock acquired successfully
  }

  Future<void> _releaseLock(DAUComp daucompToUpdate) async {
    DatabaseReference lockRef = _db.child(
      _lockManager.lockPathForComp(daucompsPath, daucompToUpdate.dbkey!),
    );
    await lockRef.set(null);
  }

  Future<String> getNetworkFixtureData(DAUComp daucompToUpdate) async {
    if (_isDownloading) {
      log('getNetworkFixtureData() is already downloading');
      return 'Fixture data is already downloading';
    }

    await initialDAUCompLoadComplete;

    // acquire lock
    bool lockAcquired = await _acquireLock(daucompToUpdate);

    if (!lockAcquired) {
      log(
        'getNetworkFixtureData() Another instance is already downloading the fixture data. Skipping download.',
      );
      return 'Another instance is already downloading the fixture data. Skipping download.';
    }

    _isDownloading = true;
    notifyListeners();

    try {
      return await _fetchAndProcessFixtureData(daucompToUpdate);
    } catch (e) {
      log('Error fetching fixture data: $e');
      rethrow;
    } finally {
      _isDownloading = false;
      // release lock
      await _releaseLock(daucompToUpdate);
      notifyListeners();
    }
  }

  Future<String> _fetchAndProcessFixtureData(DAUComp daucompToUpdate) async {
    FixtureDownloadService fetcher = FixtureDownloadService();
    Map<String, List<dynamic>> fixtures = await fetcher.fetch(
      daucompToUpdate.nrlFixtureJsonURL,
      daucompToUpdate.aflFixtureJsonURL,
      true,
    );
    List<dynamic> nrlGames = fixtures['nrlGames']!;
    List<dynamic> aflGames = fixtures['aflGames']!;

    await Future.wait(_processGames(nrlGames, aflGames, daucompToUpdate));
    await gamesViewModel!.saveBatchOfGameAttributes();

    _tagGamesWithLeague(nrlGames, 'nrl');
    _tagGamesWithLeague(aflGames, 'afl');

    List<dynamic> allGames = nrlGames + aflGames;

    // do not change round start stop times if we have an existing config for round start/end times
    // instead admins can adjust in the UI
    // This mitigates afl cyclone bug from 2025
    if (daucompToUpdate.daurounds.isEmpty) {
      log(
        'DAUCompsViewModel()_fetchAndProcessFixtureData No existing rounds found. Creating $combinedRoundsPath with round start stop times.',
      );
      await _updateRoundStartEndTimesBasedOnFixture(daucompToUpdate, allGames);
    } else {
      log(
        'DAUCompsViewModel()_fetchAndProcessFixtureData Existing rounds found. Skipping updating $combinedRoundsPath round start stop time update.',
      );
    }

    String res =
        'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    FirebaseAnalytics.instance.logEvent(
      name: 'fixture_download',
      parameters: {'comp': daucompToUpdate.name, 'result': res},
    );

    daucompToUpdate.lastFixtureUpdateTimestampUTC = DateTime.now().toUtc();
    updateCompAttribute(
      daucompToUpdate.dbkey!,
      'lastFixtureUTC',
      daucompToUpdate.lastFixtureUpdateTimestampUTC!.toIso8601String(),
    );
    await saveBatchOfCompAttributes();

    // if nrlRaw and aflRaw are null then store the raw fixture data in the database for future reference
    if ((daucompToUpdate.nrlBaseline == null ||
            daucompToUpdate.nrlBaseline!.isEmpty) &&
        (daucompToUpdate.aflBaseline == null ||
            daucompToUpdate.aflBaseline!.isEmpty)) {
      _saveBaselineFixtureData(
        fixtures['nrlGames']!,
        fixtures['aflGames']!,
        daucompToUpdate,
      );
    }

    return res;
  }

  //store the baseline fixture data in the database - we will use it later to compare
  void _saveBaselineFixtureData(
    List<dynamic> nrlGames,
    List<dynamic> aflGames,
    DAUComp daucomp,
  ) {
    DatabaseReference nrlRawRef = _db.child(
      '$daucompsPath/${daucomp.dbkey}/nrlFixtureBaseline',
    );
    DatabaseReference aflRawRef = _db.child(
      '$daucompsPath/${daucomp.dbkey}/aflFixtureBaseline',
    );
    nrlRawRef.set(nrlGames);
    aflRawRef.set(aflGames);
  }

  void _tagGamesWithLeague(List<dynamic> games, String league) {
    for (var game in games) {
      game['league'] = league;
    }
  }

  Future<void> _updateRoundStartEndTimesBasedOnFixture(
    DAUComp daucomp,
    List<dynamic> rawGames,
  ) async {
    await initialDAUCompLoadComplete;

    // Build rounds using a pure service to improve testability
    final roundsBuilder = CombinedRoundsService();
    final combined = roundsBuilder.buildCombinedRounds(rawGames);

    // Update the database with calculated rounds
    await _updateCombinedRoundsInDatabase(combined, daucomp);
  }


  Future<void> _updateCombinedRoundsInDatabase(
    List<DAURound> combinedRounds,
    DAUComp daucomp,
  ) async {
    log('In daucompsviewmodel._updateCombinedRoundsInDatabase()');
    await initialDAUCompLoadComplete;

    final batch = _roundsPersistence.buildCombinedRoundsUpdates(
      daucomp,
      combinedRounds,
      daucompsPath: daucompsPath,
      combinedRoundsPath: combinedRoundsPath,
    );
    updates.addAll(batch);
    await saveBatchOfCompAttributes();
  }

  bool _isLinkingGames = false;
  bool get isLinkingGames => _isLinkingGames;

  Future<void> linkGamesWithRounds(List<DAURound> allRounds) async {
    log('In daucompsviewmodel.linkGamesWithRounds()');

    // make sure other view models are loaded
    await otherViewModelsLoadComplete;

    // Ensure only one instance runs at a time
    if (_isLinkingGames) {
      log('linkGamesWithRounds() is already running. Skipping this call.');
      return;
    }
    _isLinkingGames = true;
    notifyListeners();

    try {
      // Create a local copy of unassignedGames
      List<Game> localUnassignedGames = List.from(
        await gamesViewModel!.getGames(),
      );

      for (var round in allRounds) {
        // Assign games to the round
        round.games = await gamesViewModel!.getGamesForRound(round);

        // Initialize the round state
        _initRoundState(round);

        // Remove assigned games from the local unassigned games list
        localUnassignedGames.removeWhere(
          (game) =>
              round.games.any((roundGame) => roundGame.dbkey == game.dbkey),
        );

        // Remove games that exceed the cutoff time for NRL and AFL
        if (_selectedDAUComp!.nrlRegularCompEndDateUTC != null) {
          localUnassignedGames.removeWhere(
            (game) =>
                game.league == League.nrl &&
                game.startTimeUTC.isAfter(
                  _selectedDAUComp!.nrlRegularCompEndDateUTC!,
                ),
          );
        }

        if (_selectedDAUComp!.aflRegularCompEndDateUTC != null) {
          localUnassignedGames.removeWhere(
            (game) =>
                game.league == League.afl &&
                game.startTimeUTC.isAfter(
                  _selectedDAUComp!.aflRegularCompEndDateUTC!,
                ),
          );
        }

        // Update AFL and NRL game counts for the round
        round.nrlGameCount = round.games
            .where((game) => game.league == League.nrl)
            .toList()
            .length;
        round.aflGameCount = round.games
            .where((game) => game.league == League.afl)
            .toList()
            .length;
      }

      // Update the shared unassignedGames list after all operations are complete
      unassignedGames = localUnassignedGames;

      log('Unassigned games count: ${unassignedGames.length}');
    } catch (e) {
      log('Error in linkGamesWithRounds(): $e');
    } finally {
      _isLinkingGames = false;
      notifyListeners();
    }
  }

  Future<DAUComp?> findComp(String compDbKey) async {
    await initialDAUCompLoadComplete;
    return _daucomps.firstWhereOrNull((daucomp) => daucomp.dbkey == compDbKey);
  }

  void updateRoundAttribute(
    String dauCompDbKey,
    int roundNumber,
    String attributeName,
    dynamic attributeValue,
  ) {
    log(
      'updateRoundAttribute() called for $dauCompDbKey, $roundNumber, $attributeName, $attributeValue',
    );
    updates['$daucompsPath/$dauCompDbKey/$combinedRoundsPath/${roundNumber - 1}/$attributeName'] =
        attributeValue;
  }

  void updateCompAttribute(
    String dauCompDbKey,
    String attributeName,
    dynamic attributeValue,
  ) {
    log(
      'updateCompAttribute() called for $dauCompDbKey, $attributeName, $attributeValue',
    );
    updates['$daucompsPath/$dauCompDbKey/$attributeName'] = attributeValue;
  }

  Future<void> newDAUComp(DAUComp newDAUComp) async {
    if (newDAUComp.dbkey == null) {
      log('Adding new DAUComp record');
      DatabaseReference newCompRecordKey = _db.child(daucompsPath).push();
      updates['$daucompsPath/${newCompRecordKey.key}/name'] = newDAUComp.name;
      updates['$daucompsPath/${newCompRecordKey.key}/aflFixtureJsonURL'] =
          newDAUComp.aflFixtureJsonURL.toString();
      updates['$daucompsPath/${newCompRecordKey.key}/nrlFixtureJsonURL'] =
          newDAUComp.nrlFixtureJsonURL.toString();
      newDAUComp.dbkey = newCompRecordKey.key;
    } else {
      throw 'newDAUComp() called with existing DAUComp dbkey';
    }
  }

  Future<void> saveBatchOfCompAttributes() async {
    // check if there are any updates to save
    if (updates.isEmpty) {
      log('No DAUComp updates to save');
      return;
    }
    await initialDAUCompLoadComplete;
    log('Saving batch of ${updates.length} DAUComp database updates');
    await _db.update(updates);
    _savingDAUComp = false;
  }

  Future<List<DAUComp>> getDAUcomps() async {
    await initialDAUCompLoadComplete;
    return _daucomps;
  }

  Map<League, List<Game>> groupGamesIntoLeagues(DAURound combinedRound) {
    List<Game> nrlGames = [];
    List<Game> aflGames = [];

    List<Game> allGamesInRound = combinedRound.games;
    for (var game in allGamesInRound) {
      if (game.league == League.nrl) {
        nrlGames.add(game);
      } else {
        aflGames.add(game);
      }
    }

    nrlGames.sort();
    aflGames.sort();

    return {League.nrl: nrlGames, League.afl: aflGames};
  }

  void _otherViewModelUpdated() {
    notifyListeners();
  }

  List<Future> _processGames(
    List<dynamic> nrlGames,
    List<dynamic> aflGames,
    DAUComp daucomp,
  ) {
    List<Future> gamesFuture = [];

    void processGames(List<dynamic> games, League league) {
      for (var gamejson in games.cast<Map<dynamic, dynamic>>()) {
        String dbkey =
            '${league.name}-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        for (var attribute in gamejson.keys) {
          gamesFuture.add(
            gamesViewModel!.updateGameAttribute(
              dbkey,
              attribute,
              gamejson[attribute],
              league.name,
            ),
          );
        }
      }
    }

    processGames(nrlGames, League.nrl);
    processGames(aflGames, League.afl);

    return gamesFuture;
  }

  // private method to check if the comp is over i.e. all rounds have been completed and scored
  bool _isCompOver(DAUComp daucomp) {
    // check if there are zero rounds
    if (daucomp.daurounds.isEmpty) {
      return false;
    }
    DAURound lastRound = daucomp.daurounds.last;
    return lastRound.roundState == RoundState.allGamesEnded;
  }

  @override
  void dispose() {
    _dailyTimer?.cancel();
    _daucompsStream.cancel();

    // remove listeners if not in admin mode
    if (!_adminMode) {
      selectedTipperTipsViewModel?.removeListener(_otherViewModelUpdated);
    }
    statsViewModel!.removeListener(_otherViewModelUpdated);
    gamesViewModel?.removeListener(_otherViewModelUpdated);

    super.dispose();
  }

  // Ladder Caching Methods
  void clearLeagueLadderCache({League? league}) {
    if (league != null) {
      _cachedLadders.remove(league);
      log('DAUCompsViewModel: Cleared ladder cache for ${league.name}');
    } else {
      _cachedLadders.clear();
      log('DAUCompsViewModel: Cleared all ladder caches');
    }
    // notifyListeners(); // Consider if UI needs to react to cache clearing directly
  }

  Future<LeagueLadder?> getOrCalculateLeagueLadder(
    League league, {
    bool forceRecalculate = false,
  }) async {
    log(
      'DAUCompsViewModel: getOrCalculateLeagueLadder called for ${league.name}, forceRecalculate: $forceRecalculate',
    );

    if (forceRecalculate) {
      clearLeagueLadderCache(league: league);
    }

    if (_cachedLadders.containsKey(league)) {
      log('DAUCompsViewModel: Cache hit for ${league.name} ladder.');
      return _cachedLadders[league]!;
    }

    log(
      'DAUCompsViewModel: Cache miss for ${league.name} ladder. Proceeding to calculate.',
    );

    if (selectedDAUComp == null) {
      log(
        'DAUCompsViewModel: Cannot calculate ladder, selectedDAUComp is null.',
      );
      return null;
    }

    // Use the class member gamesViewModel directly, which is initialized with selectedDAUComp
    if (gamesViewModel == null) {
      log(
        'DAUCompsViewModel: Cannot calculate ladder, gamesViewModel is null for DAUComp ${selectedDAUComp?.name}.',
      );
      return null;
    }

    // gamesViewModel.getGames() already awaits initialLoadComplete within itself.
    // gamesViewModel.teamsViewModel.initialLoadComplete is also handled within gamesViewModel init.

    try {
      List<Game> allGames = await gamesViewModel!.getGames();
      // Accessing teamsViewModel through the initialized gamesViewModel instance
      List<Team> leagueTeams =
          gamesViewModel!.teamsViewModel.groupedTeams[league.name.toLowerCase()]
              ?.cast<Team>() ??
          [];

      final LadderCalculationService ladderService = LadderCalculationService();
      DateTime? cutoffDate;
      if (league == League.nrl) {
        cutoffDate = selectedDAUComp!.nrlRegularCompEndDateUTC;
      } else if (league == League.afl) {
        cutoffDate = selectedDAUComp!.aflRegularCompEndDateUTC;
      }

      LeagueLadder? calculatedLadder = ladderService.calculateLadder(
        allGames: allGames,
        leagueTeams: leagueTeams,
        league: league,
        cutoffDate: cutoffDate,
      );

      if (calculatedLadder != null) {
        _cachedLadders[league] = calculatedLadder;
        log(
          'DAUCompsViewModel: Calculated and cached ladder for ${league.name}. Teams count: ${calculatedLadder.teams.length}',
        );
      } else {
        log(
          'DAUCompsViewModel: Ladder calculation returned null for ${league.name}.',
        );
      }
      return calculatedLadder;
    } catch (e) {
      log('DAUCompsViewModel: Error calculating ladder for ${league.name}: $e');
      return null;
    }
  }

  // URL health check via service
  Future<bool> _isUriActive(String uri) async => _urlHealthChecker.isActive(Uri.parse(uri));

  Future<Map<String, dynamic>> processAndSaveDauComp({
    required String name,
    required String aflFixtureJsonURL,
    required String nrlFixtureJsonURL,
    required String? nrlRegularCompEndDateString,
    required String? aflRegularCompEndDateString,
    required DAUComp? existingComp,
    required List<DAURound> currentRounds, // New parameter
  }) async {
    try {
      bool aflURLActive = await _isUriActive(aflFixtureJsonURL);
      bool nrlURLActive = await _isUriActive(nrlFixtureJsonURL);
      log('aflURLActive = $aflURLActive');
      log('nrlURLActive = $nrlURLActive');

      if (aflURLActive && nrlURLActive) {
        if (existingComp == null) {
          // New comp
          DAUComp newDAUComp = DAUComp(
            name: name,
            aflFixtureJsonURL: Uri.parse(aflFixtureJsonURL),
            nrlFixtureJsonURL: Uri.parse(nrlFixtureJsonURL),
            nrlRegularCompEndDateUTC:
                nrlRegularCompEndDateString != null &&
                    nrlRegularCompEndDateString.isNotEmpty
                ? DateTime.parse(nrlRegularCompEndDateString)
                : null,
            aflRegularCompEndDateUTC:
                aflRegularCompEndDateString != null &&
                    aflRegularCompEndDateString.isNotEmpty
                ? DateTime.parse(aflRegularCompEndDateString)
                : null,
            daurounds: [], // Initial empty rounds
          );

          await this.newDAUComp(
            newDAUComp,
          ); // 'this.' to clarify it's the VM method
          await saveBatchOfCompAttributes();

          // Initialize GamesViewModel for the new comp
          // Ensure 'this' is passed if DAUCompsViewModel instance is needed by GamesViewModel constructor
          gamesViewModel = GamesViewModel(newDAUComp, this);
          await gamesViewModel?.initialLoadComplete;

          String fixtureMessage = await getNetworkFixtureData(newDAUComp);
          return {
            'success': true,
            'message': fixtureMessage,
            'newCompData': newDAUComp,
          };
        } else {
          // Existing comp
          updateCompAttribute(existingComp.dbkey!, "name", name);
          updateCompAttribute(
            existingComp.dbkey!,
            "aflFixtureJsonURL",
            aflFixtureJsonURL,
          );
          updateCompAttribute(
            existingComp.dbkey!,
            "nrlFixtureJsonURL",
            nrlFixtureJsonURL,
          );
          updateCompAttribute(
            existingComp.dbkey!,
            "nrlRegularCompEndDateUTC",
            nrlRegularCompEndDateString != null &&
                    nrlRegularCompEndDateString.isNotEmpty
                ? DateTime.parse(nrlRegularCompEndDateString).toIso8601String()
                : null,
          );
          updateCompAttribute(
            existingComp.dbkey!,
            "aflRegularCompEndDateUTC",
            aflRegularCompEndDateString != null &&
                    aflRegularCompEndDateString.isNotEmpty
                ? DateTime.parse(aflRegularCompEndDateString).toIso8601String()
                : null,
          );

          // If activeDAUComp is not null and its dbkey matches existingComp's dbkey,
          // then iterate over activeDAUComp.daurounds. Otherwise, use existingComp.daurounds.
          // This is to ensure that we are saving the latest version of the rounds data if it was modified in memory.
          // However, the existingComp passed from the UI _should_ be the one from the ViewModel's perspective (activeDAUComp or selectedDAUComp).
          // For safety, let's use the rounds from the `existingComp` parameter as it's what the UI is working with.
          // Changed to iterate over currentRounds as per the subtask instruction
          for (DAURound round in currentRounds) {
            if (round.adminOverrideRoundStartDate != null) {
              updateRoundAttribute(
                existingComp.dbkey!,
                round.dAUroundNumber,
                "adminOverrideRoundStartDate",
                round.adminOverrideRoundStartDate!.toUtc().toIso8601String(),
              );
            }
            if (round.adminOverrideRoundEndDate != null) {
              updateRoundAttribute(
                existingComp.dbkey!,
                round.dAUroundNumber,
                "adminOverrideRoundEndDate",
                round.adminOverrideRoundEndDate!.toUtc().toIso8601String(),
              );
            }
          }
          await saveBatchOfCompAttributes();
          return {
            'success': true,
            'message': 'DAUComp record saved',
            'newCompData': null,
          };
        }
      } else {
        return {
          'success': false,
          'message': 'One or both of the URL\'s are not active',
          'newCompData': null,
        };
      }
    } catch (e) {
      log('Error in processAndSaveDauComp: $e');
      return {
        'success': false,
        'message': 'Failed to save DAUComp: ${e.toString()}',
        'newCompData': null,
      };
    }
  }
}
