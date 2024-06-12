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

// Define constants for Firestore database locations
const daucompsPath = '/AllDAUComps';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _daucompsStream;

  // The tipper/admin can change the selected comp in the UI, we keep track of the original default comp here
  final String _defaultDAUCompDbKey;
  String get defaultDAUCompDbKey => _defaultDAUCompDbKey;

  // Setter for defaultDAUCompDbKey
  void setDefaultDAUCompDbKey(String newDefaultDAUCompDbKey) {
    _selectedDAUCompDbKey = newDefaultDAUCompDbKey;
    notifyListeners();
  }

  late String _selectedDAUCompDbKey;

  // The tipper/admin can change the selected comp in the UI, this is tracked with selectedDAUComp
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

  ScoresViewModel? scoresViewModel;

  ItemScrollController itemScrollController = ItemScrollController();

  final Map<String, dynamic> updates = {};

  // Constructor
  DAUCompsViewModel(this._defaultDAUCompDbKey) {
    // The passed in comp dbkey comes from remote config, save it as default
    // User can change it in profile page, selectedDAUCompDbKey will track that change
    _selectedDAUCompDbKey = _defaultDAUCompDbKey;

    init();
  }

  Future<void> init() async {
    await _migrateDAUComps();
    _listenToDAUComps();
    _fixtureUpdateTrigger();
  }

  void _setSelectedDAUComp(DAUComp? daucomp) {
    _selectedDAUComp = daucomp;
    notifyListeners();
  }

  // Method to reset data when user changes DAUComp in the UI
  void changeCurrentDAUComp(String newDAUCompDbkey) async {
    _selectedDAUCompDbKey = newDAUCompDbkey;

    _selectedDAUComp = await findComp(newDAUCompDbkey);

    // Reset the ScoringViewModel registration in get_it
    di.registerLazySingleton<ScoresViewModel>(
        () => ScoresViewModel(_selectedDAUComp!));
    scoresViewModel = di<ScoresViewModel>();

    // Reset the gamesViewModel in get_it
    di.registerLazySingleton<GamesViewModel>(
        () => GamesViewModel(_selectedDAUComp!));

    // Reset the AllTipsViewModel registration in get_it
    di.registerLazySingleton<TipsViewModel>(() => TipsViewModel(
        di<TippersViewModel>(), newDAUCompDbkey, di<GamesViewModel>()));

    notifyListeners();
  }

  // Database listeners
  void _listenToDAUComps() {
    _daucompsStream = _db.child(daucompsPath).onValue.listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('***DAUCompsViewModel_handleEvent()***');
      if (event.snapshot.exists) {
        final allDAUComps =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        // Load existing DAUComps into a map for comparison
        Map<String, DAUComp> existingDAUCompsMap = {
          for (var daucomp in _daucomps) daucomp.dbkey!: daucomp
        };

        // Iterate through the new DAUComp data
        for (var entry in allDAUComps.entries) {
          String key = entry.key;
          dynamic daucompAsJSON = entry.value;

          // Create a list of DAURounds for this DAUComp
          List<DAURound> daurounds = [];

          // Deserialize combinedRounds List, use the index + 1 as the round number
          if (daucompAsJSON['combinedRounds'] != null) {
            List<dynamic> combinedRounds = daucompAsJSON['combinedRounds'];
            for (var i = 0; i < combinedRounds.length; i++) {
              daurounds.add(DAURound.fromJson(
                  Map<String, dynamic>.from(combinedRounds[i]), i + 1));
            }
          }

          // Deserialize the DAUComp with the DAURounds
          DAUComp databaseDAUComp = DAUComp.fromJson(
              Map<String, dynamic>.from(daucompAsJSON), key, daurounds);

          // Compare with existing data and update if necessary
          if (existingDAUCompsMap.containsKey(key)) {
            DAUComp existingDAUComp = existingDAUCompsMap[key]!;
            if (existingDAUComp != databaseDAUComp) {
              existingDAUCompsMap[key] = databaseDAUComp;
              log('Updated DAUComp from database: $key');
              // rerun the round game linking code
              await linkGameWithRounds(databaseDAUComp, di<GamesViewModel>());
            }
          } else {
            // Add new DAUComp if it doesn't exist in the existing data
            existingDAUCompsMap[key] = databaseDAUComp;
            log('Initialised DAUComp from database: $key');
          }
        }

        // Update the _daucomps list with the modified map
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

  // Method to set round state after the games have been loaded
  //   noGames, // round has no games
  //   notStarted, // round is in the future
  //   started, // round is underway
  //   allGamesEnded, // round has finished and results known
  void _setRoundState(DAURound round) {
    if (round.games.isEmpty) {
      round.roundState = RoundState.noGames;
      log('Round ${round.dAUroundNumber} has no games. All DAU rounds should have games. Check the fixture data and date ranges for each round.');
      return;
    } else {
      // Check if all games have started
      bool allGamesStarted = round.games.every((game) {
        return game.gameState == GameState.startedResultKnown ||
            game.gameState == GameState.startedResultNotKnown;
      });

      // Check if all games have ended
      bool allGamesEnded = round.games.every((game) {
        return game.gameState == GameState.startedResultKnown;
      });

      if (allGamesEnded) {
        round.roundState = RoundState.allGamesEnded;
        return;
      } else if (allGamesStarted) {
        round.roundState = RoundState.started;
        return;
      } else {
        round.roundState = RoundState.notStarted;
      }
    }
  }

  static Duration _fixtureUpdateTriggerDelay(DateTime lastUpdate) {
    // Add 24 hours to lastUpdate
    DateTime nextUpdate = lastUpdate.add(const Duration(days: 1));

    // Wind the nextUpdate clock back to 19:00 UTC
    DateTime timeUntilNewDay = DateTime.utc(
        nextUpdate.year, nextUpdate.month, nextUpdate.day, 19, 0, 0, 0, 0);

    // Calculate the duration until the next update
    Duration durationUntilUpdate =
        timeUntilNewDay.toUtc().difference(DateTime.now().toUtc());

    return durationUntilUpdate;
  }

  Future<void> _fixtureUpdateTrigger() async {
    await initialLoadComplete;

    // Get the last update time for the current comp
    DAUComp? selectedDAUComp = await getCurrentDAUComp();
    // If the selectedDAUComp is null then we can't do anything and it likely the
    // database is empty or corrupt.
    if (selectedDAUComp == null) {
      log('Cannot determine current DAUComp. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');

      return;
    }

    DateTime? lastUpdate = selectedDAUComp.lastFixtureUpdateTimestamp;

    lastUpdate ??= DateTime.utc(2021, 1, 1);

    Duration timeUntilNewDay = _fixtureUpdateTriggerDelay(lastUpdate);

    // Create a Future delayed that triggers the fixture update in the new UTC day
    log('Waiting for fixture update trigger at ${DateTime.now().toUtc().add(timeUntilNewDay)}');
    await Future.delayed(timeUntilNewDay);
    log('Fixture update delay has elapsed ${DateTime.now().toUtc()}.');

    // If the lastUpdate has not changed while we were waiting then trigger
    // the fixture update now
    // this will make sure only we update the fixture once for today
    if (selectedDAUComp.lastFixtureUpdateTimestamp == lastUpdate ||
        selectedDAUComp.lastFixtureUpdateTimestamp == null) {
      log('Starting fixture update for comp: ${selectedDAUComp.name}');

      await getNetworkFixtureData(selectedDAUComp, di<GamesViewModel>());
    } else {
      log('Fixture update has already been triggered for comp: ${selectedDAUComp.name}. Skipping');
    }
  }

  Future<String> getNetworkFixtureData(
      DAUComp daucompToUpdate, GamesViewModel? gamesViewModel) async {
    try {
      if (_isDownloading) {
        log('getNetworkFixtureData() is already downloading');
        return 'Fixture data is already downloading';
      }

      if (!_initialLoadCompleter.isCompleted) {
        log('getNetworkFixtureData() waiting for initial DAUCompsViewModel load to complete');
      }
      await initialLoadComplete;

      _isDownloading = true;

      FixtureDownloadService fetcher = FixtureDownloadService();

      Map<String, List<dynamic>> fixtures = await fetcher.fetch(
          daucompToUpdate.nrlFixtureJsonURL,
          daucompToUpdate.aflFixtureJsonURL,
          true);

      List<dynamic> nrlGames = fixtures['nrlGames']!;
      List<dynamic> aflGames = fixtures['aflGames']!;

      List<Future> gamesFuture =
          _processGames(nrlGames, aflGames, gamesViewModel);

      await Future.wait(gamesFuture);

      // Save all game updates
      await gamesViewModel!.saveBatchOfGameAttributes();

      // If any game start times have changed in the fixture,
      // this may impact the round start and end times
      _updateRoundStartEndTimesBasedOnFixture(daucompToUpdate, gamesViewModel);

      String res =
          'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';

      FirebaseAnalytics.instance.logEvent(
        name: 'fixture_update',
        parameters: {'comp': selectedDAUComp!.name, 'result': res},
      );

      // Update the lastUpdate time
      selectedDAUComp!.lastFixtureUpdateTimestamp = DateTime.now().toUtc();
      updateCompAttribute(selectedDAUComp!.dbkey!, 'lastFixtureUpdateTimestamp',
          selectedDAUComp!.lastFixtureUpdateTimestamp!.toIso8601String());
      await saveBatchOfCompAttributes();

      _isDownloading = false;
      notifyListeners();

      return res;
    } catch (e) {
      log('Error fetching fixture data: $e');
      _isDownloading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<String> syncTipsWithLegacy(DAUComp daucompToUpdate,
      GamesViewModel gamesViewModel, Tipper? onlySyncThisTipper) async {
    try {
      await initialLoadComplete;

      _isLegacySyncing = true;

      // Get reference to legacy tipping service so that we can sync tips
      LegacyTippingService tippingService =
          GetIt.instance<LegacyTippingService>();

      TippersViewModel tippersViewModel = di<TippersViewModel>();

      // Grab everybody's tips
      TipsViewModel allTipsViewModel = TipsViewModel(
          tippersViewModel, daucompToUpdate.dbkey!, gamesViewModel);

      // Sync tips to legacy
      await tippingService.initialized();

      String res;

      if (onlySyncThisTipper != null) {
        res = await tippingService.syncAllTipsToLegacy(
            allTipsViewModel, this, onlySyncThisTipper);
      } else {
        res = await tippingService.syncAllTipsToLegacy(
            allTipsViewModel, this, null);
      }
      _isLegacySyncing = false;
      notifyListeners();

      return res;
    } catch (e) {
      log('Error syncing tips with legacy: $e');
      _isLegacySyncing = false;
      notifyListeners();
      rethrow;
    }
  }

  // Find overlapping rounds for NRL and AFL and combine them into a single round using this logic:
  // 1) Each league has games grouped by a round number by the fixture service - the logic should preserve this grouping
  // 2) group the games by Game.league and Game.roundNumber
  // 3) find the min Game.startTimeUTC for each league-roundnumber group - this is the start time of the group of games for that league
  // 4) find the max Game.startTimeUTC for each group - this is the end time of the group of games for that league
  // 5) sort the groups by the min Game.startTimeUTC
  // 6) take the 1st group, this will be the basis for our combined round 1
  // 7) take the next group and see if it's min Game.startTimeUTC is within the range of the 1st group's start and end times
  // 8) if it is, add the games from the 2nd group to the 1st combined round
  // 9) if it is not, create a new combined round and add the games from the 2nd group to it
  // 10) repeat steps 7-9 until all groups have been processed into combined rounds

  // Game grouping and sorting
  Future<void> _updateRoundStartEndTimesBasedOnFixture(
      DAUComp daucomp, GamesViewModel gamesViewModel) async {
    log('In updateRoundStartEndTimesBasedOnFixture()');

    await initialLoadComplete;

    List<Game> games = await gamesViewModel.getGames();
    Map<String, List<Game>> groups = _groupGamesByLeagueAndRound(games);
    List<Map<String, Object>?> sortedGameGroups =
        _sortGameGroupsByStartTimeThenMatchNumber(groups);
    var combinedRounds = _combineGameGroupsIntoRounds(
        sortedGameGroups.cast<Map<String, dynamic>>());

    await _updateDatabaseWithCombinedRounds(combinedRounds, daucomp);
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
    // Combine any overlapping game groups into DAU rounds
    List<DAURound> combinedRounds = [];
    for (var group in sortedGameGroups) {
      List<Game> games = group['games'] as List<Game>;
      DateTime minStartTime = group['minStartTime'] as DateTime;
      DateTime maxStartTime = group['maxStartTime'] as DateTime;

      if (combinedRounds.isEmpty) {
        DAURound newRound = DAURound(
          dAUroundNumber: combinedRounds.length + 1,
          roundStartDate: minStartTime,
          roundEndDate: maxStartTime,
        );
        newRound.games = games;
        combinedRounds.add(newRound);
      } else {
        DAURound lastRound = combinedRounds.last;
        DateTime lastRoundMaxStartTime = lastRound.games
            .map((g) => g.startTimeUTC)
            .reduce((a, b) => a.isAfter(b) ? a : b);

        if (minStartTime.isBefore(lastRoundMaxStartTime)) {
          lastRound.games.addAll(games);
        } else {
          DAURound newRound = DAURound(
            dAUroundNumber: combinedRounds.length + 1,
            roundStartDate: minStartTime,
            roundEndDate: maxStartTime,
          );
          newRound.games = games;
          combinedRounds.add(newRound);
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

      // Only update the database if the roundStartDate and roundEndDate have changed
      if (_selectedDAUComp!.daurounds[i].roundStartDate != minStartTime ||
          _selectedDAUComp!.daurounds[i].roundEndDate != maxStartTime) {
        // Update the roundStartDate and roundEndDate
        updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i/roundStartDate',
            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(minStartTime).toString()}Z');
        updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i/roundEndDate',
            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(maxStartTime).toString()}Z');
      }

      // Update the roundState by calling DAUCompsViewModel.setRoundState()
      _setRoundState(combinedRounds[i]);
    }

    // Save all updates to the database
    await saveBatchOfCompAttributes();
  }

  // Update DAUComp with combined rounds and games. The caller will provide
  // GamesViewModel to get the games for each round
  Future<void> linkGameWithRounds(
      DAUComp daucompToUpdate, GamesViewModel gamesViewModel) async {
    log('In updateDAUCompWithCombinedRoundsAndGames()');

    await initialLoadComplete;

    //assert(daucompToUpdate.daurounds.isNotEmpty,
    //    'DAUComp has no DAURounds. Check the fixture data and date ranges for each round.');

    // Loop through the combinedRounds and assign the games to each round
    for (var round in daucompToUpdate.daurounds) {
      round.games = await gamesViewModel.getGamesForRound(round);
      _setRoundState(round);
    }
  }

  Future<DAUComp?> findComp(String compDbKey) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('findComp() waiting for initial DAuComp load to complete');
    }
    await _initialLoadCompleter.future;
    return _daucomps.firstWhereOrNull((daucomp) => daucomp.dbkey == compDbKey);
  }

  void updateCompAttribute(
      String dauCompDbKey, String attributeName, dynamic attributeValue) {
    log('updateCompAttribute() called for $dauCompDbKey, $attributeName, $attributeValue');
    updates['$daucompsPath/$dauCompDbKey/$attributeName'] = attributeValue;
  }

  Future<void> newDAUComp(
    DAUComp newDAUComp,
  ) async {
    if (newDAUComp.dbkey == null) {
      log('Adding new DAUComp record');
      // Add new record to updates Map, create a new db key first
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
    try {
      await initialLoadComplete;
      log('Saving batch of ${updates.length} DAUComp database updates');

      await _db.update(updates);
    } finally {
      _savingDAUComp = false;
      notifyListeners();
    }
  }

  Future<List<DAUComp>> getDAUcomps() async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getDAUcomps() waiting for initial DAUCompsViewModel load to complete');
      await initialLoadComplete;
    }
    //assert(_selectedDAUComp!.daurounds[0].games.isNotEmpty,
    //    'DAUCompsViewModel: No DAUComp.DAUround games');

    return _daucomps;
  }

  // This is a key function called from the UI
  // It will return a DAUComp with the scores for the selected tipper

  Future<DAUComp> getCompWithScores() async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getCompWithScores() waiting for initial Game load to complete');
      await initialLoadComplete;
    }

    List<DAURound> listOfRounds = _selectedDAUComp!.daurounds;
    ScoresViewModel? tipperScoresViewModel = di<ScoresViewModel>();

    for (DAURound round in listOfRounds) {
      round.roundScores =
          await tipperScoresViewModel.getTipperConsolidatedScoresForRound(
              round, di<TippersViewModel>().selectedTipper!);
    }

    //daucomp.consolidatedCompScores =
    //    tipperScoresViewModel.getTipperConsolidatedScoresForComp(tipper);

    return _selectedDAUComp!;
  }

  // Method to get a List<DAURound> of the combined rounds
  Future<List<DAURound>> getCombinedRounds() async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getCombinedRounds() waiting for initial DAUComp load to complete');
      await initialLoadComplete;
    }

    return _selectedDAUComp!.daurounds;
  }

  Future<Map<League, List<Game>>> sortGamesIntoLeagues(
      DAURound combinedRound, GamesViewModel gamesViewModel) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getGamesForCombinedRoundNumber() waiting for initial DAUComp load to complete');
    }

    await initialLoadComplete;

    List<Game> nrlGames = [];
    List<Game> aflGames = [];

    // Use dauround.getRoundStartDate and getRoundEndDate to filter the games for the combined round
    // Then based on the league, add the games to the appropriate list
    List<Game> roundGames = combinedRound.games;

    // Sort the games into their respective leagues
    for (var game in roundGames) {
      if (game.league == League.nrl) {
        nrlGames.add(game);
      } else {
        aflGames.add(game);
      }
    }

    // Sort each list of games by match number
    nrlGames.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    aflGames.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));

    return {League.nrl: nrlGames, League.afl: aflGames};
  }

  // Method to get default tips for a given combined round number and league
  Future<String> getDefaultTipsForCombinedRoundNumber(
      DAURound combinedRound) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getDefaultTipsForCombinedRoundNumber() waiting for initial Game load to complete');
    }
    await initialLoadComplete;

    // Get all the games for this round
    Map<League, List<Game>> gamesForCombinedRoundNumber =
        await sortGamesIntoLeagues(combinedRound, di<GamesViewModel>());

    if (!_initialLoadCompleter.isCompleted) {
      log('getGamesForCombinedRoundNumber() waiting for initial Game load to complete');
    }
    await initialLoadComplete;

    List<Game> filteredNrlGames = gamesForCombinedRoundNumber[League.nrl]!;
    List<Game> filteredAflGames = gamesForCombinedRoundNumber[League.afl]!;

    String defaultRoundNrlTips = 'D' * filteredNrlGames.length;
    defaultRoundNrlTips = defaultRoundNrlTips.padRight(
      8,
      'z',
    );

    String defaultRoundAflTips = 'D' * filteredAflGames.length;
    defaultRoundAflTips = defaultRoundAflTips.padRight(
      9,
      'z',
    );

    return defaultRoundNrlTips + defaultRoundAflTips;
  }

  Future<DAUComp?> getCurrentDAUComp() async {
    DAUComp? daucomp = await findComp(_selectedDAUCompDbKey);

    _setSelectedDAUComp(daucomp);
    return daucomp;
  }

  void turnOffListener() {
    _daucompsStream.cancel();
  }

  void turnOnListener() {
    _listenToDAUComps();
  }

  // This method will migrate each dau comp under /DAUComps to /AllDAUComps if it does not exist
  // It will bring across the following attributes:
  // name, aflFixtureJsonURL, nrlFixtureJsonURL
  // It will not create a combinedRounds attribute
  Future<void> _migrateDAUComps() async {
    try {
      log('Migrating DAUComps to AllDAUComps');
      final legacyDAUComps = Map<String, dynamic>.from(
          (await _db.child('/DAUComps').get()).value as dynamic);

      for (var legacyDAUcomp in legacyDAUComps.entries) {
        String key = legacyDAUcomp.key;
        dynamic daucompAsJSON = legacyDAUcomp.value;

        // Check if the DAUComp exists in /AllDAUComps
        if ((await _db.child('$daucompsPath/$key').get()).value == null) {
          // Create the DAUComp in /AllDAUComps
          await _db.child('$daucompsPath/$key').set({
            'name': daucompAsJSON['name'],
            'aflFixtureJsonURL': daucompAsJSON['aflFixtureJsonURL'],
            'nrlFixtureJsonURL': daucompAsJSON['nrlFixtureJsonURL'],
          });
          log('Migrated DAUComp: $key');
        }
      }
    } catch (e) {
      log('Error migrating DAUComps: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _daucompsStream.cancel(); // Stop listening to stream
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
