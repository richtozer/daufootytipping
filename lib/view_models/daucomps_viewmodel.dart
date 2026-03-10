import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/messaging_service.dart';
import 'package:daufootytipping/services/ladder_calculation_service.dart'; // Added import
import 'package:daufootytipping/models/league_ladder.dart'; // Added import
import 'package:daufootytipping/services/combined_rounds_service.dart';
import 'package:daufootytipping/services/combined_rounds_persistence.dart';
import 'package:daufootytipping/services/daucomps_snapshot_applier.dart';
import 'package:daufootytipping/services/fixture_update_coordinator.dart';
import 'package:daufootytipping/services/lock_manager.dart';
import 'package:daufootytipping/services/timer_scheduler.dart';
import 'package:daufootytipping/services/url_health_checker.dart';
import 'package:daufootytipping/repositories/daucomps_repository.dart';
import 'package:daufootytipping/services/rounds_linking_service.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:daufootytipping/services/fixture_update_service.dart';
import 'package:daufootytipping/services/analytics_service.dart';
import 'package:daufootytipping/services/fixture_import_applier.dart';
import 'package:daufootytipping/services/selection_init_coordinator.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart';

enum LeagueLadderAvailability {
  unknown,
  ready,
  insufficientData,
  unavailable,
}

class DAUCompsViewModel extends ChangeNotifier {
  static const String _cachedDauCompsKey = 'cached_daucomps_v1';
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
  final Map<League, Future<LeagueLadder?>> _inFlightLadderCalculations = {};
  final Map<League, LeagueLadderAvailability> _cachedLadderAvailability = {};
  DAURound? _cachedGroupedGamesRound;
  List<Game>? _cachedGroupedGamesSource;
  int? _cachedGroupedGamesCount;
  Map<League, List<Game>>? _cachedGroupedGames;
  final CombinedRoundsPersistence _roundsPersistence = const CombinedRoundsPersistence();
  final FixtureUpdateCoordinator _fixtureCoordinator;
  final DauCompsSnapshotApplier _snapshotApplier = const DauCompsSnapshotApplier();
  final LockManager _lockManager = const LockManager();
  final TimerScheduler _timerScheduler = const TimerSchedulerDefault();
  final UrlHealthChecker _urlHealthChecker = UrlHealthChecker();
  final AnalyticsService _analytics;
  final MessagingService _messaging;
  final FixtureUpdateService _fixtureUpdater;
  final RoundsLinkingService _roundsLinking = const RoundsLinkingService();
  final FixtureImportApplier _importApplier = const FixtureImportApplier();
  final SelectionInitCoordinator _selectionInit = const SelectionInitCoordinator();

  final DauCompsRepository _repo;
  final TippersViewModel Function() _tippers;
  final Future<SharedPreferences> Function() _prefsFactory;
  bool _hasReceivedRemoteSnapshot = false;

  DAUCompsViewModel(
    this._initDAUCompDbKey,
    this._adminMode, {
    bool skipInit = false,
    DauCompsRepository? repo,
    FixtureDownloadService? fixtureDownloader,
    AnalyticsService? analytics,
    MessagingService? messaging,
    TippersViewModel Function()? tippers,
    FixtureUpdateCoordinator? fixtureCoordinator,
    Future<SharedPreferences> Function()? prefsFactory,
  })  : _repo = repo ?? FirebaseDauCompsRepository(),
        _fixtureUpdater = FixtureUpdateService(fixtureDownloader ?? FixtureDownloadService()),
        _analytics = analytics ?? FirebaseAnalyticsService(),
        _messaging = messaging ?? FirebaseMessagingServiceAdapter(),
        _tippers = tippers ?? (() => di<TippersViewModel>()),
        _fixtureCoordinator = fixtureCoordinator ?? const FixtureUpdateCoordinator(),
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance {
    log(
      'DAUCompsViewModel() created with comp: $_initDAUCompDbKey, adminMode: $_adminMode',
    );
    if (!skipInit) {
      unawaited(_restoreCachedDauComps());
      _init();
    }
  }

  // --- Testability additions ---
  @visibleForTesting
  void setSelectedCompForTest(DAUComp comp) {
    _selectedDAUComp = comp;
    _clearGroupedGamesCache();
    clearLeagueLadderCache();
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
    final role = _tippers().authenticatedTipper?.tipperRole;
    final shouldStart = _fixtureCoordinator.shouldStartDailyTimer(
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
    final didRun = await _fixtureCoordinator.maybeTriggerUpdate(
      activeComp: _activeDAUComp,
      selectedComp: _selectedDAUComp,
      threshold: fixtureUpdateTimerDuration,
      isSelectedCompActive: isSelectedCompActiveComp,
      isCompOver: _isCompOver,
      refreshActiveByKey: (key) async {
        _activeDAUComp = await findComp(key);
        return _activeDAUComp;
      },
      logAnalytics: (name, params) => _analytics.logEvent(
        name,
        parameters: {
          ...params,
          'tipperHandlingUpdate': _tippers().authenticatedTipper?.name ?? 'unknown tipper',
        },
      ),
      runFixtureUpdate: (comp) async {
        // Preserve prior behavior: await games VM load before updating fixtures
        await gamesViewModel?.initialLoadComplete;
        return getNetworkFixtureData(comp);
      },
      afterUpdate: () => _messaging.deleteStaleTokens(_tippers()),
    );

    if (!didRun) {
      log(
        'DAUCompsViewModel_triggerDailyEvent() Looks like another client did an update in the last ${fixtureUpdateTimerDuration.inHours} hours or conditions not met. Skipping fixture update.',
      );
    } else {
      log('DAUCompsViewModel_triggerDailyEvent()  Triggering fixture update');
    }
  }

  Future<void> changeDisplayedDAUComp(
    DAUComp? changeToDAUComp,
    bool changingActiveComp,
  ) async {
    _selectedDAUComp = changeToDAUComp;
    _clearGroupedGamesCache();
    clearLeagueLadderCache();

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
    _disposeChildViewModels();
    await StartupProfiling.trackAsync(
      'startup.initialize_user_view_models',
      () async {
        await initialDAUCompLoadComplete;

        final res = await StartupProfiling.trackAsync(
          'startup.selection_init_initialize_user',
          () => _selectionInit.initializeUser(
            selectedComp: _selectedDAUComp!,
            createGamesViewModel: () => StartupProfiling.trackSync(
              'startup.create_games_view_model',
              () => GamesViewModel(_selectedDAUComp!, this),
            ),
            awaitTippersReady: () async {
              // Do not block startup on loading the full tippers list.
              await StartupProfiling.trackAsync(
                'startup.await_user_linked',
                () => _tippers().isUserLinked,
              );
            },
            createStatsViewModel: (comp, gamesVm) => StartupProfiling.trackSync(
              'startup.create_stats_view_model',
              () => StatsViewModel(comp, gamesVm),
            ),
            createTipsViewModel: (gamesVm) => StartupProfiling.trackSync(
              'startup.create_tips_view_model',
              () => TipsViewModel.forTipper(
                _tippers(),
                _selectedDAUComp!,
                gamesVm,
                _tippers().selectedTipper,
              ),
            ),
          ),
          arguments: <String, Object?>{
            'compDbKey': _selectedDAUComp?.dbkey ?? 'unknown',
          },
        );

        // DI registration for StatsViewModel remains in VM
        if (di.isRegistered<StatsViewModel>()) {
          di.unregister<StatsViewModel>();
        }
        di.registerSingleton<StatsViewModel>(res.statsViewModel);

        gamesViewModel = res.gamesViewModel;
        statsViewModel = di<StatsViewModel>();
        selectedTipperTipsViewModel = res.tipsViewModel;

        gamesViewModel!.addListener(_otherViewModelUpdated);
        statsViewModel!.addListener(_otherViewModelUpdated);
        selectedTipperTipsViewModel!.addListener(_otherViewModelUpdated);
        StartupProfiling.instant(
          'startup.user_view_models_ready',
          arguments: <String, Object?>{
            'compDbKey': _selectedDAUComp?.dbkey ?? 'unknown',
          },
        );
      },
      arguments: <String, Object?>{
        'compDbKey': _selectedDAUComp?.dbkey ?? 'unknown',
      },
    );
  }

  Future<void> _initializeAdminViewModels() async {
    _disposeChildViewModels();
    final res = await _selectionInit.initializeAdmin(
      selectedComp: _selectedDAUComp!,
      createGamesViewModel: () => GamesViewModel(_selectedDAUComp!, this),
      createStatsViewModel: (comp, gamesVm) => StatsViewModel(comp, gamesVm),
    );

    if (di.isRegistered<StatsViewModel>()) {
      di.unregister<StatsViewModel>();
    }
    di.registerSingleton<StatsViewModel>(res.statsViewModel);
    gamesViewModel = res.gamesViewModel;
    statsViewModel = di<StatsViewModel>();

    gamesViewModel!.addListener(_otherViewModelUpdated);
    statsViewModel!.addListener(_otherViewModelUpdated);
  }

  void _listenToDAUComps() {
    _daucompsStream = _repo.streamDauComps(daucompsPath).listen(_handleEvent);
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('DAUCompsViewModel_handleEvent()');
      _hasReceivedRemoteSnapshot = true;
      final bool isFirstLoad = !_initialDAUCompLoadCompleter.isCompleted;
      final Stopwatch processingStopwatch = Stopwatch()..start();
      final dynamic rawValue = event.snapshot.value;
      final int entryCount = rawValue is Map ? rawValue.length : 0;
      final int? payloadBytes = StartupProfiling.estimatePayloadBytes(rawValue);
      StartupProfiling.instant(
        'startup.daucomps_snapshot_received',
        arguments: <String, Object?>{
          'exists': event.snapshot.exists,
          'entryCount': entryCount,
          'payloadBytes': payloadBytes ?? -1,
          'firstLoad': isFirstLoad,
        },
      );

      if (event.snapshot.exists) {
        final value = event.snapshot.value as dynamic;
        final databaseMap = Map<String, dynamic>.from(value as Map);
        await _applyDatabaseMap(databaseMap);
        unawaited(_cacheCurrentDauComps(databaseMap));
      } else {
        log('No DAUComps found at database location: $daucompsPath');
        _daucomps = [];
      }

      if (!_initialDAUCompLoadCompleter.isCompleted) {
        _initialDAUCompLoadCompleter.complete();
      }

      processingStopwatch.stop();
      StartupProfiling.instant(
        'startup.daucomps_snapshot_processed',
        arguments: <String, Object?>{
          'elapsedMs': processingStopwatch.elapsedMilliseconds,
          'daucompsCount': _daucomps.length,
          'firstLoad': isFirstLoad,
        },
      );
      notifyListeners();
    } catch (e) {
      log('Error listening to $daucompsPath: $e');
      rethrow;
    }
  }

  Future<void> _restoreCachedDauComps() async {
    try {
      final SharedPreferences prefs = await _prefsFactory();
      final String? cachedDauCompsJson = prefs.getString(_cachedDauCompsKey);
      if (cachedDauCompsJson == null || _hasReceivedRemoteSnapshot) {
        return;
      }

      final Map<String, dynamic> cachedDauComps = Map<String, dynamic>.from(
        jsonDecode(cachedDauCompsJson) as Map,
      );
      await _applyDatabaseMap(cachedDauComps);
      StartupProfiling.instant(
        'startup.daucomps_cache_loaded',
        arguments: <String, Object?>{
          'daucompsCount': _daucomps.length,
          'bootstrapReady': _daucomps.isNotEmpty,
        },
      );
      if (!_initialDAUCompLoadCompleter.isCompleted) {
        _initialDAUCompLoadCompleter.complete();
      }
      notifyListeners();
    } catch (error, stackTrace) {
      log(
        'DAUCompsViewModel._restoreCachedDauComps() Error restoring cache: $error',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cacheCurrentDauComps(Map<String, dynamic> databaseMap) async {
    try {
      final SharedPreferences prefs = await _prefsFactory();
      await prefs.setString(
        _cachedDauCompsKey,
        jsonEncode(databaseMap),
      );
    } catch (error, stackTrace) {
      log(
        'DAUCompsViewModel._cacheCurrentDauComps() Error caching DAUComps: $error',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _applyDatabaseMap(Map<String, dynamic> databaseMap) async {
    final result = _snapshotApplier.apply(
      databaseValue: databaseMap,
      currentComps: _daucomps,
      combinedRoundsPath: combinedRoundsPath,
    );

    _daucomps = result.comps;

    if (_activeDAUComp != null) {
      _activeDAUComp = _daucomps.firstWhereOrNull(
        (c) => c.dbkey == _activeDAUComp!.dbkey,
      );
    }
    if (_selectedDAUComp != null) {
      _selectedDAUComp = _daucomps.firstWhereOrNull(
        (c) => c.dbkey == _selectedDAUComp!.dbkey,
      );
    }
    _clearGroupedGamesCache();

    final selKey = _selectedDAUComp?.dbkey;
    if (selKey != null && result.compKeysNeedingRelink.contains(selKey)) {
      await linkGamesWithRounds(_selectedDAUComp!.daurounds);
    }
  }


  // parsing and cutoff logic is now handled by DaucompsRoundsParser service

  

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
    return _fixtureUpdater.runUpdate(
      comp: daucompToUpdate,
      acquireLock: () => _acquireLock(daucompToUpdate),
      releaseLock: () => _releaseLock(daucompToUpdate),
      setDownloading: (v) {
        _isDownloading = v;
        notifyListeners();
      },
      processFetched: (comp, nrl, afl) => _processFetchedFixtures(comp, nrl, afl),
    );
  }

  Future<String> _processFetchedFixtures(
    DAUComp daucompToUpdate,
    List<dynamic> nrlGames,
    List<dynamic> aflGames,
  ) async {
    // Build and apply per-game updates
    final ops = _importApplier.buildGameUpdates(nrlGames, aflGames);
    final futures = <Future>[];
    for (final op in ops) {
      for (final entry in op.attributes.entries) {
        futures.add(
          gamesViewModel!.updateGameAttribute(
            op.dbkey,
            entry.key,
            entry.value,
            op.league,
          ),
        );
      }
    }
    await Future.wait(futures);
    await gamesViewModel!.saveBatchOfGameAttributes();

    // Tag games with league in-place (keeps previous behavior for raw arrays)
    _importApplier.tagGamesWithLeagueInPlace(nrlGames, 'nrl');
    _importApplier.tagGamesWithLeagueInPlace(aflGames, 'afl');

    List<dynamic> allGames = nrlGames + aflGames;
    final combined = _importApplier.computeCombinedRoundsIfMissing(daucompToUpdate, allGames);
    if (combined != null) {
      log('DAUCompsViewModel()_fetchAndProcessFixtureData No existing rounds found. Creating $combinedRoundsPath with round start stop times.');
      await _updateRoundStartEndTimesBasedOnFixture(daucompToUpdate, allGames);
    } else {
      log('DAUCompsViewModel()_fetchAndProcessFixtureData Existing rounds found. Skipping updating $combinedRoundsPath round start stop time update.');
    }

    String res =
        'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    await _analytics.logEvent('fixture_download',
        parameters: {'comp': daucompToUpdate.name, 'result': res});

    daucompToUpdate.lastFixtureUpdateTimestampUTC = DateTime.now().toUtc();
    updateCompAttribute(
      daucompToUpdate.dbkey!,
      lastFixtureUTCKey,
      daucompToUpdate.lastFixtureUpdateTimestampUTC!.toIso8601String(),
    );
    await saveBatchOfCompAttributes();

    return res;
  }

  // tagging handled via FixtureImportApplier

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

    try {
      _clearGroupedGamesCache();
      // Assign round.games via GamesViewModel to keep behavior consistent
      for (var round in allRounds) {
        round.games = await gamesViewModel!.getGamesForRound(round);
      }

      final all = await gamesViewModel!.getGames();
      unassignedGames = _roundsLinking.finalizeRoundsAndComputeUnassigned(
        rounds: allRounds,
        allGames: all,
        nrlCutoff: _selectedDAUComp!.nrlRegularCompEndDateUTC,
        aflCutoff: _selectedDAUComp!.aflRegularCompEndDateUTC,
      );
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
      final key = await _repo.newCompKey(daucompsPath);
      updates['$daucompsPath/$key/$compNameKey'] = newDAUComp.name;
      updates['$daucompsPath/$key/$aflFixtureJsonURLKey'] =
          newDAUComp.aflFixtureJsonURL.toString();
      updates['$daucompsPath/$key/$nrlFixtureJsonURLKey'] =
          newDAUComp.nrlFixtureJsonURL.toString();
      newDAUComp.dbkey = key;
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
    await _repo.update(updates);
    _savingDAUComp = false;
  }

  Future<List<DAUComp>> getDAUcomps() async {
    await initialDAUCompLoadComplete;
    return _daucomps;
  }

  void _clearGroupedGamesCache() {
    _cachedGroupedGamesRound = null;
    _cachedGroupedGamesSource = null;
    _cachedGroupedGamesCount = null;
    _cachedGroupedGames = null;
  }

  Map<League, List<Game>> _copyGroupedGames(Map<League, List<Game>> grouped) {
    return {
      League.nrl: List<Game>.from(grouped[League.nrl] ?? const <Game>[]),
      League.afl: List<Game>.from(grouped[League.afl] ?? const <Game>[]),
    };
  }

  Map<League, List<Game>> groupGamesIntoLeagues(DAURound combinedRound) {
    final List<Game> allGamesInRound = combinedRound.games;
    if (_cachedGroupedGames != null &&
        identical(_cachedGroupedGamesRound, combinedRound) &&
        identical(_cachedGroupedGamesSource, allGamesInRound) &&
        _cachedGroupedGamesCount == allGamesInRound.length) {
      return _copyGroupedGames(_cachedGroupedGames!);
    }

    final List<Game> nrlGames = [];
    final List<Game> aflGames = [];
    for (var game in allGamesInRound) {
      if (game.league == League.nrl) {
        nrlGames.add(game);
      } else {
        aflGames.add(game);
      }
    }

    nrlGames.sort();
    aflGames.sort();

    _cachedGroupedGamesRound = combinedRound;
    _cachedGroupedGamesSource = allGamesInRound;
    _cachedGroupedGamesCount = allGamesInRound.length;
    _cachedGroupedGames = {
      League.nrl: List<Game>.unmodifiable(nrlGames),
      League.afl: List<Game>.unmodifiable(aflGames),
    };

    return _copyGroupedGames(_cachedGroupedGames!);
  }

  int currentRoundOutstandingTipsCount() {
    final comp = _selectedDAUComp;
    final tipsViewModel = selectedTipperTipsViewModel;
    if (comp == null || tipsViewModel == null || comp.daurounds.isEmpty) {
      return 0;
    }

    final roundNumber = comp.firstNotEndedRoundNumber();
    if (roundNumber < 1 || roundNumber > comp.daurounds.length) {
      return 0;
    }
    final currentRound = comp.daurounds[roundNumber - 1];
    if (currentRound.roundState != RoundState.started &&
        currentRound.roundState != RoundState.notStarted) {
      return 0;
    }

    final outstanding =
        tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          currentRound,
          League.nrl,
        ) +
        tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          currentRound,
          League.afl,
        );

    return outstanding > 0 ? outstanding : 0;
  }

  void _otherViewModelUpdated() {
    _clearGroupedGamesCache();
    notifyListeners();
  }

  /// Disposes child ViewModels (games, stats, tips) before re-initialization
  /// to prevent leaked Firebase stream subscriptions and listeners.
  void _disposeChildViewModels() {
    gamesViewModel?.removeListener(_otherViewModelUpdated);
    gamesViewModel?.dispose();
    gamesViewModel = null;

    statsViewModel?.removeListener(_otherViewModelUpdated);
    statsViewModel?.dispose();
    statsViewModel = null;

    selectedTipperTipsViewModel?.removeListener(_otherViewModelUpdated);
    selectedTipperTipsViewModel?.dispose();
    selectedTipperTipsViewModel = null;
  }

  // per-game processing handled via FixtureImportApplier

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
    _disposeChildViewModels();
    super.dispose();
  }

  // Ladder Caching Methods
  void clearLeagueLadderCache({League? league}) {
    if (league != null) {
      _cachedLadders.remove(league);
      _inFlightLadderCalculations.remove(league);
      _cachedLadderAvailability.remove(league);
      log('DAUCompsViewModel: Cleared ladder cache for ${league.name}');
    } else {
      _cachedLadders.clear();
      _inFlightLadderCalculations.clear();
      _cachedLadderAvailability.clear();
      log('DAUCompsViewModel: Cleared all ladder caches');
    }
    // notifyListeners(); // Consider if UI needs to react to cache clearing directly
  }

  LeagueLadderAvailability getLeagueLadderAvailability(League league) {
    return _cachedLadderAvailability[league] ?? LeagueLadderAvailability.unknown;
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

    if (_cachedLadderAvailability[league] ==
        LeagueLadderAvailability.insufficientData) {
      log(
        'DAUCompsViewModel: Cached insufficient ladder data for ${league.name}.',
      );
      return null;
    }

    final inFlightCalculation = _inFlightLadderCalculations[league];
    if (inFlightCalculation != null) {
      log(
        'DAUCompsViewModel: Reusing in-flight ladder calculation for ${league.name}.',
      );
      return inFlightCalculation;
    }

    log(
      'DAUCompsViewModel: Cache miss for ${league.name} ladder. Proceeding to calculate.',
    );

    if (selectedDAUComp == null) {
      _cachedLadderAvailability[league] = LeagueLadderAvailability.unavailable;
      log(
        'DAUCompsViewModel: Cannot calculate ladder, selectedDAUComp is null.',
      );
      return null;
    }

    // Use the class member gamesViewModel directly, which is initialized with selectedDAUComp
    if (gamesViewModel == null) {
      _cachedLadderAvailability[league] = LeagueLadderAvailability.unavailable;
      log(
        'DAUCompsViewModel: Cannot calculate ladder, gamesViewModel is null for DAUComp ${selectedDAUComp?.name}.',
      );
      return null;
    }

    // gamesViewModel.getGames() already awaits initialLoadComplete within itself.
    // gamesViewModel.teamsViewModel.initialLoadComplete is also handled within gamesViewModel init.

    final currentComp = selectedDAUComp!;
    final currentGamesViewModel = gamesViewModel!;
    final calculationFuture = _calculateAndCacheLeagueLadder(
      league: league,
      selectedComp: currentComp,
      currentGamesViewModel: currentGamesViewModel,
    );
    _inFlightLadderCalculations[league] = calculationFuture;

    try {
      return await calculationFuture;
    } finally {
      if (identical(_inFlightLadderCalculations[league], calculationFuture)) {
        _inFlightLadderCalculations.remove(league);
      }
    }
  }

  Future<LeagueLadder?> _calculateAndCacheLeagueLadder({
    required League league,
    required DAUComp selectedComp,
    required GamesViewModel currentGamesViewModel,
  }) async {
    try {
      List<Game> allGames = await currentGamesViewModel.getGames();
      // Accessing teamsViewModel through the initialized gamesViewModel instance
      List<Team> leagueTeams =
          currentGamesViewModel
              .teamsViewModel
              .groupedTeams[league.name.toLowerCase()]
              ?.cast<Team>() ??
          [];

      final LadderCalculationService ladderService = LadderCalculationService();
      DateTime? cutoffDate;
      if (league == League.nrl) {
        cutoffDate = selectedComp.nrlRegularCompEndDateUTC;
      } else if (league == League.afl) {
        cutoffDate = selectedComp.aflRegularCompEndDateUTC;
      }

      LeagueLadder? calculatedLadder = ladderService.calculateLadder(
        allGames: allGames,
        leagueTeams: leagueTeams,
        league: league,
        cutoffDate: cutoffDate,
      );

      if (calculatedLadder != null) {
        final bool sameCompStillSelected =
            identical(_selectedDAUComp, selectedComp) ||
            _selectedDAUComp?.dbkey == selectedComp.dbkey;
        final bool sameGamesViewModelStillActive =
            identical(gamesViewModel, currentGamesViewModel);

        if (sameCompStillSelected && sameGamesViewModelStillActive) {
          _cachedLadders[league] = calculatedLadder;
          _cachedLadderAvailability[league] = LeagueLadderAvailability.ready;
          log(
            'DAUCompsViewModel: Calculated and cached ladder for ${league.name}. Teams count: ${calculatedLadder.teams.length}',
          );
        } else {
          log(
            'DAUCompsViewModel: Calculated ladder for ${league.name} but skipped caching because the selected comp changed.',
          );
        }
      } else {
        final bool sameCompStillSelected =
            identical(_selectedDAUComp, selectedComp) ||
            _selectedDAUComp?.dbkey == selectedComp.dbkey;
        final bool sameGamesViewModelStillActive =
            identical(gamesViewModel, currentGamesViewModel);

        if (sameCompStillSelected && sameGamesViewModelStillActive) {
          _cachedLadderAvailability[league] =
              LeagueLadderAvailability.insufficientData;
          log(
            'DAUCompsViewModel: Insufficient completed rounds to calculate ladder for ${league.name}.',
          );
        } else {
          log(
            'DAUCompsViewModel: Ladder calculation returned null for ${league.name} after selected comp changed.',
          );
        }
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
          updateCompAttribute(existingComp.dbkey!, compNameKey, name);
          updateCompAttribute(
            existingComp.dbkey!,
            aflFixtureJsonURLKey,
            aflFixtureJsonURL,
          );
          updateCompAttribute(
            existingComp.dbkey!,
            nrlFixtureJsonURLKey,
            nrlFixtureJsonURL,
          );
          updateCompAttribute(
            existingComp.dbkey!,
            nrlRegularCompEndDateUTCKey,
            nrlRegularCompEndDateString != null &&
                    nrlRegularCompEndDateString.isNotEmpty
                ? DateTime.parse(nrlRegularCompEndDateString).toIso8601String()
                : null,
          );
          updateCompAttribute(
            existingComp.dbkey!,
            aflRegularCompEndDateUTCKey,
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
                adminOverrideRoundStartDateKey,
                round.adminOverrideRoundStartDate!.toUtc().toIso8601String(),
              );
            }
            if (round.adminOverrideRoundEndDate != null) {
              updateRoundAttribute(
                existingComp.dbkey!,
                round.dAUroundNumber,
                adminOverrideRoundEndDateKey,
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
