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
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart';

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
  })  : _repo = repo ?? FirebaseDauCompsRepository(),
        _fixtureUpdater = FixtureUpdateService(fixtureDownloader ?? FixtureDownloadService()),
        _analytics = analytics ?? FirebaseAnalyticsService(),
        _messaging = messaging ?? FirebaseMessagingServiceAdapter(),
        _tippers = tippers ?? (() => di<TippersViewModel>()),
        _fixtureCoordinator = fixtureCoordinator ?? const FixtureUpdateCoordinator() {
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

    final res = await _selectionInit.initializeUser(
      selectedComp: _selectedDAUComp!,
      createGamesViewModel: () => GamesViewModel(_selectedDAUComp!, this),
      awaitTippersReady: () async {
        await _tippers().initialLoadComplete;
        await _tippers().isUserLinked;
      },
      createStatsViewModel: (comp, gamesVm) => StatsViewModel(comp, gamesVm),
      createTipsViewModel: (gamesVm) => TipsViewModel.forTipper(
        _tippers(),
        _selectedDAUComp!,
        gamesVm,
        _tippers().selectedTipper,
      ),
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
  }

  Future<void> _initializeAdminViewModels() async {
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
      if (event.snapshot.exists) {
        final value = event.snapshot.value as dynamic;
        final databaseMap = Map<String, dynamic>.from(value as Map);
        final result = _snapshotApplier.apply(
          databaseValue: databaseMap,
          currentComps: _daucomps,
          combinedRoundsPath: combinedRoundsPath,
        );

        _daucomps = result.comps;

        // Refresh pointers to active/selected comps
        if (_activeDAUComp != null) {
          _activeDAUComp = _daucomps.firstWhereOrNull((c) => c.dbkey == _activeDAUComp!.dbkey);
        }
        if (_selectedDAUComp != null) {
          _selectedDAUComp = _daucomps.firstWhereOrNull((c) => c.dbkey == _selectedDAUComp!.dbkey);
        }

        // If selected comp had rounds changed or was replaced, relink games
        final selKey = _selectedDAUComp?.dbkey;
        if (selKey != null && result.compKeysNeedingRelink.contains(selKey)) {
          await linkGamesWithRounds(_selectedDAUComp!.daurounds);
        }
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

    if ((daucompToUpdate.nrlBaseline == null ||
            daucompToUpdate.nrlBaseline!.isEmpty) &&
        (daucompToUpdate.aflBaseline == null ||
            daucompToUpdate.aflBaseline!.isEmpty)) {
      _saveBaselineFixtureData(
        nrlGames,
        aflGames,
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
      '$daucompsPath/${daucomp.dbkey}/$nrlFixtureBaselineKey',
    );
    DatabaseReference aflRawRef = _db.child(
      '$daucompsPath/${daucomp.dbkey}/$aflFixtureBaselineKey',
    );
    nrlRawRef.set(nrlGames);
    aflRawRef.set(aflGames);
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
    notifyListeners();

    try {
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
