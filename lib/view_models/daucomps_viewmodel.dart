import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/ladder_calculation_service.dart'; // Added import
import 'package:daufootytipping/models/league_ladder.dart'; // Added import
import 'package:daufootytipping/services/combined_rounds_service.dart';
import 'package:daufootytipping/services/combined_rounds_persistence.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/daucomps_snapshot_applier.dart';
import 'package:daufootytipping/services/lock_manager.dart';
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
import 'package:daufootytipping/services/kickoff_refresh_scheduler.dart';
import 'package:daufootytipping/services/selection_init_coordinator.dart';
import 'package:dau_shared/services/outstanding_tips_calculator.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart';

enum LeagueLadderAvailability {
  unknown,
  ready,
  insufficientData,
  unavailable,
}

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];
  List<DAUComp> get daucomps => _daucomps;
  // Lazily access database reference to avoid Firebase initialization during pure unit tests
  DatabaseReference get _db => configuredDatabaseRef();
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
  bool _lastFixtureDownloadRanViaCloudFunction = false;
  bool get lastFixtureDownloadRanViaCloudFunction =>
      _lastFixtureDownloadRanViaCloudFunction;

  final bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  GamesViewModel? gamesViewModel;
  StatsViewModel? statsViewModel;
  TipsViewModel? selectedTipperTipsViewModel;

  final Map<String, dynamic> updates = {};
  final bool _adminMode;
  bool get adminMode => _adminMode;

  List<Game> unassignedGames = []; // List to store unassigned games
  final Map<League, LeagueLadder> _cachedLadders = {}; // Added cache storage
  final Map<League, Future<LeagueLadder?>> _inFlightLadderCalculations = {};
  final Map<League, LeagueLadderAvailability> _cachedLadderAvailability = {};
  final ValueNotifier<int> _leagueLadderRevision = ValueNotifier<int>(0);
  ValueListenable<int> get leagueLadderRevision => _leagueLadderRevision;
  DAURound? _cachedGroupedGamesRound;
  List<Game>? _cachedGroupedGamesSource;
  int? _cachedGroupedGamesCount;
  Map<League, List<Game>>? _cachedGroupedGames;
  final CombinedRoundsPersistence _roundsPersistence = const CombinedRoundsPersistence();
  final DauCompsSnapshotApplier _snapshotApplier = const DauCompsSnapshotApplier();
  final LockManager _lockManager = const LockManager();
  late final UrlHealthChecker _urlHealthChecker;
  final AnalyticsService _analytics;
  final FixtureUpdateService _fixtureUpdater;
  final RoundsLinkingService _roundsLinking = const RoundsLinkingService();
  final FixtureImportApplier _importApplier = const FixtureImportApplier();
  final KickoffRefreshScheduler _kickoffRefreshScheduler;
  final SelectionInitCoordinator _selectionInit;
  final String? _cloudFunctionsBaseURLOverride;
  final String? Function()? _cloudFunctionsBaseURLProvider;
  final String? Function()? _adminScoringRescoreURLProvider;
  final Future<String?> Function()? _adminScoringRescoreURLLoader;
  final String? Function()? _adminCheckFixtureUrlURLProvider;
  final Future<String?> Function()? _adminCheckFixtureUrlURLLoader;

  final DauCompsRepository _repo;
  final TippersViewModel Function() _tippers;
  static const String _firebaseProjectId = 'dau-footy-tipping-f8a42';
  static const String _fixtureFunctionRegion = 'asia-southeast1';

  DAUCompsViewModel(
    this._initDAUCompDbKey,
    this._adminMode, {
    bool skipInit = false,
    DauCompsRepository? repo,
    FixtureDownloadService? fixtureDownloader,
    AnalyticsService? analytics,
    TippersViewModel Function()? tippers,
    SelectionInitCoordinator? selectionInit,
    UrlHealthChecker? urlHealthChecker,
    String? cloudFunctionsBaseURLOverride,
    String? Function()? cloudFunctionsBaseURLProvider,
    String? Function()? adminScoringRescoreURLProvider,
    Future<String?> Function()? adminScoringRescoreURLLoader,
    String? Function()? adminCheckFixtureUrlURLProvider,
    Future<String?> Function()? adminCheckFixtureUrlURLLoader,
    KickoffRefreshScheduler? kickoffRefreshScheduler,
  })  : _repo = repo ?? FirebaseDauCompsRepository(),
        _fixtureUpdater = FixtureUpdateService(fixtureDownloader ?? FixtureDownloadService()),
        _analytics = analytics ?? FirebaseAnalyticsService(),
        _tippers = tippers ?? (() => di<TippersViewModel>()),
        _selectionInit = selectionInit ?? const SelectionInitCoordinator(),
        _kickoffRefreshScheduler =
            kickoffRefreshScheduler ?? KickoffRefreshScheduler(),
        _cloudFunctionsBaseURLProvider = cloudFunctionsBaseURLProvider,
        _adminScoringRescoreURLProvider = adminScoringRescoreURLProvider,
        _adminScoringRescoreURLLoader = adminScoringRescoreURLLoader,
        _adminCheckFixtureUrlURLProvider = adminCheckFixtureUrlURLProvider,
        _adminCheckFixtureUrlURLLoader = adminCheckFixtureUrlURLLoader,
        _cloudFunctionsBaseURLOverride =
            cloudFunctionsBaseURLOverride ??
            resolveDefaultCloudFunctionsBaseURLOverride() {
    _urlHealthChecker =
        urlHealthChecker ??
        UrlHealthChecker(
          remoteChecker: _checkFixtureUrlActiveViaCloudFunction,
          // On web, a direct fallback would just recreate the browser CORS
          // failure this backend proxy exists to avoid, and misreport a
          // proxy/config outage as "URL not active". Non-web platforms can
          // still fall back to a direct request.
          allowDirectFallback: !kIsWeb,
        );
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
    _clearGroupedGamesCache();
    clearLeagueLadderCache();
  }

  @visibleForTesting
  void completeOtherViewModelsForTest() {
    if (!_otherViewModels.isCompleted) {
      _otherViewModels.complete();
    }
  }

  @visibleForTesting
  void completeInitialDAUCompLoadForTest() {
    if (!_initialDAUCompLoadCompleter.isCompleted) {
      _initialDAUCompLoadCompleter.complete();
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
    _scheduleNextKickoffRefresh();
    notifyListeners();
  }

  Future<void> selectedTipperChanged() async {
    await _initializeAndResetViewModels(false);
    _scheduleNextKickoffRefresh();
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
              () => StatsViewModel(
                comp,
                gamesVm,
              ),
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

        gamesViewModel!.addListener(_gamesViewModelUpdated);
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
      createStatsViewModel: (comp, gamesVm) => StatsViewModel(
        comp,
        gamesVm,
      ),
    );

    gamesViewModel = res.gamesViewModel;
    statsViewModel = res.statsViewModel;

    gamesViewModel!.addListener(_gamesViewModelUpdated);
    statsViewModel!.addListener(_otherViewModelUpdated);
  }

  void _listenToDAUComps() {
    _daucompsStream = _repo.streamDauComps(daucompsPath).listen(_handleEvent);
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('DAUCompsViewModel_handleEvent()');
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
        _clearGroupedGamesCache();

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

  HttpsCallable _adminCallable(
    String functionName,
    String configuredURL, {
    required Duration timeout,
  }) {
    final uri = Uri.parse(configuredURL);
    final isLocalEmulatorUrl = uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' ||
            uri.host == 'localhost' ||
            uri.host == '10.0.2.2');
    final options = HttpsCallableOptions(timeout: timeout);
    if (isLocalEmulatorUrl) {
      final functions = FirebaseFunctions.instanceFor(
        region: _fixtureFunctionRegion,
      );
      functions.useFunctionsEmulator(uri.host, uri.port);
      log(
        'DAUCompsViewModel: using local Functions emulator callable $functionName at ${uri.scheme}://${uri.host}:${uri.port}.',
      );
      return functions.httpsCallable(functionName, options: options);
    }

    log('DAUCompsViewModel: using deployed callable URL $configuredURL.');
    return FirebaseFunctions.instance.httpsCallableFromUrl(
      deployedAdminCallableURL(configuredURL),
      options: options,
    );
  }

  @visibleForTesting
  static String deployedAdminCallableURL(String configuredURL) {
    return Uri.parse(configuredURL).toString();
  }

  Future<String> rescoreWithBackend(DAUComp daucompToUpdate) async {
    var adminScoringRescoreURL = resolveConfiguredAdminScoringRescoreURL();
    if (adminScoringRescoreURL == null) {
      log(
        'DAUCompsViewModel_rescoreWithBackend: configured URL is not cached; refreshing AppConfig.',
      );
      adminScoringRescoreURL = parseCloudFunctionsBaseURLValue(
        await _adminScoringRescoreURLLoader?.call(),
      );
    }
    if (adminScoringRescoreURL == null || adminScoringRescoreURL.isEmpty) {
      throw StateError(
        'Backend scoring is not configured. Set /AppConfig/adminScoringRescoreURL.',
      );
    }

    const functionName = 'admin-scoring-rescore';
    final callable = _adminCallable(
      functionName,
      adminScoringRescoreURL,
      timeout: const Duration(minutes: 6),
    );

    log(
      'DAUCompsViewModel_rescoreWithBackend: triggering $functionName for ${daucompToUpdate.dbkey}.',
    );
    final result = await callable.call(<String, dynamic>{
      'compKey': daucompToUpdate.dbkey,
    });
    return cloudFunctionFixtureDownloadMessage(result.data);
  }

  Future<String> getNetworkFixtureData(
    DAUComp daucompToUpdate, {
    bool useCloudFunction = true,
  }) async {
    _lastFixtureDownloadRanViaCloudFunction = false;
    if (_isDownloading) {
      log('getNetworkFixtureData() is already downloading');
      return 'Fixture data is already downloading';
    }
    await initialDAUCompLoadComplete;
    await otherViewModelsLoadComplete;
    if (gamesViewModel == null) {
      return 'Fixture download is not ready yet. Please try again.';
    }
    if (gamesViewModel!.selectedDAUComp.dbkey != daucompToUpdate.dbkey) {
      final loadedComp = gamesViewModel!.selectedDAUComp;
      final message =
          'Fixture download aborted: loaded games belong to ${loadedComp.name}, not ${daucompToUpdate.name}.';
      log('DAUCompsViewModel_getNetworkFixtureData: $message');
      return message;
    }

    String? cloudFunctionsBaseURL;
    if (useCloudFunction) {
      cloudFunctionsBaseURL = resolveConfiguredCloudFunctionsBaseURL();
      final String configDescription =
          parseCloudFunctionsBaseURLValue(
            _cloudFunctionsBaseURLProvider?.call(),
          ) ??
          '<not set>';
      final String overrideDescription =
          parseCloudFunctionsBaseURLValue(_cloudFunctionsBaseURLOverride) ??
          '<not set>';
      log(
        'DAUCompsViewModel_getNetworkFixtureData: cloudFunctionsBaseURL resolved to ${cloudFunctionsBaseURL ?? '<not set>'} from ConfigViewModel (config=$configDescription, override=$overrideDescription)',
      );
    } else {
      log(
        'DAUCompsViewModel_getNetworkFixtureData: Cloud Function disabled for this call. Falling back to local execution.',
      );
    }

    if (useCloudFunction && cloudFunctionsBaseURL != null && cloudFunctionsBaseURL.isNotEmpty) {
      log('DAUCompsViewModel_getNetworkFixtureData: Triggering backend fixture download via Cloud Function...');
      _isDownloading = true;
      notifyListeners();
      try {
        const functionName = 'admin-fixture-download';
        final callable = _adminCallable(
          functionName,
          cloudFunctionsBaseURL,
          timeout: const Duration(minutes: 2),
        );
        final result = await callable.call(<String, dynamic>{
          'compKey': daucompToUpdate.dbkey,
        });
        final String message = cloudFunctionFixtureDownloadMessage(
          result.data,
        );
        _lastFixtureDownloadRanViaCloudFunction = true;
        log('DAUCompsViewModel_getNetworkFixtureData: Cloud function success: $message');
        return message;
      } catch (e, stackTrace) {
        log('DAUCompsViewModel_getNetworkFixtureData: Cloud Function execution failed: $e.', error: e, stackTrace: stackTrace);
        rethrow;
      } finally {
        _isDownloading = false;
        notifyListeners();
      }
    }

    if (useCloudFunction) {
      log(
        'DAUCompsViewModel_getNetworkFixtureData: Cloud Function not configured. Executing local fixture download...',
      );
    } else {
      log('DAUCompsViewModel_getNetworkFixtureData: Executing local fixture download...');
    }
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

  static String? parseCloudFunctionsBaseURLValue(Object? value) {
    final parsed = _parseOptionalStringLike(value);
    if (parsed == null) {
      return null;
    }

    final uri = Uri.tryParse(parsed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    return parsed;
  }

  static String? resolveCloudFunctionsBaseURLValue({
    required Object? configValue,
    Object? overrideValue,
  }) {
    final override = parseCloudFunctionsBaseURLValue(overrideValue);
    if (override != null) {
      return override;
    }
    return parseCloudFunctionsBaseURLValue(configValue);
  }

  @visibleForTesting
  String? resolveConfiguredCloudFunctionsBaseURL() {
    return resolveCloudFunctionsBaseURLValue(
      configValue: _cloudFunctionsBaseURLProvider?.call(),
      overrideValue: _cloudFunctionsBaseURLOverride,
    );
  }

  @visibleForTesting
  String? resolveConfiguredAdminScoringRescoreURL() {
    return resolveCloudFunctionsBaseURLValue(
      configValue: _adminScoringRescoreURLProvider?.call(),
      overrideValue: _cloudFunctionsBaseURLOverride,
    );
  }

  @visibleForTesting
  String? resolveConfiguredAdminCheckFixtureUrlURL() {
    return resolveCloudFunctionsBaseURLValue(
      configValue: _adminCheckFixtureUrlURLProvider?.call(),
      overrideValue: _cloudFunctionsBaseURLOverride,
    );
  }

  Future<bool> _checkFixtureUrlActiveViaCloudFunction(Uri uri) async {
    var adminCheckFixtureUrlURL = resolveConfiguredAdminCheckFixtureUrlURL();
    adminCheckFixtureUrlURL ??= parseCloudFunctionsBaseURLValue(
      await _adminCheckFixtureUrlURLLoader?.call(),
    );
    if (adminCheckFixtureUrlURL == null || adminCheckFixtureUrlURL.isEmpty) {
      throw StateError(
        'Fixture URL health check backend is not configured. Set /AppConfig/adminCheckFixtureUrlURL.',
      );
    }

    // Must match the deployed entrypoint id exactly (functions_dart/functions.yaml:
    // admin-check-fixture-url — the Dart build tooling kebab-cases the
    // in-source `name: 'adminCheckFixtureUrl'` when generating the Cloud
    // Functions/Cloud Run deployment manifest, since Cloud Run service names
    // must be lowercase-hyphenated). Production uses the full configured URL
    // and ignores this, but the local Functions emulator branch of
    // _adminCallable resolves callables by this literal, deployed name.
    const functionName = 'admin-check-fixture-url';
    final callable = _adminCallable(
      functionName,
      adminCheckFixtureUrlURL,
      timeout: const Duration(seconds: 20),
    );

    log(
      'DAUCompsViewModel_checkFixtureUrlActiveViaCloudFunction: checking $uri via $functionName.',
    );
    final result = await callable.call(<String, dynamic>{'url': uri.toString()});
    final data = result.data;
    if (data is Map && data['active'] is bool) {
      return data['active'] as bool;
    }
    throw StateError(
      'Unexpected $functionName response for $uri: $data',
    );
  }

  static String? resolveDefaultCloudFunctionsBaseURLOverride({
    bool? useFirebaseEmulators,
    String? configuredFirebaseEmulatorHost,
    Object? configuredOverride,
    bool? isDebugMode,
    bool? isWeb,
    TargetPlatform? targetPlatform,
  }) {
    final parsedOverride = parseCloudFunctionsBaseURLValue(
      configuredOverride ??
          const String.fromEnvironment(
            'CLOUD_FUNCTIONS_BASE_URL_OVERRIDE',
            defaultValue: '',
          ),
    );
    if (parsedOverride != null) {
      return parsedOverride;
    }

    final emulatorsEnabled =
        useFirebaseEmulators ??
        const bool.fromEnvironment(
          'USE_FIREBASE_EMULATORS',
          defaultValue: true,
        );
    if (!(isDebugMode ?? kDebugMode) || !emulatorsEnabled) {
      return null;
    }

    final configuredHost =
        configuredFirebaseEmulatorHost ??
        const String.fromEnvironment(
          'FIREBASE_EMULATOR_HOST',
          defaultValue: '',
        );
    final host = configuredHost.isNotEmpty
        ? configuredHost
        : (!(isWeb ?? kIsWeb) &&
              (targetPlatform ?? defaultTargetPlatform) ==
                  TargetPlatform.android)
        ? '10.0.2.2'
        : 'localhost';

    return 'http://$host:9229/$_firebaseProjectId/$_fixtureFunctionRegion';
  }

  @visibleForTesting
  static String cloudFunctionFixtureDownloadMessage(Object? resultData) {
    if (resultData case {'message': final String message}
        when message.isNotEmpty) {
      return message;
    }
    return 'Successfully updated fixtures via Cloud Function';
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
      _scheduleNextKickoffRefresh();
      notifyListeners();
    }
  }

  Future<DAUComp?> findComp(String compDbKey) async {
    await initialDAUCompLoadComplete;
    return _daucomps.firstWhereOrNull((daucomp) => daucomp.dbkey == compDbKey);
  }

  Future<List<DAUComp>> resolveCompsList(List compDbKeys) async {
    await initialDAUCompLoadComplete;
    List<DAUComp> daucompList = [];
    for (var compDbKey in compDbKeys) {
      final DAUComp? daucomp = await findComp(compDbKey);
      if (daucomp == null) {
        log('DAUCompsViewModel.resolveCompsList: compDbKey not found: $compDbKey');
      } else if (daucomp.dbkey == compDbKey) {
        daucompList.add(daucomp);
      }
    }
    return daucompList;
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

  int appBadgeOutstandingTipsCount([DateTime? now]) {
    final comp = _selectedDAUComp;
    final tipsViewModel = selectedTipperTipsViewModel;
    if (comp == null || tipsViewModel == null) {
      return 0;
    }

    final badgeRound = OutstandingTipsCalculator.appBadgeRoundForTime(
      rounds: comp.daurounds,
      now: now ?? DateTime.now().toUtc(),
    );
    if (badgeRound == null) {
      return 0;
    }

    final outstanding =
        tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          badgeRound,
          League.nrl,
        ) +
        tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          badgeRound,
          League.afl,
        );
    return outstanding > 0 ? outstanding : 0;
  }

  void _otherViewModelUpdated() {
    _clearGroupedGamesCache();
    _scheduleNextKickoffRefresh();
    notifyListeners();
  }

  void _scheduleNextKickoffRefresh() {
    _kickoffRefreshScheduler.schedule(
      kickoffTimes: () {
        final rounds = _selectedDAUComp?.daurounds;
        if (rounds == null) {
          return const <DateTime>[];
        }
        return <DateTime>[
          for (final round in rounds) ...<DateTime>[
            round.firstGameKickOffUTC.subtract(
              OutstandingTipsCalculator.appBadgeActivationLeadTime,
            ),
            ...round.games.map((game) => game.startTimeUTC),
          ],
        ];
      },
      onRefresh: () {
        _clearGroupedGamesCache();
        notifyListeners();
      },
    );
  }

  void _gamesViewModelUpdated() {
    clearLeagueLadderCache();
    _leagueLadderRevision.value++;
    _otherViewModelUpdated();
  }

  @visibleForTesting
  void gamesViewModelUpdatedForTest() => _gamesViewModelUpdated();

  /// Disposes child ViewModels (games, stats, tips) before re-initialization
  /// to prevent leaked Firebase stream subscriptions and listeners.
  void _disposeChildViewModels() {
    gamesViewModel?.removeListener(_gamesViewModelUpdated);
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

  @override
  void dispose() {
    _daucompsStream.cancel();
    _kickoffRefreshScheduler.dispose();
    _disposeChildViewModels();
    _leagueLadderRevision.dispose();
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
    if (forceRecalculate) {
      clearLeagueLadderCache(league: league);
    }

    if (_cachedLadders.containsKey(league)) {
      return _cachedLadders[league]!;
    }

    if (_cachedLadderAvailability[league] ==
        LeagueLadderAvailability.insufficientData) {
      return null;
    }

    final inFlightCalculation = _inFlightLadderCalculations[league];
    if (inFlightCalculation != null) {
      return inFlightCalculation;
    }

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
  Future<bool> _isUriActiveIfChanged(String uri, {Uri? previousUri}) async =>
      _urlHealthChecker.isActiveIfChanged(
        Uri.parse(uri),
        previousUri: previousUri,
      );

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
      bool aflURLActive = await _isUriActiveIfChanged(
        aflFixtureJsonURL,
        previousUri: existingComp?.aflFixtureJsonURL,
      );
      bool nrlURLActive = await _isUriActiveIfChanged(
        nrlFixtureJsonURL,
        previousUri: existingComp?.nrlFixtureJsonURL,
      );
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

String? _parseOptionalStringLike(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }

  if (value is Map) {
    final candidates = <Object?>[
      value['value'],
      value['.value'],
      if (value.length == 1) value.values.first,
    ];
    for (final candidate in candidates) {
      final parsed = _parseOptionalStringLike(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    for (final candidate in value.values) {
      final parsed = _parseOptionalStringLike(candidate);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return null;
}
