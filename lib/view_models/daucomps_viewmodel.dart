import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/ladder_calculation_service.dart'; // Added import
import 'package:daufootytipping/models/league_ladder.dart'; // Added import
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:watch_it/watch_it.dart';
import 'package:http/http.dart' as http; // Added for _isUriActive

const daucompsPath = '/AllDAUComps';
const combinedRoundsPath = 'combinedRounds2';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];
  List<DAUComp> get daucomps => _daucomps;
  final fixtureUpdateTimerDuration =
      Duration(hours: 24); // how often we check for fixture updates

  final _db = FirebaseDatabase.instance.ref();
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

  DAUCompsViewModel(this._initDAUCompDbKey, this._adminMode) {
    log('DAUCompsViewModel() created with comp: $_initDAUCompDbKey, adminMode: $_adminMode');
    _init();
  }

  Future<void> _init() async {
    _listenToDAUComps();
    await initialDAUCompLoadComplete;

    if (_initDAUCompDbKey != null) {
      DAUComp? foundComp = await findComp(_initDAUCompDbKey!);
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
          log('No DAUComps found. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');
        }
      } else {
        log('In admin mode');
      }
    }

    _startDailyTimer();
  }

  void _startDailyTimer() {
    // if we are on web, then we don't want to start the daily timer
    if (kIsWeb) {
      return;
    }
    // if we are in admin mode, then we don't want to start the daily timer
    if (_adminMode) {
      return;
    }
    // if role of authenticated tipper is not admin, then we don't want to start the daily timer
    if (di<TippersViewModel>().authenticatedTipper?.tipperRole !=
        TipperRole.admin) {
      log('DAUCompsViewModel_startDailyTimer() Authenticated tipper is not an admin. Daily timer will not be started.');
      return;
    }
    _dailyTimer = Timer.periodic(fixtureUpdateTimerDuration, (timer) {
      triggerDailyEvent();
    });

    // always trigger the daily event when the timer is started
    triggerDailyEvent();
  }

  void triggerDailyEvent() async {
    log("DAUCompsViewModel_triggerDailyEvent()  Daily event triggered at ${DateTime.now()}");
    // make sure we are using the current database state for this comp
    _activeDAUComp = await findComp(_activeDAUComp!.dbkey!);
    // if the last fixture update was more than 24 hours ago, then trigger the fixture update
    if (_activeDAUComp != null &&
        _activeDAUComp!.lastFixtureUpdateTimestampUTC != null &&
        DateTime.now()
                .difference(_activeDAUComp!.lastFixtureUpdateTimestampUTC!)
                .inHours >=
            24) {
      log('DAUCompsViewModel_triggerDailyEvent()  Triggering fixture update');
      _fixtureUpdate();
    } else {
      log('DAUCompsViewModel_triggerDailyEvent() Looks like another client did an update in the last ${fixtureUpdateTimerDuration.inHours} hours. Skipping fixture update.');
    }
  }

  Future<void> changeDisplayedDAUComp(
      DAUComp? changeToDAUComp, bool changingActiveComp) async {
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
      log('Cannot determine current DAUComp. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');
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
    gamesViewModel!.addListener(_otherViewModelUpdated);

    //await the TippersViewModel to be initialized
    await di<TippersViewModel>().initialLoadComplete;

    await di<TippersViewModel>().isUserLinked;

    di.registerLazySingleton<StatsViewModel>(
        () => StatsViewModel(_selectedDAUComp!, gamesViewModel));
    statsViewModel = di<StatsViewModel>();
    statsViewModel!.addListener(_otherViewModelUpdated);

    selectedTipperTipsViewModel = TipsViewModel.forTipper(
        di<TippersViewModel>(),
        _selectedDAUComp!,
        gamesViewModel!,
        di<TippersViewModel>().selectedTipper);
    selectedTipperTipsViewModel!.addListener(_otherViewModelUpdated);
  }

  Future<void> _initializeAdminViewModels() async {
    gamesViewModel = GamesViewModel(_selectedDAUComp!, this);
    gamesViewModel!.addListener(_otherViewModelUpdated);
    statsViewModel = StatsViewModel(_selectedDAUComp!, gamesViewModel);
  }

  void _listenToDAUComps() {
    _daucompsStream = _db.child(daucompsPath).onValue.listen(_handleEvent);
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('DAUCompsViewModel_handleEvent()');
      if (event.snapshot.exists) {
        _processSnapshot(event.snapshot);
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

  void _processSnapshot(DataSnapshot snapshot) {
    final databaseDAUComps =
        Map<String, dynamic>.from(snapshot.value as dynamic);
    Map<String, DAUComp> existingDAUCompsMap = {
      for (var daucomp in _daucomps) daucomp.dbkey!: daucomp
    };

    for (var entry in databaseDAUComps.entries) {
      String key = entry.key;
      dynamic daucompAsJSON = entry.value;
      List<DAURound> daurounds = _parseRounds(daucompAsJSON);

      DAUComp databaseDAUComp = DAUComp.fromJson(
          Map<String, dynamic>.from(daucompAsJSON), key, daurounds);

      // if  databaseDAUComp.aflRegularCompEndDateUTC and databaseDAUComp.nrlRegularCompEndDateUTC are not null
      // calculate the greater of the two and set it as a local variable
      DateTime? greaterEndDate;
      if (databaseDAUComp.aflRegularCompEndDateUTC != null &&
          databaseDAUComp.nrlRegularCompEndDateUTC != null) {
        greaterEndDate = databaseDAUComp.aflRegularCompEndDateUTC!
                .isAfter(databaseDAUComp.nrlRegularCompEndDateUTC!)
            ? databaseDAUComp.aflRegularCompEndDateUTC!
            : databaseDAUComp.nrlRegularCompEndDateUTC!;
      }

      // remove any rounds where the round start date exceeds greaterEndDate
      if (greaterEndDate != null) {
        databaseDAUComp.daurounds.removeWhere((round) {
          return round.getRoundStartDate().isAfter(greaterEndDate!);
        });
      }

      if (existingDAUCompsMap.containsKey(key)) {
        DAUComp existingDAUComp = existingDAUCompsMap[key]!;
        if (existingDAUComp != databaseDAUComp) {
          existingDAUCompsMap[key] = databaseDAUComp;
          log('Updated DAUComp from database: $key');
          // if the active comp is updated, then we need to update the gamesViewModel
          if (existingDAUComp.dbkey == _activeDAUComp?.dbkey) {
            _activeDAUComp = databaseDAUComp;
          }
          // if the selected comp is updated, then we need to update the gamesViewModel
          if (existingDAUComp.dbkey == _selectedDAUComp?.dbkey) {
            _selectedDAUComp = databaseDAUComp;
          }
        }
      } else {
        existingDAUCompsMap[key] = databaseDAUComp;
        log('Initialized DAUComp from database: $key');
      }
    }

    _daucomps = existingDAUCompsMap.values.toList();
  }

  List<DAURound> _parseRounds(dynamic daucompAsJSON) {
    List<DAURound> daurounds = [];
    if (daucompAsJSON[combinedRoundsPath] != null) {
      List<dynamic> combinedRounds = daucompAsJSON[combinedRoundsPath];
      for (var i = 0; i < combinedRounds.length; i++) {
        daurounds.add(DAURound.fromJson(
            Map<String, dynamic>.from(combinedRounds[i]), i + 1));
      }
    }
    return daurounds;
  }

  void _initRoundState(DAURound round) {
    if (round.games.isEmpty) {
      round.roundState = RoundState.noGames;
      log('Round ${round.dAUroundNumber} has no games. Check the fixture data and date ranges for each round.');
      return;
    }

    bool allGamesStarted = round.games.every((game) =>
        game.gameState == GameState.startedResultKnown ||
        game.gameState == GameState.startedResultNotKnown);
    bool allGamesEnded = round.games
        .every((game) => game.gameState == GameState.startedResultKnown);

    if (allGamesEnded) {
      round.roundState = RoundState.allGamesEnded;
    } else if (allGamesStarted) {
      round.roundState = RoundState.started;
    } else {
      round.roundState = RoundState.notStarted;
    }
  }

  Future<void> _fixtureUpdate() async {
    await initialDAUCompLoadComplete;
    await gamesViewModel!.initialLoadComplete;

    if (_activeDAUComp == null) {
      log('_fixtureUpdate() Active comp is null. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');
      return;
    }

    // if selected comp is not the active comp then we don't want to trigger the fixture update
    if (!isSelectedCompActiveComp()) {
      log('_fixtureUpdate() Selected comp ${_selectedDAUComp?.name} is not the active comp. No fixture update will be triggered.');
      return;
    }

    // if we are at the end of the competition, then don't trigger the fixture update
    if (_isCompOver(_activeDAUComp!)) {
      log('_fixtureUpdate() End of competition detected for active comp: ${_activeDAUComp!.name}. Going forward only manual downloads by Admin will trigger an update.');
      return;
    }

    try {
      log('_fixtureUpdate() Starting fixture update for comp: ${_activeDAUComp!.name}');
      // create an analytics event to track the fixture update trigger
      FirebaseAnalytics.instance.logEvent(name: 'fixture_trigger', parameters: {
        'comp': _activeDAUComp!.name,
        'tipperHandlingUpdate':
            di<TippersViewModel>().authenticatedTipper?.name ?? 'unknown tipper'
      });
      await getNetworkFixtureData(_activeDAUComp!);
    }
    // ignore: avoid_catches_without_on_clauses
    catch (e) {
      log('_fixtureUpdateTrigger() Error fetching fixture data: $e');
    }
    // use this daily opportunity to delete stale tokens
    // this is done after the fixture update is complete
    await di<FirebaseMessagingService>()
        .deleteStaleTokens(di<TippersViewModel>());
  }

  Future<bool> _acquireLock(DAUComp daucompToUpdate) async {
    DatabaseReference lockRef =
        _db.child('$daucompsPath/${daucompToUpdate.dbkey}/downloadLock');
    DataSnapshot snapshot = await lockRef.get();

    if (snapshot.exists) {
      DateTime? lockTimestamp;
      if (snapshot.value is String) {
        lockTimestamp = DateTime.tryParse(snapshot.value as String);
      } else {
        lockTimestamp = null;
      }
      if (lockTimestamp != null &&
          DateTime.now().difference(lockTimestamp).inHours < 24) {
        return false; // Lock is already held by another instance
      }
    }

    await lockRef.set(DateTime.now().toIso8601String());
    return true; // Lock acquired successfully
  }

  Future<void> _releaseLock(DAUComp daucompToUpdate) async {
    DatabaseReference lockRef =
        _db.child('$daucompsPath/${daucompToUpdate.dbkey}/downloadLock');
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
      log('getNetworkFixtureData() Another instance is already downloading the fixture data. Skipping download.');
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
        true);
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
      log('DAUCompsViewModel()_fetchAndProcessFixtureData No existing rounds found. Creating $combinedRoundsPath with round start stop times.');
      await _updateRoundStartEndTimesBasedOnFixture(daucompToUpdate, allGames);
    } else {
      log('DAUCompsViewModel()_fetchAndProcessFixtureData Existing rounds found. Skipping updating $combinedRoundsPath round start stop time update.');
    }

    String res =
        'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    FirebaseAnalytics.instance.logEvent(
        name: 'fixture_download',
        parameters: {'comp': daucompToUpdate.name, 'result': res});

    daucompToUpdate.lastFixtureUpdateTimestampUTC = DateTime.now().toUtc();
    updateCompAttribute(daucompToUpdate.dbkey!, 'lastFixtureUTC',
        daucompToUpdate.lastFixtureUpdateTimestampUTC!.toIso8601String());
    await saveBatchOfCompAttributes();

    // if nrlRaw and aflRaw are null then store the raw fixture data in the database for future reference
    if ((daucompToUpdate.nrlBaseline == null ||
            daucompToUpdate.nrlBaseline!.isEmpty) &&
        (daucompToUpdate.aflBaseline == null ||
            daucompToUpdate.aflBaseline!.isEmpty)) {
      _saveBaselineFixtureData(
          fixtures['nrlGames']!, fixtures['aflGames']!, daucompToUpdate);
    }

    return res;
  }

  //store the baseline fixture data in the database - we will use it later to compare
  void _saveBaselineFixtureData(
      List<dynamic> nrlGames, List<dynamic> aflGames, DAUComp daucomp) {
    DatabaseReference nrlRawRef =
        _db.child('$daucompsPath/${daucomp.dbkey}/nrlFixtureBaseline');
    DatabaseReference aflRawRef =
        _db.child('$daucompsPath/${daucomp.dbkey}/aflFixtureBaseline');
    nrlRawRef.set(nrlGames);
    aflRawRef.set(aflGames);
  }

  void _tagGamesWithLeague(List<dynamic> games, String league) {
    for (var game in games) {
      game['league'] = league;
    }
  }

  Future<void> _updateRoundStartEndTimesBasedOnFixture(
      DAUComp daucomp, List<dynamic> rawGames) async {
    await initialDAUCompLoadComplete;

    // Group games by league and round
    Map<String, List<Map<dynamic, dynamic>>> groups =
        _groupGamesByLeagueAndRound(rawGames.cast<Map<dynamic, dynamic>>());

    // Sort game groups by start time and match number
    List<Map<String, Object>?> sortedGameGroups =
        _sortGameGroupsByStartTimeThenMatchNumber(groups);

    // If found, fix any overlapping league game groups
    List<Map<String, dynamic>> fixedGameGroups =
        _fixOverlappingLeagueGameGroups(
            sortedGameGroups.cast<Map<String, dynamic>>());

    // Combine game groups into rounds and update the database
    await _updateCombinedRoundsInDatabase(
        _combineGameGroupsIntoRounds(fixedGameGroups), daucomp);
  }

  Map<String, List<Map<dynamic, dynamic>>> _groupGamesByLeagueAndRound(
      List<Map<dynamic, dynamic>> games) {
    return groupBy(
        games,
        (Map<dynamic, dynamic> rawGame) =>
            '${rawGame["league"]}-${rawGame["RoundNumber"]}');
  }

  Map<String, DateTime> _calculateStartEndTimes(
      List<Map<dynamic, dynamic>> rawGames) {
    var minStartTime = rawGames
        .map((rawGame) => DateTime.parse(rawGame["DateUtc"]))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    var maxStartTime = rawGames
        .map((rawGame) => DateTime.parse(rawGame["DateUtc"]))
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return {'minStartTime': minStartTime, 'maxStartTime': maxStartTime};
  }

  List<Map<String, Object>?> _sortGameGroupsByStartTimeThenMatchNumber(
      Map<String, List<Map<dynamic, dynamic>>> groups) {
    return groups.entries
        .map((e) {
          if (e.value.isEmpty) return null;
          var times = _calculateStartEndTimes(e.value);
          return {
            'league-round': e.key, // Add the key from the passed-in groups
            'games': e.value,
            ...times
          };
        })
        .where((group) => group != null)
        .toList()
      ..sort((a, b) {
        int startTimeCompare = (a!['minStartTime'] as DateTime)
            .compareTo(b!['minStartTime'] as DateTime);
        if (startTimeCompare == 0) {
          return (a['games'] as List<Map>)
              .first['MatchNumber']
              .compareTo((b['games'] as List<Map>).first['MatchNumber']);
        }
        return startTimeCompare;
      });
  }

  List<Map<String, dynamic>> _fixOverlappingLeagueGameGroups(
      List<Map<String, dynamic>> sortedGameGroups) {
    // filter on each league i.e 'nrl-*' then 'afl-*'
    // loop through the groups for that league, if any overlap,
    // modify the end date of the last group, to be just before the start date of the next group
    List<Map<String, dynamic>> fixedGameGroups = [];
    var groupedByLeague =
        groupBy(sortedGameGroups, (Map<String, dynamic> group) {
      return group['league-round'].toString().split('-')[0];
    });
    groupedByLeague.forEach((league, groups) {
      DateTime lastEndDate = DateTime.fromMillisecondsSinceEpoch(0);
      for (var group in groups) {
        DateTime groupStartDate = group['minStartTime'];
        DateTime groupEndDate = group['maxStartTime'];

        if (groupStartDate.isBefore(lastEndDate)) {
          // Adjust the end date of the last fixedGameGroup
          lastEndDate = groupEndDate.subtract(Duration(days: 1, minutes: 1));
          fixedGameGroups.last['maxStartTime'] = groupStartDate.subtract(Duration(
              days: 1,
              minutes:
                  1)); // make this special buffer over 3 hours because later we add a standard 3 hours to the start and end times of each round
          log('Adjusted end date of last group to: ${fixedGameGroups.last['maxStartTime']}');
        } else {
          lastEndDate = groupEndDate;
        }
        fixedGameGroups.add(group);
      }
    });
    // resort the groups by start time
    fixedGameGroups.sort((a, b) {
      return (a['minStartTime'] as DateTime)
          .compareTo(b['minStartTime'] as DateTime);
    });
    return fixedGameGroups;
  }

  List<DAURound> _combineGameGroupsIntoRounds(
      List<Map<String, dynamic>> sortedGameGroups) {
    List<DAURound> combinedRounds = [];
    for (var group in sortedGameGroups) {
      DateTime groupMinStartTime = (group['minStartTime'] as DateTime).toUtc();
      DateTime groupMaxStartTime = (group['maxStartTime'] as DateTime).toUtc();

      if (combinedRounds.isEmpty) {
        combinedRounds.add(DAURound(
            dAUroundNumber: combinedRounds.length + 1,
            firstGameKickOffUTC: groupMinStartTime,
            lastGameKickOffUTC: groupMaxStartTime,
            games: []));
      } else {
        DAURound lastCombinedRound = combinedRounds.last;
        if (groupMinStartTime.isBefore(lastCombinedRound.lastGameKickOffUTC) ||
            groupMinStartTime
                .isAtSameMomentAs(lastCombinedRound.lastGameKickOffUTC)) {
          // extend the combined round to include the overlapping league

          lastCombinedRound.lastGameKickOffUTC =
              groupMaxStartTime.isAfter(lastCombinedRound.lastGameKickOffUTC)
                  ? groupMaxStartTime
                  : lastCombinedRound.lastGameKickOffUTC;
        } else {
          // start a new round
          combinedRounds.add(DAURound(
              dAUroundNumber: combinedRounds.length + 1,
              firstGameKickOffUTC: groupMinStartTime,
              lastGameKickOffUTC: groupMaxStartTime,
              games: []));
        }
      }
    }

    // add a 3 hours buffer to the start and end times of each round - this will cater for minor schedule changes during the year
    for (var round in combinedRounds) {
      round.firstGameKickOffUTC =
          round.firstGameKickOffUTC.subtract(Duration(hours: 3));
      round.lastGameKickOffUTC =
          round.lastGameKickOffUTC.add(Duration(hours: 3));
    }

    return combinedRounds;
  }

  Future<void> _updateCombinedRoundsInDatabase(
      List<DAURound> combinedRounds, DAUComp daucomp) async {
    log('In daucompsviewmodel._updateCombinedRoundsInDatabase()');

    await initialDAUCompLoadComplete;

    // Update combined rounds in a separate batch
    for (var i = 0; i < combinedRounds.length; i++) {
      log('_updateCombinedRoundsInDatabase() Updating round start date: $combinedRoundsPath/$i/roundStartDate');
      updateCompAttribute(
          daucomp.dbkey!,
          '$combinedRoundsPath/$i/roundStartDate',
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(combinedRounds[i].firstGameKickOffUTC).toString()}Z');
      log('_updateCombinedRoundsInDatabase() Updating round end date: $combinedRoundsPath/$i/roundEndDate');
      updateCompAttribute(daucomp.dbkey!, '$combinedRoundsPath/$i/roundEndDate',
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(combinedRounds[i].lastGameKickOffUTC).toString()}Z');
    }

    await saveBatchOfCompAttributes();

    // if daucomp.daurounds.length is greater than combinedRounds.length then we need to remove the extra rounds
    // from the database
    if (daucomp.daurounds.length > combinedRounds.length) {
      for (var i = combinedRounds.length; i < daucomp.daurounds.length; i++) {
        log('_updateCombinedRoundsInDatabase() Removing round: $combinedRoundsPath/$i');
        updateCompAttribute(daucomp.dbkey!, '$combinedRoundsPath/$i', null);
      }
      await saveBatchOfCompAttributes();
    }
  }

  bool _isLinkingGames = false;

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
      await initialDAUCompLoadComplete;

      // Create a local copy of unassignedGames
      List<Game> localUnassignedGames =
          List.from(await gamesViewModel!.getGames());

      for (var round in allRounds) {
        // Assign games to the round
        round.games = await gamesViewModel!.getGamesForRound(round);

        // Initialize the round state
        _initRoundState(round);

        // Remove assigned games from the local unassigned games list
        localUnassignedGames.removeWhere((game) =>
            round.games.any((roundGame) => roundGame.dbkey == game.dbkey));

        // Remove games that exceed the cutoff time for NRL and AFL
        if (_selectedDAUComp!.nrlRegularCompEndDateUTC != null) {
          localUnassignedGames.removeWhere((game) =>
              game.league == League.nrl &&
              game.startTimeUTC
                  .isAfter(_selectedDAUComp!.nrlRegularCompEndDateUTC!));
        }

        if (_selectedDAUComp!.aflRegularCompEndDateUTC != null) {
          localUnassignedGames.removeWhere((game) =>
              game.league == League.afl &&
              game.startTimeUTC
                  .isAfter(_selectedDAUComp!.aflRegularCompEndDateUTC!));
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
      notifyListeners();
    } catch (e) {
      log('Error in linkGamesWithRounds(): $e');
    } finally {
      _isLinkingGames = false;
    }
  }

  Future<DAUComp?> findComp(String compDbKey) async {
    await initialDAUCompLoadComplete;
    return _daucomps.firstWhereOrNull((daucomp) => daucomp.dbkey == compDbKey);
  }

  void updateRoundAttribute(String dauCompDbKey, int roundNumber,
      String attributeName, dynamic attributeValue) {
    log('updateRoundAttribute() called for $dauCompDbKey, $roundNumber, $attributeName, $attributeValue');
    updates['$daucompsPath/$dauCompDbKey/$combinedRoundsPath/${roundNumber - 1}/$attributeName'] =
        attributeValue;
  }

  void updateCompAttribute(
      String dauCompDbKey, String attributeName, dynamic attributeValue) {
    log('updateCompAttribute() called for $dauCompDbKey, $attributeName, $attributeValue');
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
      List<dynamic> nrlGames, List<dynamic> aflGames, DAUComp daucomp) {
    List<Future> gamesFuture = [];

    void processGames(List<dynamic> games, League league) {
      for (var gamejson in games.cast<Map<dynamic, dynamic>>()) {
        String dbkey =
            '${league.name}-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        for (var attribute in gamejson.keys) {
          gamesFuture.add(gamesViewModel!.updateGameAttribute(
              dbkey, attribute, gamejson[attribute], league.name));
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
      statsViewModel?.removeListener(_otherViewModelUpdated);
      statsViewModel!.removeListener(_otherViewModelUpdated);
    }
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

  Future<LeagueLadder?> getOrCalculateLeagueLadder(League league,
      {bool forceRecalculate = false}) async {
    log('DAUCompsViewModel: getOrCalculateLeagueLadder called for ${league.name}, forceRecalculate: $forceRecalculate');

    if (forceRecalculate) {
      clearLeagueLadderCache(league: league);
    }

    if (_cachedLadders.containsKey(league)) {
      log('DAUCompsViewModel: Cache hit for ${league.name} ladder.');
      return _cachedLadders[league]!;
    }

    log('DAUCompsViewModel: Cache miss for ${league.name} ladder. Proceeding to calculate.');

    if (selectedDAUComp == null) {
      log('DAUCompsViewModel: Cannot calculate ladder, selectedDAUComp is null.');
      return null;
    }

    // Use the class member gamesViewModel directly, which is initialized with selectedDAUComp
    if (gamesViewModel == null) {
      log('DAUCompsViewModel: Cannot calculate ladder, gamesViewModel is null for DAUComp ${selectedDAUComp?.name}.');
      return null;
    }

    // gamesViewModel.getGames() already awaits initialLoadComplete within itself.
    // gamesViewModel.teamsViewModel.initialLoadComplete is also handled within gamesViewModel init.

    try {
      List<Game> allGames = await gamesViewModel!.getGames();
      // Accessing teamsViewModel through the initialized gamesViewModel instance
      List<Team> leagueTeams = gamesViewModel!
              .teamsViewModel.groupedTeams[league.name.toLowerCase()]
              ?.cast<Team>() ??
          [];

      final LadderCalculationService ladderService = LadderCalculationService();
      LeagueLadder? calculatedLadder = ladderService.calculateLadder(
        allGames: allGames,
        leagueTeams: leagueTeams,
        league: league,
      );

      if (calculatedLadder != null) {
        _cachedLadders[league] = calculatedLadder;
        log('DAUCompsViewModel: Calculated and cached ladder for ${league.name}. Teams count: ${calculatedLadder.teams.length}');
      } else {
        log('DAUCompsViewModel: Ladder calculation returned null for ${league.name}.');
      }
      return calculatedLadder;
    } catch (e) {
      log('DAUCompsViewModel: Error calculating ladder for ${league.name}: $e');
      return null;
    }
  }

  // Added for Step 1 of refactoring
  Future<bool> _isUriActive(String uri) async {
    try {
      final response = await http.get(Uri.parse(uri));
      if (response.statusCode == 200) {
        return true;
      } else {
        log('Error checking URL: $uri, status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      log('Exception checking URL: $uri, error: $e');
      return false;
    }
  }

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
            nrlRegularCompEndDateUTC: nrlRegularCompEndDateString != null &&
                    nrlRegularCompEndDateString.isNotEmpty
                ? DateTime.parse(nrlRegularCompEndDateString)
                : null,
            aflRegularCompEndDateUTC: aflRegularCompEndDateString != null &&
                    aflRegularCompEndDateString.isNotEmpty
                ? DateTime.parse(aflRegularCompEndDateString)
                : null,
            daurounds: [], // Initial empty rounds
          );

          await this
              .newDAUComp(newDAUComp); // 'this.' to clarify it's the VM method
          await saveBatchOfCompAttributes();

          // Initialize GamesViewModel for the new comp
          // Ensure 'this' is passed if DAUCompsViewModel instance is needed by GamesViewModel constructor
          gamesViewModel = GamesViewModel(newDAUComp, this);
          await gamesViewModel?.initialLoadComplete;

          String fixtureMessage = await getNetworkFixtureData(newDAUComp);
          return {
            'success': true,
            'message': fixtureMessage,
            'newCompData': newDAUComp
          };
        } else {
          // Existing comp
          updateCompAttribute(existingComp.dbkey!, "name", name);
          updateCompAttribute(
              existingComp.dbkey!, "aflFixtureJsonURL", aflFixtureJsonURL);
          updateCompAttribute(
              existingComp.dbkey!, "nrlFixtureJsonURL", nrlFixtureJsonURL);
          updateCompAttribute(
              existingComp.dbkey!,
              "nrlRegularCompEndDateUTC",
              nrlRegularCompEndDateString != null &&
                      nrlRegularCompEndDateString.isNotEmpty
                  ? DateTime.parse(nrlRegularCompEndDateString)
                      .toIso8601String()
                  : null);
          updateCompAttribute(
              existingComp.dbkey!,
              "aflRegularCompEndDateUTC",
              aflRegularCompEndDateString != null &&
                      aflRegularCompEndDateString.isNotEmpty
                  ? DateTime.parse(aflRegularCompEndDateString)
                      .toIso8601String()
                  : null);

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
                  round.adminOverrideRoundStartDate!.toUtc().toIso8601String());
            }
            if (round.adminOverrideRoundEndDate != null) {
              updateRoundAttribute(
                  existingComp.dbkey!,
                  round.dAUroundNumber,
                  "adminOverrideRoundEndDate",
                  round.adminOverrideRoundEndDate!.toUtc().toIso8601String());
            }
          }
          await saveBatchOfCompAttributes();
          return {
            'success': true,
            'message': 'DAUComp record saved',
            'newCompData': null
          };
        }
      } else {
        return {
          'success': false,
          'message': 'One or both of the URL\'s are not active',
          'newCompData': null
        };
      }
    } catch (e) {
      log('Error in processAndSaveDauComp: $e');
      return {
        'success': false,
        'message': 'Failed to save DAUComp: ${e.toString()}',
        'newCompData': null
      };
    }
  }
}
