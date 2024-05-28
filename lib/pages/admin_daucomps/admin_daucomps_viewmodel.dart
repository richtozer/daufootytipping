import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:watch_it/watch_it.dart';

// define constant for firestore database locations
const daucompsPath = '/AllDAUComps';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _daucompsStream;

  // the tipper/admin can change the selected comp in the UI, we keep track of the original default comp here
  final String _defaultDAUCompDbKey;
  String get defaultDAUCompDbKey => _defaultDAUCompDbKey;

  //setter for defaultDAUCompDbKey
  void setDefaultDAUCompDbKey(String newDefaultDAUCompDbKey) {
    _selectedDAUCompDbKey = newDefaultDAUCompDbKey;
    notifyListeners();
  }

  late String _selectedDAUCompDbKey;

  // the tipper/admin can change the selected comp in the UI, this is tracked with selectedDAUComp
  DAUComp? _selectedDAUComp;
  DAUComp? get selectedDAUComp => _selectedDAUComp;

  bool _savingDAUComp = false;
  bool get savingDAUComp => _savingDAUComp;

  Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  ScoresViewModel? scoresViewModel;

  //constructor
  DAUCompsViewModel(this._defaultDAUCompDbKey) {
    // the passed in comp dbkey comes from remote config, save it as default
    // user can change it in profile page, selectedDAUCompDbKey will track that change
    _selectedDAUCompDbKey = _defaultDAUCompDbKey;

    init();
  }

  Future<void> init() async {
    await migrateDAUComps();
    _listenToDAUComps();
    fixtureUpdateTrigger();
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void setSelectedDAUComp(DAUComp? daucomp) {
    _selectedDAUComp = daucomp;
    notifyListeners();
  }

  // method to reset data when user changes DAUComp in the UI
  void changeCurrentDAUComp(String newDAUCompDbkey) async {
    _selectedDAUCompDbKey = newDAUCompDbkey;

    _selectedDAUComp = await findComp(newDAUCompDbkey);

    //reset the ScoringViewModel registration in get_it
    di.registerLazySingleton<ScoresViewModel>(
        () => ScoresViewModel(newDAUCompDbkey));
    scoresViewModel = di<ScoresViewModel>();

    //reset the gamesViewModel in get_it
    di.registerLazySingleton<GamesViewModel>(
        () => GamesViewModel(_selectedDAUComp!));

    //reset the AllTipsViewModel registration in get_it
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

        _daucomps = allDAUComps.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic daucompAsJSON = entry.value;

          // Create a list of DAURounds for this DAUComp
          List<DAURound> daurounds = [];

          //deserialize combinedRounds List, use the index + 1 as the round number
          if (daucompAsJSON['combinedRounds'] != null) {
            List<dynamic> combinedRounds = daucompAsJSON['combinedRounds'];
            for (var i = 0; i < combinedRounds.length; i++) {
              daurounds.add(DAURound.fromJson(
                  Map<String, dynamic>.from(combinedRounds[i]), i + 1));
            }
          }

          //deserialize the DAUComp with the DAURounds
          return DAUComp.fromJson(
              Map<String, dynamic>.from(daucompAsJSON), key, daurounds);
        }).toList();

        if (!_initialLoadCompleter.isCompleted) {
          _initialLoadCompleter.complete();
        }
      } else {
        log('No DAUComps found at database location: $daucompsPath');
        _daucomps = [];
      }
    } catch (e) {
      log('Error listening to $daucompsPath: $e');
      rethrow;
    } finally {
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
    }
  }

  // method to set roundstate after the games have been loaded
  //   noGames, // round has no games
  //   notStarted, // round is in the future
  //   started, // round is underway
  //   allGamesEnded, // round has finished and results known
  void setRoundState(DAURound round) {
    if (round.games.isEmpty) {
      //round.roundState = RoundState.noGames;
      throw 'Round has no games. All DAU rounds should have games. Check the fixture data and date ranges for each round.';
    } else {
      // check if all games have started
      bool allGamesStarted = round.games.every((game) {
        return game.gameState == GameState.startedResultKnown ||
            game.gameState == GameState.startedResultNotKnown;
      });

      // check if all games have ended
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

  static Duration fixtureUpdateTriggerDelay(DateTime lastUpdate) {
    // add 24 hours to lastUpdate
    DateTime nextUpdate = lastUpdate.add(const Duration(days: 1));

    // wind the nextUpdate clock back to 19:00 UTC
    DateTime timeUntilNewDay = DateTime.utc(
        nextUpdate.year, nextUpdate.month, nextUpdate.day, 19, 0, 0, 0, 0);

    // calculate the duration until the next update
    Duration durationUntilUpdate =
        timeUntilNewDay.toUtc().difference(DateTime.now().toUtc());

    return durationUntilUpdate;
  }

  Future<void> fixtureUpdateTrigger() async {
    await initialLoadComplete;

    // get the last update time for the current comp
    DAUComp? selectedDAUComp = await getCurrentDAUComp();
    // if the selectedDAUComp is null then we can't do anything and it likely the
    // database is empty or corrupt.
    if (selectedDAUComp == null) {
      log('Cannot determine current DAUComp. Check 1) AppCheck, 2) database is empty or 3) database is corrupt. No fixture update will be triggered.');

      return;
    }

    DateTime? lastUpdate = selectedDAUComp.lastFixtureUpdateTimestamp;

    lastUpdate ??= DateTime.utc(2021, 1, 1);

    Duration timeUntilNewDay = fixtureUpdateTriggerDelay(lastUpdate);

    // create a Future delayed that triggers the fixture update in the new UTC day
    log('Waiting for fixture update trigger at ${DateTime.now().toUtc().add(timeUntilNewDay)}');
    await Future.delayed(timeUntilNewDay);
    log('Fixture update trigger has been triggered at ${DateTime.now().toUtc()}');

    // if the lastUpdate has not changed while we were waiting then trigger
    // the fixture update now
    // this will make sure only we update the fixture once for today
    if (selectedDAUComp.lastFixtureUpdateTimestamp == lastUpdate ||
        selectedDAUComp.lastFixtureUpdateTimestamp == null) {
      log('Triggering fixture update for comp: ${selectedDAUComp.name}');

      String res =
          await getNetworkFixtureData(selectedDAUComp, di<GamesViewModel>());

      FirebaseAnalytics.instance.logEvent(
        name: 'fixture_update',
        parameters: {'comp': selectedDAUComp.name, 'result': res},
      );

      // update the lastUpdate time
      selectedDAUComp.lastFixtureUpdateTimestamp = DateTime.now().toUtc();
      updateCompAttribute(selectedDAUComp.dbkey!, 'lastFixtureUpdateTimestamp',
          selectedDAUComp.lastFixtureUpdateTimestamp!.toIso8601String());
      await saveBatchOfCompAttributes();
    } else {
      log('Fixture update has already been triggered for comp: ${selectedDAUComp.name}');
    }
  }

  Future<String> getNetworkFixtureData(
      DAUComp daucompToUpdate, GamesViewModel? gamesViewModel) async {
    try {
      if (!_initialLoadCompleter.isCompleted) {
        log('getNetworkFixtureData() waiting for initial DAUCompsViewModel load to complete');
      }
      await initialLoadComplete;

      gamesViewModel ??= GamesViewModel(daucompToUpdate);

      _isDownloading = true;
      notifyListeners();

      FixtureDownloadService fetcher = FixtureDownloadService();

      //fetch the fixture data on a background thread
      Map<String, List<dynamic>> fixtures = await fetcher.fetch(
          daucompToUpdate.nrlFixtureJsonURL, daucompToUpdate.aflFixtureJsonURL);

      log('Fixture data loaded on background thread.');

      List<dynamic> nrlGames = fixtures['nrlGames']!;
      List<dynamic> aflGames = fixtures['aflGames']!;

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

      await Future.wait(gamesFuture);

      //save all game updates
      await gamesViewModel.saveBatchOfGameAttributes();

      //once all the data is loaded, update the combinedRound field
      await caclRoundStartEndTimesBasedOnFixture(
          daucompToUpdate, gamesViewModel);

      return 'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<String> syncTipsWithLegacy(
      DAUComp daucompToUpdate, GamesViewModel gamesViewModel) async {
    try {
      await initialLoadComplete;

      _isLegacySyncing = true;
      notifyListeners();

      //get reference to legacy tipping service so that we can sync tips
      LegacyTippingService tippingService =
          GetIt.instance<LegacyTippingService>();

      TippersViewModel tippersViewModel = TippersViewModel(false);

      // grab everybodies tips
      TipsViewModel allTipsViewModel = TipsViewModel(
          tippersViewModel, daucompToUpdate.dbkey!, gamesViewModel);

      //sync tips to legacy
      await tippingService.initialized();
      return await tippingService.syncAllTipsToLegacy(allTipsViewModel, this);
    } finally {
      _isLegacySyncing = false;
      notifyListeners();
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
  Future<void> caclRoundStartEndTimesBasedOnFixture(
      DAUComp daucomp, GamesViewModel gamesViewModel) async {
    log('In caclRoundStartEndTimesBasedOnFixture()');

    await initialLoadComplete;

    List<Game> games = await gamesViewModel.getGames();

    // Group games by league and round number
    var groups = groupBy(games, (g) => '${g.league}-${g.roundNumber}');

    // Find min and max start times for each group and sort groups by min start time
    var sortedGameGroups = groups.entries
        .map((e) {
          if (e.value.isEmpty) {
            return null; // Return null if the group is empty
          }
          var minStartTime = e.value
              .map((g) => g.startTimeUTC)
              .reduce((a, b) => a.isBefore(b) ? a : b);
          var maxStartTime = e.value
              .map((g) => g.startTimeUTC)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          return {
            'games': e.value,
            'minStartTime': minStartTime,
            'maxStartTime': maxStartTime
          };
        })
        .where((group) => group != null)
        .toList()
      ..sort((a, b) => ((a!['minStartTime'] as DateTime?)
              ?.compareTo(b!['minStartTime'] as DateTime) ??
          1));

    // Combine any overlaping game groups into DAU rounds
    List<DAURound> combinedRounds = [];
    for (var group in sortedGameGroups) {
      List<Game> games = group!['games'] as List<Game>;
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

    for (var i = 0; i < combinedRounds.length; i++) {
      var minStartTime = combinedRounds[i]
          .games
          .map((g) => g.startTimeUTC)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      var maxStartTime = combinedRounds[i]
          .games
          .map((g) => g.startTimeUTC)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      // only update the database if the roundStartDate and roundEndDate have changed
      // or if the daucomp.daurounds[] is empty
      // or if the daucomp.daurounds[i] is empty
      // this will prevent unnecessary database writes

      if (combinedRounds[i].roundStartDate != minStartTime ||
          combinedRounds[i].roundEndDate != maxStartTime ||
          daucomp.daurounds == null ||
          daucomp.daurounds!.isEmpty) {
        // update the roundStartDate and roundEndDate
        updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i/roundStartDate',
            DateFormat('yyyy-MM-ddTHH:mm:ssZ').format(minStartTime.toUtc()));
        updateCompAttribute(daucomp.dbkey!, 'combinedRounds/$i/roundEndDate',
            DateFormat('yyyy-MM-ddTHH:mm:ssZ').format(maxStartTime.toUtc()));
      }

      // update the roundState by calling DAUCompsViewModel.setRoundState()
      di<DAUCompsViewModel>().setRoundState(combinedRounds[i]);
    }

    // save all updates to the database
    await saveBatchOfCompAttributes();

    daucomp.daurounds = combinedRounds;
  }

  Future<DAUComp?> findComp(String compDbKey) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('findComp() waiting for initial DAuComp load to complete');
    }
    await _initialLoadCompleter.future;
    return _daucomps.firstWhereOrNull((daucomp) => daucomp.dbkey == compDbKey);
  }

  final Map<String, dynamic> updates = {};

  void updateCompAttribute(
      String dauCompDbKey, String attributeName, dynamic attributeValue) {
    updates['$daucompsPath/$dauCompDbKey/$attributeName'] = attributeValue;
  }

  Future<void> newDAUComp(
    DAUComp newDAUComp,
  ) async {
    if (newDAUComp.dbkey == null) {
      log('Adding new DAUComp record');
      // add new record to updates Map, create a new db key first
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

    return _daucomps;
  }

  Future<DAUComp> getCompWithScores() async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getCompWithScores() waiting for initial Game load to complete');
      await initialLoadComplete;
    }

    List<DAURound> getRoundInfoAndConsolidatedScores =
        _selectedDAUComp!.daurounds!;
    ScoresViewModel? tipperScoresViewModel = di<ScoresViewModel>();

    for (DAURound round in getRoundInfoAndConsolidatedScores) {
      round.roundScores =
          await tipperScoresViewModel.getTipperConsolidatedScoresForRound(
              round, di<TippersViewModel>().selectedTipper!);
    }

    //daucomp.consolidatedCompScores =
    //    tipperScoresViewModel.getTipperConsolidatedScoresForComp(tipper);

    return _selectedDAUComp!;
  }

  //method to get a List<int> of the combined round numbers
  Future<List<int>> getCombinedRoundNumbers() async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getCombinedRoundNumbers() waiting for initial Game load to complete');
      await initialLoadComplete;
    }

    List<int> combinedRoundNumbers = [];
    for (var round in _selectedDAUComp!.daurounds!) {
      combinedRoundNumbers.add(round.dAUroundNumber);
    }

    combinedRoundNumbers.sort();
    return combinedRoundNumbers;
  }

  Future<Map<League, List<Game>>> getGamesForCombinedRoundNumber(
      int combinedRoundNumber, GamesViewModel gamesViewModel) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getGamesForCombinedRoundNumber() waiting for initial Game load to complete');
    }

    await initialLoadComplete;

    List<Game> nrlGames = [];
    List<Game> aflGames = [];

    gamesViewModel ??= di<GamesViewModel>();

    //use dauround.getRoundStartDate and getRoundEndDate to filter the games for the combined round
    //then based on the league, add the games to the appropriate list
    for (var round in _selectedDAUComp!.daurounds!) {
      if (round.dAUroundNumber == combinedRoundNumber) {
        //filter the games for this round
        gamesViewModel!.getGames().then((games) {
          for (var game in games) {
            if (game.startTimeUTC.isAfter(round.getRoundStartDate()) &&
                game.startTimeUTC.isBefore(round.getRoundEndDate())) {
              if (game.league == League.nrl) {
                nrlGames.add(game);
              } else if (game.league == League.afl) {
                aflGames.add(game);
              }
            }
          }
        });
      }
    }

    // sort each list of games by matchnumber
    nrlGames.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    aflGames.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));

    return {League.nrl: nrlGames, League.afl: aflGames};
  }

  //method to get default tips for a given combined round number and league
  Future<String> getDefaultTipsForCombinedRoundNumber(
      int combinedRoundNumber) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getDefaultTipsForCombinedRoundNumber() waiting for initial Game load to complete');
    }
    await initialLoadComplete;

    //get all the games for this round
    Map<League, List<Game>> gamesForCombinedRoundNumber =
        await getGamesForCombinedRoundNumber(
            combinedRoundNumber, di<GamesViewModel>());

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

    setSelectedDAUComp(daucomp);
    return daucomp;
  }

  // method to return the highest round number, where all the games have been played
  Future<int> getHighestRoundNumberWithAllGamesPlayed(DAUComp daucomp) async {
    int highestRoundNumber = 0;

    for (var round in daucomp.daurounds!..sort((a, b) => b.compareTo(a))) {
      bool allGamesPlayed = true;
      for (var game in round.games) {
        if (game.gameState == GameState.notStarted ||
            game.gameState == GameState.startingSoon) {
          allGamesPlayed = false;
          break;
        }
      }
      if (allGamesPlayed) {
        highestRoundNumber = round.dAUroundNumber;
      } else {
        break;
      }
    }
    return highestRoundNumber;
  }

  turnOffListener() {
    _daucompsStream.cancel();
  }

  turnOnListener() {
    _listenToDAUComps();
  }

  // this method will migrate each dau comp under /DAUComps to /AllDAUComps if it does not exist
  // it will bring across the following attributes:
  // name, aflFixtureJsonURL, nrlFixtureJsonURL
  // it will not create a combinedRounds attribute
  Future<void> migrateDAUComps() async {
    try {
      log('Migrating DAUComps to AllDAUComps');
      final legacyDAUComps = Map<String, dynamic>.from(
          (await _db.child('/DAUComps').get()).value as dynamic);

      for (var legacyDAUcomp in legacyDAUComps.entries) {
        String key = legacyDAUcomp.key;
        dynamic daucompAsJSON = legacyDAUcomp.value;

        // check if the DAUComp exists in /AllDAUComps
        if ((await _db.child('$daucompsPath/$key').get()).value == null) {
          // create the DAUComp in /AllDAUComps
          await _db.child('$daucompsPath/$key').set({
            'name': daucompAsJSON['name'],
            'aflFixtureJsonURL': daucompAsJSON['aflFixtureJsonURL'],
            'nrlFixtureJsonURL': daucompAsJSON['nrlFixtureJsonURL'],
          });
          log('Migrated DAUComp: $key');
        } else {
          log('DAUComp already exists in AllDAUComps: $key');
        }
      }
    } catch (e) {
      log('Error migrating DAUComps: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _daucompsStream.cancel(); // stop listening to stream

    // create a new Completer if the old one was completed:
    if (_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter = Completer<void>();
    }
    super.dispose();
  }
}
