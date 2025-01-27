import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
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
  String? _activeDAUCompDbKey;
  DAUComp? _activeDAUComp;
  DAUComp? get activeDAUComp =>
      _activeDAUComp; // this is the comp flagged by admins in the daucomp list as the active comp

  DAUComp? _selectedDAUComp;
  DAUComp? get selectedDAUComp =>
      _selectedDAUComp; // if the user has paid for previous comps, then this is the comp they are currently viewing

  bool _savingDAUComp = false;
  bool get savingDAUComp => _savingDAUComp;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  final bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  GamesViewModel? gamesViewModel;
  StatsViewModel? tipperScoresViewModel;
  TipsViewModel? tipperTipsViewModel;

  ItemScrollController itemScrollController = ItemScrollController();
  final Map<String, dynamic> updates = {};

  DAUCompsViewModel(this._activeDAUCompDbKey) {
    _init();
  }

  Future<void> _init() async {
    _listenToDAUComps();
    await initialLoadComplete;

    if (_activeDAUCompDbKey != null) {
      DAUComp? comp = await findComp(_activeDAUCompDbKey!);
      if (comp != null) {
        await changeSelectedDAUComp(comp.dbkey!, true);
      }
    }
  }

  Future<void> changeSelectedDAUComp(
      String newDAUCompDbkey, bool changingActiveComp) async {
    _selectedDAUComp = await findComp(newDAUCompDbkey);
    if (_selectedDAUComp == null) {
      log('Cannot find DAUComp with dbkey: $newDAUCompDbkey');
      return;
    }
    if (changingActiveComp) {
      _activeDAUCompDbKey = newDAUCompDbkey;
      _activeDAUComp = _selectedDAUComp;
    }

    await _initializeAndResetViewModels();
    notifyListeners();
  }

  Future<void> selectedTipperChanged() async {
    await _initializeAndResetViewModels();
    notifyListeners();
  }

  bool isSelectedCompActiveComp() {
    return _selectedDAUComp == _activeDAUComp;
  }

  Future<void> _initializeAndResetViewModels() async {
    if (di<DAUCompsViewModel>()._selectedDAUComp == null) {
      log('Cannot determine current DAUComp. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');
      return;
    }

    await initialLoadComplete;
    di.registerLazySingleton<StatsViewModel>(
        () => StatsViewModel(_selectedDAUComp!));

    gamesViewModel = GamesViewModel(_selectedDAUComp!);
    gamesViewModel!.addListener(_otherViewModelUpdated);

    await di<TippersViewModel>().isUserLinked;
    Tipper currentTipper = di<TippersViewModel>().selectedTipper!;

    tipperTipsViewModel = TipsViewModel.forTipper(
        di<TippersViewModel>(),
        di<DAUCompsViewModel>().selectedDAUComp!,
        gamesViewModel!,
        currentTipper);
    tipperTipsViewModel!.addListener(_otherViewModelUpdated);

    tipperScoresViewModel = di<StatsViewModel>();
    tipperScoresViewModel!.addListener(_otherViewModelUpdated);
  }

  void _listenToDAUComps() {
    _daucompsStream = _db.child(daucompsPath).onValue.listen(_handleEvent);
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('DAUCompsViewModel_handleEvent()');
      if (event.snapshot.exists) {
        final allDAUComps =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);
        Map<String, DAUComp> existingDAUCompsMap = {
          for (var daucomp in _daucomps) daucomp.dbkey!: daucomp
        };

        for (var entry in allDAUComps.entries) {
          String key = entry.key;
          dynamic daucompAsJSON = entry.value;
          List<DAURound> daurounds = [];

          if (daucompAsJSON['combinedRounds'] != null) {
            List<dynamic> combinedRounds = daucompAsJSON['combinedRounds'];
            for (var i = 0; i < combinedRounds.length; i++) {
              daurounds.add(DAURound.fromJson(
                  Map<String, dynamic>.from(combinedRounds[i]), i + 1));
            }
          }

          DAUComp databaseDAUComp = DAUComp.fromJson(
              Map<String, dynamic>.from(daucompAsJSON), key, daurounds);

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

  // method to setup a potential trigger to periodically update the active comp fixture data
  // this method will delay until elapsed time has passed
  Future<void> fixtureUpdateTrigger() async {
    await initialLoadComplete;

    if (_activeDAUComp == null) {
      log('_fixtureUpdateTrigger() Active comp is null. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');
      return;
    }

    // if we are at the end of the competition, then don't trigger the fixture update
    if (_isCompOver(_activeDAUComp!)) {
      log('End of competition detected for active comp: ${_activeDAUComp!.name}. Going forward only manual downloads by Admin will trigger an update.');
      return;
    }

    DateTime? lastUpdate = _activeDAUComp!.lastFixtureUpdateTimestampUTC ??
        DateTime.utc(2021, 1, 1);
    Duration timeUntilNewDay = _fixtureUpdateTriggerDelay(lastUpdate);

    log('Waiting for fixture update trigger at ${DateTime.now().toUtc().add(timeUntilNewDay)}');
    await Future.delayed(timeUntilNewDay);
    log('Fixture update delay has elapsed ${DateTime.now().toUtc()}.');

    // create an analytics event to track the fixture update trigger
    FirebaseAnalytics.instance
        .logEvent(name: 'fixture_update_trigger', parameters: {
      'comp': _activeDAUComp!.name,
      'tipperHandlingUpdate':
          di<TippersViewModel>().authenticatedTipper?.name ?? 'unknown tipper'
    });

    if (_activeDAUComp!.lastFixtureUpdateTimestampUTC == lastUpdate ||
        _activeDAUComp!.lastFixtureUpdateTimestampUTC == null) {
      log('Starting fixture update for comp: ${_activeDAUComp!.name}');
      await getNetworkFixtureData(_activeDAUComp!);
    } else {
      log('Fixture update has already been triggered for active comp: ${_activeDAUComp!.name}. Skipping');
    }
  }

  Future<String> getNetworkFixtureData(DAUComp daucompToUpdate) async {
    if (_isDownloading) {
      log('getNetworkFixtureData() is already downloading');
      return 'Fixture data is already downloading';
    }

    await initialLoadComplete;

    _isDownloading = true;
    notifyListeners();

    // if the comp being updated is not the active comp then we need to reset the viewmodels
    if (daucompToUpdate.dbkey != _activeDAUCompDbKey) {
      log('getNetworkFixtureData() Changing selected comp to ${daucompToUpdate.name}');
      await changeSelectedDAUComp(daucompToUpdate.dbkey!, false);
    }

    FixtureDownloadService fetcher = FixtureDownloadService();

    try {
      Map<String, List<dynamic>> fixtures = await fetcher.fetch(
          daucompToUpdate.nrlFixtureJsonURL,
          daucompToUpdate.aflFixtureJsonURL,
          true);
      List<dynamic> nrlGames = fixtures['nrlGames']!;
      List<dynamic> aflGames = fixtures['aflGames']!;

      await Future.wait(_processGames(nrlGames, aflGames));
      await gamesViewModel!.saveBatchOfGameAttributes();

      // tag each game with the league
      for (var game in nrlGames) {
        game['league'] = 'nrl';
      }
      for (var game in aflGames) {
        game['league'] = 'afl';
      }

      List<dynamic> allGames = nrlGames + aflGames;

      await _updateRoundStartEndTimesBasedOnFixture(daucompToUpdate, allGames);

      String res =
          'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
      FirebaseAnalytics.instance.logEvent(
          name: 'fixture_update',
          parameters: {'comp': daucompToUpdate.name, 'result': res});

      daucompToUpdate.lastFixtureUpdateTimestampUTC = DateTime.now().toUtc();
      updateCompAttribute(daucompToUpdate.dbkey!, 'lastFixtureUpdateTimestamp',
          daucompToUpdate.lastFixtureUpdateTimestampUTC!.toIso8601String());
      await saveBatchOfCompAttributes();

      // if the comp being updated is not the active comp then we need to reset the viewmodels back
      if (daucompToUpdate.dbkey != _activeDAUCompDbKey) {
        log('getNetworkFixtureData() Changing selected comp back to $_activeDAUCompDbKey');
        await changeSelectedDAUComp(_activeDAUCompDbKey!, true);
      }

      return res;
    } catch (e) {
      log('Error fetching fixture data: $e');
      rethrow;
    } finally {
      _isDownloading = false;
      notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  Future<List<DAUComp>> getDAUcomps() async {
    await initialLoadComplete;
    return _daucomps;
  }

  Future<List<DAURound>> getCombinedRounds() async {
    await initialLoadComplete;
    return _selectedDAUComp!.daurounds;
  }

  Map<League, List<Game>> sortGamesIntoLeagues(DAURound combinedRound) {
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

  Future<String> getDefaultTipsForCombinedRoundNumber(
      DAURound combinedRound) async {
    await initialLoadComplete;

    Map<League, List<Game>> gamesForCombinedRoundNumber =
        sortGamesIntoLeagues(combinedRound);

    List<Game> filteredNrlGames = gamesForCombinedRoundNumber[League.nrl]!;
    List<Game> filteredAflGames = gamesForCombinedRoundNumber[League.afl]!;

    String defaultRoundNrlTips = 'D' * filteredNrlGames.length;
    defaultRoundNrlTips = defaultRoundNrlTips.padRight(8, 'z');

    String defaultRoundAflTips = 'D' * filteredAflGames.length;
    defaultRoundAflTips = defaultRoundAflTips.padRight(9, 'z');

    return defaultRoundNrlTips + defaultRoundAflTips;
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
    tipperScoresViewModel!.removeListener(_otherViewModelUpdated);

    gamesViewModel?.removeListener(_otherViewModelUpdated);

    tipperScoresViewModel = di<StatsViewModel>();
    tipperScoresViewModel!.removeListener(_otherViewModelUpdated);

    super.dispose();
  }
}
