import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
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
  String _activeDAUCompDbKey;
  DAUComp? _activeDAUComp;
  DAUComp? get activeDAUComp => _activeDAUComp;

  DAUComp? _selectedDAUComp;
  DAUComp? get selectedDAUComp => _selectedDAUComp;

  bool _savingDAUComp = false;
  bool get savingDAUComp => _savingDAUComp;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  ScoresViewModel? tipperScoresViewModel;

  TipsViewModel? tipperTipsViewModel;

  ItemScrollController itemScrollController = ItemScrollController();
  final Map<String, dynamic> updates = {};

  DAUCompsViewModel(this._activeDAUCompDbKey) {
    init();
  }

  Future<void> init() async {
    _listenToDAUComps();
    await initialLoadComplete;
    await changeSelectedDAUComp(_activeDAUCompDbKey, true);
    _fixtureUpdateTrigger();
  }

  Future<void> changeSelectedDAUComp(
      String newDAUCompDbkey, bool changingActiveComp) async {
    _selectedDAUComp = await findComp(newDAUCompDbkey);
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

  Future<void> _initializeAndResetViewModels() async {
    await initialLoadComplete;
    di.registerLazySingleton<ScoresViewModel>(
        () => ScoresViewModel(_selectedDAUComp!));

    di.registerLazySingleton<GamesViewModel>(
        () => GamesViewModel(_selectedDAUComp!));

    // get the current selected tipper from the TipperViewModel
    await di<TippersViewModel>().isUserLinked;
    Tipper currentTipper = di<TippersViewModel>().selectedTipper!;

    tipperTipsViewModel = TipsViewModel.forTipper(
        di<TippersViewModel>(),
        di<DAUCompsViewModel>().selectedDAUComp!,
        di<GamesViewModel>(),
        currentTipper);
    tipperTipsViewModel!.addListener(_otherViewModelUpdated);

    GamesViewModel gamesViewModel = di<GamesViewModel>();
    gamesViewModel.addListener(_otherViewModelUpdated);

    tipperScoresViewModel = di<ScoresViewModel>();
    tipperScoresViewModel!.addListener(_otherViewModelUpdated);
  }

  void _listenToDAUComps() {
    _daucompsStream = _db.child(daucompsPath).onValue.listen(_handleEvent);
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('***DAUCompsViewModel_handleEvent()***');
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

        if (!_initialLoadCompleter.isCompleted) {
          _initialLoadCompleter.complete();
        }
      } else {
        log('No DAUComps found at database location: $daucompsPath');
        _daucomps = [];
      }

      notifyListeners();
    } catch (e) {
      log('Error listening to $daucompsPath: $e');
      rethrow;
    }
  }

  void _setRoundState(DAURound round) {
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

  Future<void> _fixtureUpdateTrigger() async {
    await initialLoadComplete;

    if (_selectedDAUComp == null) {
      log('Cannot determine current DAUComp. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');
      return;
    }

    DateTime? lastUpdate = _selectedDAUComp!.lastFixtureUpdateTimestamp ??
        DateTime.utc(2021, 1, 1);
    Duration timeUntilNewDay = _fixtureUpdateTriggerDelay(lastUpdate);

    log('Waiting for fixture update trigger at ${DateTime.now().toUtc().add(timeUntilNewDay)}');
    await Future.delayed(timeUntilNewDay);
    log('Fixture update delay has elapsed ${DateTime.now().toUtc()}.');

    if (_selectedDAUComp!.lastFixtureUpdateTimestamp == lastUpdate ||
        _selectedDAUComp!.lastFixtureUpdateTimestamp == null) {
      log('Starting fixture update for comp: ${_selectedDAUComp!.name}');
      await getNetworkFixtureData(_selectedDAUComp!, di<GamesViewModel>());
    } else {
      log('Fixture update has already been triggered for comp: ${_selectedDAUComp!.name}. Skipping');
    }
  }

  Future<String> getNetworkFixtureData(
      DAUComp daucompToUpdate, GamesViewModel? gamesViewModel) async {
    if (_isDownloading) {
      log('getNetworkFixtureData() is already downloading');
      return 'Fixture data is already downloading';
    }

    await initialLoadComplete;

    _isDownloading = true;
    notifyListeners();

    FixtureDownloadService fetcher = FixtureDownloadService();

    try {
      Map<String, List<dynamic>> fixtures = await fetcher.fetch(
          daucompToUpdate.nrlFixtureJsonURL,
          daucompToUpdate.aflFixtureJsonURL,
          true);
      List<dynamic> nrlGames = fixtures['nrlGames']!;
      List<dynamic> aflGames = fixtures['aflGames']!;

      await Future.wait(_processGames(nrlGames, aflGames, gamesViewModel));
      await gamesViewModel!.saveBatchOfGameAttributes();
      await _updateRoundStartEndTimesBasedOnFixture(
          daucompToUpdate, gamesViewModel);

      String res =
          'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
      FirebaseAnalytics.instance.logEvent(
          name: 'fixture_update',
          parameters: {'comp': selectedDAUComp!.name, 'result': res});

      selectedDAUComp!.lastFixtureUpdateTimestamp = DateTime.now().toUtc();
      updateCompAttribute(selectedDAUComp!.dbkey!, 'lastFixtureUpdateTimestamp',
          selectedDAUComp!.lastFixtureUpdateTimestamp!.toIso8601String());
      await saveBatchOfCompAttributes();

      await gamesViewModel.initialLoadComplete;
      await linkGameWithRounds(daucompToUpdate, gamesViewModel);

      return res;
    } catch (e) {
      log('Error fetching fixture data: $e');
      rethrow;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<String> syncTipsWithLegacy(DAUComp daucompToUpdate,
      GamesViewModel gamesViewModel, Tipper? onlySyncThisTipper) async {
    await initialLoadComplete;

    _isLegacySyncing = true;
    notifyListeners();

    try {
      LegacyTippingService tippingService =
          GetIt.instance<LegacyTippingService>();
      TippersViewModel tippersViewModel = di<TippersViewModel>();
      TipsViewModel allTipsViewModel =
          TipsViewModel(tippersViewModel, daucompToUpdate, gamesViewModel);

      await tippingService.initialized();
      String res;

      if (onlySyncThisTipper != null) {
        res = await tippingService.syncAllTipsToLegacy(
            allTipsViewModel, this, onlySyncThisTipper);
      } else {
        res = await tippingService.syncAllTipsToLegacy(
            allTipsViewModel, this, null);
      }

      return res;
    } catch (e) {
      log('Error syncing tips with legacy: $e');
      rethrow;
    } finally {
      _isLegacySyncing = false;
      notifyListeners();
    }
  }

  Future<void> _updateRoundStartEndTimesBasedOnFixture(
      DAUComp daucomp, GamesViewModel gamesViewModel) async {
    await initialLoadComplete;

    List<Game> games = await gamesViewModel.getGames();
    Map<String, List<Game>> groups = _groupGamesByLeagueAndRound(games);
    List<Map<String, Object>?> sortedGameGroups =
        _sortGameGroupsByStartTimeThenMatchNumber(groups);

    await _updateDatabaseWithCombinedRounds(
        _combineGameGroupsIntoRounds(
            sortedGameGroups.cast<Map<String, dynamic>>()),
        daucomp);
  }

  Map<String, List<Game>> _groupGamesByLeagueAndRound(List<Game> games) {
    return groupBy(games, (Game g) => '${g.league}-${g.roundNumber}');
  }

  Map<String, DateTime> _calculateStartEndTimes(List<Game> games) {
    var minStartTime = games
        .map((g) => g.startTimeUTC)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    var maxStartTime =
        games.map((g) => g.startTimeUTC).reduce((a, b) => a.isAfter(b) ? a : b);
    return {'minStartTime': minStartTime, 'maxStartTime': maxStartTime};
  }

  List<Map<String, Object>?> _sortGameGroupsByStartTimeThenMatchNumber(
      Map<String, List<Game>> groups) {
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
          return (a['games'] as List<Game>)
              .first
              .matchNumber
              .compareTo((b['games'] as List<Game>).first.matchNumber);
        }
        return startTimeCompare;
      });
  }

  List<DAURound> _combineGameGroupsIntoRounds(
      List<Map<String, dynamic>> sortedGameGroups) {
    List<DAURound> combinedRounds = [];
    for (var group in sortedGameGroups) {
      List<Game> games = group['games'] as List<Game>;
      DateTime minStartTime = group['minStartTime'] as DateTime;
      DateTime maxStartTime = group['maxStartTime'] as DateTime;

      if (combinedRounds.isEmpty) {
        combinedRounds.add(DAURound(
            dAUroundNumber: combinedRounds.length + 1,
            roundStartDate: minStartTime,
            roundEndDate: maxStartTime)
          ..games = games);
      } else {
        DAURound lastRound = combinedRounds.last;
        DateTime lastRoundMaxStartTime = lastRound.games
            .map((g) => g.startTimeUTC)
            .reduce((a, b) => a.isAfter(b) ? a : b);

        if (minStartTime.isBefore(lastRoundMaxStartTime)) {
          lastRound.games.addAll(games);
        } else {
          combinedRounds.add(DAURound(
              dAUroundNumber: combinedRounds.length + 1,
              roundStartDate: minStartTime,
              roundEndDate: maxStartTime)
            ..games = games);
        }
      }
    }
    return combinedRounds;
  }

  Future<void> _updateDatabaseWithCombinedRounds(
      List<DAURound> combinedRounds, DAUComp daucomp) async {
    for (var i = 0; i < combinedRounds.length; i++) {
      var minStartTime = combinedRounds[i]
          .games
          .map((g) => g.startTimeUTC)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      var maxStartTime = combinedRounds[i]
          .games
          .map((g) => g.startTimeUTC)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      if (_selectedDAUComp!.daurounds.isEmpty ||
          _selectedDAUComp!.daurounds[i].roundStartDate != minStartTime ||
          _selectedDAUComp!.daurounds[i].roundEndDate != maxStartTime) {
        updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i/roundStartDate',
            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(minStartTime).toString()}Z');
        updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i/roundEndDate',
            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(maxStartTime).toString()}Z');
      }

      _setRoundState(combinedRounds[i]);
    }

    await saveBatchOfCompAttributes();
  }

  Future<void> linkGameWithRounds(
      DAUComp daucompToUpdate, GamesViewModel gamesViewModel) async {
    log('In linkGameWithRounds()');

    for (var round in daucompToUpdate.daurounds) {
      round.games = await gamesViewModel.getGamesForRound(round);
      _setRoundState(round);
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

  Future<Map<League, List<Game>>> sortGamesIntoLeagues(
      DAURound combinedRound, GamesViewModel gamesViewModel) async {
    await initialLoadComplete;
    await gamesViewModel.initialLoadComplete;

    List<Game> nrlGames = [];
    List<Game> aflGames = [];

    List<Game> roundGames = combinedRound.games;
    for (var game in roundGames) {
      if (game.league == League.nrl) {
        nrlGames.add(game);
      } else {
        aflGames.add(game);
      }
    }

    nrlGames
        .sort(); //use the default sort which is game start time then match number
    aflGames
        .sort(); //use the default sort which is game start time then match number

    return {League.nrl: nrlGames, League.afl: aflGames};
  }

  Future<String> getDefaultTipsForCombinedRoundNumber(
      DAURound combinedRound) async {
    await initialLoadComplete;

    Map<League, List<Game>> gamesForCombinedRoundNumber =
        await sortGamesIntoLeagues(combinedRound, di<GamesViewModel>());

    List<Game> filteredNrlGames = gamesForCombinedRoundNumber[League.nrl]!;
    List<Game> filteredAflGames = gamesForCombinedRoundNumber[League.afl]!;

    String defaultRoundNrlTips = 'D' * filteredNrlGames.length;
    defaultRoundNrlTips = defaultRoundNrlTips.padRight(8, 'z');

    String defaultRoundAflTips = 'D' * filteredAflGames.length;
    defaultRoundAflTips = defaultRoundAflTips.padRight(9, 'z');

    return defaultRoundNrlTips + defaultRoundAflTips;
  }

  // Future<DAUComp?> getCurrentDAUComp() async {
  //   DAUComp? daucomp = await findComp(_selectedDAUCompDbKey);
  //   _setSelectedDAUComp(daucomp);
  //   return daucomp;
  // }

  void turnOffListener() {
    _daucompsStream.cancel();
  }

  void turnOnListener() {
    _listenToDAUComps();
  }

  void _otherViewModelUpdated() {
    notifyListeners();
  }

  @override
  void dispose() {
    _daucompsStream.cancel();
    tipperScoresViewModel!.removeListener(_otherViewModelUpdated);

    GamesViewModel gamesViewModel = di<GamesViewModel>();
    gamesViewModel.removeListener(_otherViewModelUpdated);

    tipperScoresViewModel = di<ScoresViewModel>();
    tipperScoresViewModel!.removeListener(_otherViewModelUpdated);

    super.dispose();
  }

  List<Future> _processGames(List<dynamic> nrlGames, List<dynamic> aflGames,
      GamesViewModel? gamesViewModel) {
    List<Future> gamesFuture = [];

    void processGames(List games, League league) {
      for (var gamejson in games) {
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
}
