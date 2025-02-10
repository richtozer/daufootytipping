import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:watch_it/watch_it.dart';

const daucompsPath = '/AllDAUComps';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];
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

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  final bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  GamesViewModel? gamesViewModel;
  StatsViewModel? statsViewModel;
  TipsViewModel? selectedTipperTipsViewModel;

  ItemScrollController itemScrollController = ItemScrollController();
  final Map<String, dynamic> updates = {};
  final bool _adminMode;
  bool get adminMode => _adminMode;

  DAUCompsViewModel(this._initDAUCompDbKey, this._adminMode) {
    _init();
    log('DAUCompsViewModel() created with comp: $_initDAUCompDbKey, adminMode: $_adminMode');
  }

  Future<void> _init() async {
    _listenToDAUComps();
    await initialLoadComplete;

    if (_initDAUCompDbKey != null) {
      DAUComp? foundComp = await findComp(_initDAUCompDbKey!);
      if (foundComp != null) {
        _activeDAUComp = foundComp;
        await changeDisplayedDAUComp(foundComp, false);
      }
    } else {
      // if no comp is set as the active comp then we will default to the first comp in the list
      _activeDAUComp = _daucomps.first;
      if (_activeDAUComp != null) {
        await changeDisplayedDAUComp(_daucomps.first, false);
      } else {
        log('No DAUComps found. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');
      }
    }
    notifyListeners();
  }

  Future<void> changeDisplayedDAUComp(
      DAUComp newDAUComp, bool changingActiveComp) async {
    if (!_adminMode) _selectedDAUComp = newDAUComp;

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
  }

  Future<void> _initializeUserViewModels() async {
    await initialLoadComplete;

    gamesViewModel = GamesViewModel(_selectedDAUComp!, this);
    gamesViewModel!.addListener(_otherViewModelUpdated);

    await di<TippersViewModel>().isUserLinked;

    di.registerLazySingleton<StatsViewModel>(
        () => StatsViewModel(_selectedDAUComp!, gamesViewModel));
    statsViewModel = di<StatsViewModel>();
    statsViewModel!.addListener(_otherViewModelUpdated);

    selectedTipperTipsViewModel = TipsViewModel.forTipper(
        di<TippersViewModel>(),
        _selectedDAUComp!,
        gamesViewModel!,
        di<TippersViewModel>().selectedTipper!);
    selectedTipperTipsViewModel!.addListener(_otherViewModelUpdated);
  }

  Future<void> _initializeAdminViewModels() async {
    gamesViewModel = GamesViewModel(_activeDAUComp!, this);
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

      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }

      notifyListeners();
    } catch (e) {
      log('Error listening to $daucompsPath: $e');
      rethrow;
    }
  }

  void _processSnapshot(DataSnapshot snapshot) {
    final allDAUComps = Map<String, dynamic>.from(snapshot.value as dynamic);
    Map<String, DAUComp> existingDAUCompsMap = {
      for (var daucomp in _daucomps) daucomp.dbkey!: daucomp
    };

    for (var entry in allDAUComps.entries) {
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
          return round.roundStartDate.isAfter(greaterEndDate!);
        });
      }

      if (existingDAUCompsMap.containsKey(key)) {
        DAUComp existingDAUComp = existingDAUCompsMap[key]!;
        if (existingDAUComp != databaseDAUComp) {
          existingDAUCompsMap[key] = databaseDAUComp;
          log('Updated DAUComp from database: $key');
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
    if (daucompAsJSON['combinedRounds'] != null) {
      List<dynamic> combinedRounds = daucompAsJSON['combinedRounds'];
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

  static Duration _fixtureUpdateTriggerDelay(DateTime lastUpdate) {
    DateTime nextUpdate = lastUpdate.add(const Duration(days: 1));
    DateTime timeUntilNewDay = DateTime.utc(
        nextUpdate.year, nextUpdate.month, nextUpdate.day, 19, 0, 0, 0, 0);
    return timeUntilNewDay.toUtc().difference(DateTime.now().toUtc());
  }

  Future<void> fixtureUpdateTrigger() async {
    await initialLoadComplete;

    if (_activeDAUComp == null) {
      log('_fixtureUpdateTrigger() Active comp is null. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');
      return;
    }

    // do not use trigger when in admin mode
    if (_adminMode) {
      log('fixtureUpdateTrigger() Admin mode detected. No automated trigger setup for ${_activeDAUComp!.name}.');
      return;
    }

    // if we are at the end of the competition, then don't trigger the fixture update
    if (_isCompOver(_activeDAUComp!)) {
      log('_fixtureUpdateTrigger() End of competition detected for active comp: ${_activeDAUComp!.name}. Going forward only manual downloads by Admin will trigger an update.');
      return;
    }

    DateTime? lastUpdate = _activeDAUComp!.lastFixtureUpdateTimestampUTC ??
        DateTime.utc(2021, 1, 1);
    Duration timeUntilNewDay = _fixtureUpdateTriggerDelay(lastUpdate);

    log('_fixtureUpdateTrigger() Waiting for fixture update trigger at ${DateTime.now().toUtc().add(timeUntilNewDay)}');
    await Future.delayed(timeUntilNewDay);
    log('_fixtureUpdateTrigger() Fixture update delay has elapsed ${DateTime.now().toUtc()}.');

    // Try to acquire the lock
    bool lockAcquired = await _acquireLock();
    if (!lockAcquired) {
      log('_fixtureUpdateTrigger() Another instance is already downloading the fixture data. Skipping download.');
      return;
    }

    try {
      log('_fixtureUpdateTrigger() Starting fixture update for comp: ${_activeDAUComp!.name}');
      // create an analytics event to track the fixture update trigger
      FirebaseAnalytics.instance.logEvent(name: 'fixture_trigger', parameters: {
        'comp': _activeDAUComp!.name,
        'tipperHandlingUpdate':
            di<TippersViewModel>().authenticatedTipper?.name ?? 'unknown tipper'
      });
      await getNetworkFixtureData(_activeDAUComp!);
    } finally {
      // Release the lock
      await _releaseLock();
    }
  }

  Future<bool> _acquireLock() async {
    DatabaseReference lockRef =
        _db.child('$daucompsPath/${_activeDAUComp!.dbkey}/fixtureDownloadLock');
    DataSnapshot snapshot = await lockRef.get();

    if (snapshot.exists && snapshot.value == true) {
      return false; // Lock is already held by another instance
    }

    await lockRef.set(true);
    return true; // Lock acquired successfully
  }

  Future<void> _releaseLock() async {
    DatabaseReference lockRef =
        _db.child('$daucompsPath/${_activeDAUComp!.dbkey}/fixtureDownloadLock');
    await lockRef.set(false);
  }

  Future<String> getNetworkFixtureData(DAUComp daucompToUpdate) async {
    if (_isDownloading) {
      log('getNetworkFixtureData() is already downloading');
      return 'Fixture data is already downloading';
    }

    await initialLoadComplete;

    // acquire lock
    bool lockAcquired = await _acquireLock();

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
      await _releaseLock();
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

    await Future.wait(_processGames(nrlGames, aflGames));
    await gamesViewModel!.saveBatchOfGameAttributes();

    _tagGamesWithLeague(nrlGames, 'nrl');
    _tagGamesWithLeague(aflGames, 'afl');

    List<dynamic> allGames = nrlGames + aflGames;

    await _updateRoundStartEndTimesBasedOnFixture(daucompToUpdate, allGames);

    String res =
        'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    FirebaseAnalytics.instance.logEvent(
        name: 'fixture_download',
        parameters: {'comp': daucompToUpdate.name, 'result': res});

    daucompToUpdate.lastFixtureUpdateTimestampUTC = DateTime.now().toUtc();
    updateCompAttribute(daucompToUpdate.dbkey!, 'lastFixtureUpdateTimestamp',
        daucompToUpdate.lastFixtureUpdateTimestampUTC!.toIso8601String());
    await saveBatchOfCompAttributes();

    if (daucompToUpdate.dbkey != _activeDAUComp!.dbkey!) {
      log('getNetworkFixtureData() Changing selected comp back to $_activeDAUComp.name');
      await changeDisplayedDAUComp(daucompToUpdate, false);
    }

    return res;
  }

  void _tagGamesWithLeague(List<dynamic> games, String league) {
    for (var game in games) {
      game['league'] = league;
    }
  }

  Future<void> _updateRoundStartEndTimesBasedOnFixture(
      DAUComp daucomp, List<dynamic> rawGames) async {
    await initialLoadComplete;

    Map<String, List<Map<dynamic, dynamic>>> groups =
        _groupGamesByLeagueAndRound(rawGames.cast<Map<dynamic, dynamic>>());
    List<Map<String, Object>?> sortedGameGroups =
        _sortGameGroupsByStartTimeThenMatchNumber(groups);

    await _updateDatabaseWithCombinedRounds(
        _combineGameGroupsIntoRounds(
            sortedGameGroups.cast<Map<String, dynamic>>()),
        daucomp);
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
          return {'games': e.value, ...times};
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

  List<DAURound> _combineGameGroupsIntoRounds(
      List<Map<String, dynamic>> sortedGameGroups) {
    List<DAURound> combinedRounds = [];
    for (var group in sortedGameGroups) {
      DateTime groupMinStartTime = (group['minStartTime'] as DateTime).toUtc();
      DateTime groupMaxStartTime = (group['maxStartTime'] as DateTime).toUtc();

      if (combinedRounds.isEmpty) {
        combinedRounds.add(DAURound(
            dAUroundNumber: combinedRounds.length + 1,
            roundStartDate: groupMinStartTime,
            roundEndDate: groupMaxStartTime,
            games: []));
      } else {
        DAURound lastRound = combinedRounds.last;
        if (groupMinStartTime.isBefore(lastRound.roundEndDate) ||
            groupMinStartTime.isAtSameMomentAs(lastRound.roundEndDate)) {
          lastRound.roundEndDate =
              groupMaxStartTime.isAfter(lastRound.roundEndDate)
                  ? groupMaxStartTime
                  : lastRound.roundEndDate;
        } else {
          combinedRounds.add(DAURound(
              dAUroundNumber: combinedRounds.length + 1,
              roundStartDate: groupMinStartTime,
              roundEndDate: groupMaxStartTime,
              games: []));
        }
      }
    }
    return combinedRounds;
  }

  Future<void> _updateDatabaseWithCombinedRounds(
      List<DAURound> combinedRounds, DAUComp daucomp) async {
    log('In _updateDatabaseWithCombinedRounds()');

    await initialLoadComplete;

    // Update combined rounds in a separate batch
    for (var i = 0; i < combinedRounds.length; i++) {
      log('Updating round start date: combinedRounds/$i/roundStartDate');
      updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i/roundStartDate',
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(combinedRounds[i].roundStartDate).toString()}Z');
      log('Updating round end date: combinedRounds/$i/roundEndDate');
      updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i/roundEndDate',
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(combinedRounds[i].roundEndDate).toString()}Z');
    }

    await saveBatchOfCompAttributes();

    // if daucomp.daurounds.length is greater than combinedRounds.length then we need to remove the extra rounds
    // from the database
    if (daucomp.daurounds.length > combinedRounds.length) {
      for (var i = combinedRounds.length; i < daucomp.daurounds.length; i++) {
        log('Removing round: combinedRounds/$i');
        updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i', null);
      }
      await saveBatchOfCompAttributes();
    }
  }

  Future<void> linkGameWithRounds(
      DAUComp daucompToUpdate, GamesViewModel gamesViewModel) async {
    log('In daucompsviewmodel.linkGameWithRounds()');

    await initialLoadComplete;

    for (var round in daucompToUpdate.daurounds) {
      round.games = await gamesViewModel.getGamesForRound(round);
      _initRoundState(round);
    }
  }

  Future<DAUComp?> findComp(String compDbKey) async {
    await initialLoadComplete;
    return _daucomps.firstWhereOrNull((daucomp) => daucomp.dbkey == compDbKey);
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
    await initialLoadComplete;
    log('Saving batch of ${updates.length} DAUComp database updates');
    await _db.update(updates);
    _savingDAUComp = false;
  }

  Future<List<DAUComp>> getDAUcomps() async {
    await initialLoadComplete;
    return _daucomps;
  }

  Map<League, List<Game>> groupGamesIntoLeagues(DAURound combinedRound) {
    //await initialLoadComplete;
    //await gamesViewModel!.initialLoadComplete;

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

  List<Future> _processGames(List<dynamic> nrlGames, List<dynamic> aflGames) {
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
    _daucompsStream.cancel();

    // remove listeners if not in admin mode
    if (!_adminMode) {
      statsViewModel?.removeListener(_otherViewModelUpdated);
      gamesViewModel?.removeListener(_otherViewModelUpdated);
      statsViewModel!.removeListener(_otherViewModelUpdated);
    }

    super.dispose();
  }
}
