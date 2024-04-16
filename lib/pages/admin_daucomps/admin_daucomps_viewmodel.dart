import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
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

// define constant for firestore database locations - TODO move to env file
const daucompsPath = '/DAUComps';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _daucompsStream;

  final String _defaultDAUCompDbKey;
  String get defaultDAUCompDbKey => _defaultDAUCompDbKey;

  late String
      _selectedDAUCompDbKey; // TODO - refactor to remove this - key can be accessed from selectedDAUComp
  String get selectedDAUCompDbKey =>
      _selectedDAUCompDbKey; // TODO - refactor to remove this - key can be accessed from selectedDAUComp

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

  bool _isScoring = false;
  bool get isScoring => _isScoring;

  GamesViewModel? userGamesViewModel;

  ScoresViewModel? scoresViewModel;
  TipsViewModel? allTipsViewModel;

  //constructor
  DAUCompsViewModel(this._defaultDAUCompDbKey) {
    // the passed in comp dbkey comes from remote config, save it as default
    // user can change it in profile page, selectedDAUCompDbKey will track that change
    _selectedDAUCompDbKey = _defaultDAUCompDbKey;

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

    //reset the gamesViewModel in get_it
    di.registerLazySingleton<GamesViewModel>(
        () => GamesViewModel(_selectedDAUComp!));
    userGamesViewModel = di<GamesViewModel>();
    userGamesViewModel?.addListener(update);

    //reset the allTipsViewModel
    allTipsViewModel = null;

    //reset the ScoringViewModel registration in get_it
    di.registerLazySingleton<ScoresViewModel>(
        () => ScoresViewModel(newDAUCompDbkey));
    scoresViewModel = di<ScoresViewModel>();

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
          if (daucompAsJSON['combinedRounds'] != null) {
            List<dynamic> rounds =
                daucompAsJSON['combinedRounds'] as List<dynamic>;
            for (int roundIndex = 0; roundIndex < rounds.length; roundIndex++) {
              List roundAsJSON = rounds[roundIndex];
              final gamesInRound = (roundAsJSON).cast<String>().map((game) {
                return game;
              }).toList();

              daurounds.add(DAURound.fromJson(gamesInRound, roundIndex + 1));
            }
          }

          //deserialize the DAUComp with the DAURounds
          return DAUComp.fromJson(
              Map<String, dynamic>.from(daucompAsJSON), key, daurounds);
        }).toList();
      }
    } catch (e) {
      log('Error listening to DAUComps: $e');
      rethrow;
    } finally {
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
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

  void fixtureUpdateTrigger() async {
    // get the last update time for the current comp
    DAUComp? selectedDAUComp = await getCurrentDAUComp();
    DateTime? lastUpdate = selectedDAUComp!.lastFixtureUpdateTimestamp;

    lastUpdate ??= DateTime.utc(2021, 1, 1);

    Duration timeUntilNewDay = fixtureUpdateTriggerDelay(lastUpdate);

    // create a Future delayed that triggers the fixture update in the new UTC day
    log('Waiting for fixture update trigger at ${DateTime.now().toUtc().add(timeUntilNewDay)}');
    await Future.delayed(timeUntilNewDay);
    log('Fixture update trigger has been triggered at ${DateTime.now().toUtc()}');

    // if the lastUpdate has not changed while we were waiting then trigger
    // the fixture update now
    // this will make sure only we update the fixture once for today
    if (selectedDAUComp!.lastFixtureUpdateTimestamp == lastUpdate ||
        selectedDAUComp!.lastFixtureUpdateTimestamp == null) {
      log('Triggering fixture update for comp: ${selectedDAUComp!.name}');

      String res = await getNetworkFixtureData(selectedDAUComp!);

      FirebaseAnalytics.instance.logEvent(
        name: 'fixture_update',
        parameters: {'comp': selectedDAUComp!.name, 'result': res},
      );

      // update the lastUpdate time
      selectedDAUComp!.lastFixtureUpdateTimestamp = DateTime.now().toUtc();
      await updateCompAttribute(selectedDAUComp!, 'lastFixtureUpdateTimestamp',
          selectedDAUComp!.lastFixtureUpdateTimestamp!.toIso8601String());
    } else {
      log('Fixture update has already been triggered for comp: ${selectedDAUComp!.name}');
    }
  }

  Future<String> getNetworkFixtureData(DAUComp daucompToUpdate) async {
    try {
      if (!_initialLoadCompleter.isCompleted) {
        log('getNetworkFixtureData() waiting for initial DAUCompsViewModel load to complete');
      }
      await initialLoadComplete;

      if (userGamesViewModel != null ||
          userGamesViewModel?.selectedDAUComp.dbkey != daucompToUpdate.dbkey!) {
        //invalidte the adminGamesViewModel
        userGamesViewModel = null;
      }

      userGamesViewModel ??= GamesViewModel(daucompToUpdate);

      // check if there were any games help yesterday. if not then skip this download
      bool gamesYesterday = await userGamesViewModel!.anyGamesHeldYesterday();

      if (!gamesYesterday) {
        return 'No games yesterday, skipping fixture update as there are unlikely to be any scoring updates';
      }

      _isDownloading = true;
      notifyListeners();

      FixtureDownloadService fixtureDownloadService = FixtureDownloadService();

      List<dynamic> nrlGames = [];
      try {
        nrlGames = await fixtureDownloadService.getLeagueFixtureRaw(
            daucompToUpdate.nrlFixtureJsonURL, League.nrl);
      } catch (e) {
        throw 'Error loading NRL fixture data. Exception was: $e';
        //return 'Error loading NRL fixture data. Exception was: $e'; // TODO - exceptions is not being passed to caller
      }

      List<dynamic> aflGames = [];
      try {
        aflGames = await fixtureDownloadService.getLeagueFixtureRaw(
            daucompToUpdate.aflFixtureJsonURL, League.afl);
      } catch (e) {
        throw 'Error loading AFL fixture data. Exception was: $e';

        //return 'Error loading AFL fixture data. Exception was: $e';  // TODO - exceptions is not being passed to caller
      }

      List<Future> gamesFuture = [];

      void processGames(List games, League league) {
        for (var gamejson in games) {
          String dbkey =
              '${league.name}-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
          for (var attribute in gamejson.keys) {
            gamesFuture.add(userGamesViewModel!.updateGameAttribute(
                dbkey, attribute, gamejson[attribute], league.name));
          }
        }
      }

      processGames(nrlGames, League.nrl);
      processGames(aflGames, League.afl);

      await Future.wait(gamesFuture);

      //save all updates
      await userGamesViewModel!.saveBatchOfGameAttributes();

      //once all the data is loaded, update the combinedRound field
      updateCombinedRoundNumber(daucompToUpdate, userGamesViewModel!);

      return 'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<String> syncTipsWithLegacy(DAUComp daucompToUpdate) async {
    try {
      await initialLoadComplete;

      _isLegacySyncing = true;
      notifyListeners();

      //get reference to legacy tipping service so that we can sync tips
      LegacyTippingService tippingService =
          GetIt.instance<LegacyTippingService>();

      TippersViewModel tippersViewModel = TippersViewModel();

      if (userGamesViewModel != null ||
          userGamesViewModel?.selectedDAUComp != daucompToUpdate.dbkey!) {
        //invalidte the adminGamesViewModel
        userGamesViewModel = null;
      }

      userGamesViewModel ??= GamesViewModel(daucompToUpdate);

      // grab everybodies tips
      TipsViewModel allTipsViewModel = TipsViewModel(
          tippersViewModel, daucompToUpdate.dbkey!, userGamesViewModel!);

      //sync tips to legacy
      await tippingService.initialized();
      return await tippingService.syncTipsToLegacy(allTipsViewModel, this);
    } finally {
      _isLegacySyncing = false;
      notifyListeners();
    }
  }

  // Find overlapping rounds for NRL and AFL and combine them into a single round
  // lets group the games for NRL and AFL into our own combined rounds based on this logic:
  // 1) Each league has games grouped by a round number - the logic should preserve this grouping
  // 2) group the games by Game.league and Game.roundNumber
  // 3) find the min Game.startTimeUTC for each league-roundnumber group - this is the start time of the group of games
  // 4) find the max Game.startTimeUTC for each group - this is the end time of the group of games for that league
  // 5) sort the groups by the min Game.startTimeUTC
  // 6) take the 1st group, this will be the basis for our combined round 1
  // 7) take the next group and see if it's min Game.startTimeUTC is within the range of the 1st group's start and end times
  // 8) if it is, add the games from the 2nd group to the 1st combined round
  // 9) if it is not, create a new combined round and add the games from the 2nd group to it
  // 10) repeat steps 7-9 until all groups have been processed into combined rounds
  // 11) Update Game.combinedRoundNumber for each game in the combined rounds

  // Game grouping and sorting
  void updateCombinedRoundNumber(
      DAUComp daucomp, GamesViewModel gamesViewModel) async {
    log('In updateCombinedRoundNumber()');

    await initialLoadComplete;
    List<Game> games = await gamesViewModel.getGames();

    // Group games by league and round number
    var groups = groupBy(games, (g) => '${g.league}-${g.roundNumber}');

    // Find min and max start times for each group and sort groups by min start time
    var sortedGroups = groups.entries
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

    // Combine rounds
    var combinedRounds = <List<Game>>[];
    for (var group in sortedGroups) {
      if (combinedRounds.isEmpty) {
        combinedRounds.add(group!['games'] as List<Game>);
      } else {
        var lastRound = combinedRounds.last;
        var lastRoundMaxStartTime = lastRound
            .map((g) => g.startTimeUTC)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        if ((group!['minStartTime'] as DateTime?)
                ?.isBefore(lastRoundMaxStartTime) ??
            false) {
          lastRound.addAll(group['games'] as List<Game>);
        } else {
          combinedRounds.add(group['games'] as List<Game>);
        }
      }
    }

    // log to the console the start and end times for each combined round
    // include the count of NRL and AFL games in each combined round
    for (var i = 0; i < combinedRounds.length; i++) {
      var minStartTime = combinedRounds[i]
          .map((g) => g.startTimeUTC)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      var maxStartTime = combinedRounds[i]
          .map((g) => g.startTimeUTC)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      var nrlCount =
          combinedRounds[i].where((g) => g.league == League.nrl).length;
      var aflCount =
          combinedRounds[i].where((g) => g.league == League.afl).length;
      //log('Date range for combined round ${i + 1}: ${DateFormat('yyyy-MM-dd').format(minStartTime.toLocal())} - ${DateFormat('yyyy-MM-dd').format(maxStartTime.toLocal())} NRL games: $nrlCount, AFL games: $aflCount');
      log('Excel Round ${i + 1},${DateFormat('yyyy-MM-dd').format(minStartTime.toLocal())},${DateFormat('yyyy-MM-dd').format(maxStartTime.toLocal())},$nrlCount,$aflCount');
    }

    // Update combined round number for each game in each round
    for (var i = 0; i < combinedRounds.length; i++) {
      List<String> listGameKeys = [];
      for (var game in combinedRounds[i]) {
        log('Updating combined round number to ${i + 1} for game: ${game.dbkey}');
        listGameKeys.add(game.dbkey);
      }
      //submit a db update for this combined round
      await updateCompAttribute(daucomp, 'combinedRounds/$i', listGameKeys);
    }

    // save all updates to the database
    await saveBatchOfCompAttributes();

    //now that the database is updated, loop through the games again and
    //assign DAURound for reverse lookup
    // TODO this is inefficient, we should be able to do this in the previous loop
    for (var i = 0; i < combinedRounds.length; i++) {
      for (var game in combinedRounds[i]) {
        // allow for reverse lookup of round from a game object
        game.dauRound = daucomp.daurounds![i];
      }
    }
  }

  Future<DAUComp?> findComp(String compDbKey) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('findComp() waiting for initial DAuComp load to complete');
    }
    await _initialLoadCompleter.future;
    return _daucomps.firstWhereOrNull((daucomp) => daucomp.dbkey == compDbKey);
  }

  final Map<String, dynamic> updates = {};

  Future<void> updateCompAttribute(
      DAUComp? dauComp, String attributeName, dynamic attributeValue) async {
    await _initialLoadCompleter.future;

    if (dauComp != null) {
      //find the DAUComp in the local list. if it's there,
      // compare the attribute value and update if different
      DAUComp? compToUpdate = await findComp(dauComp.dbkey!);
      if (compToUpdate != null) {
        dynamic oldValue = compToUpdate.toJsonForCompare()[attributeName];
        if (attributeValue != oldValue) {
          updates['$daucompsPath/${dauComp.dbkey!}/$attributeName'] =
              attributeValue;
        } else {
          log('DAUComp: ${dauComp.name} already has $attributeName: $attributeValue, skipping update');
        }
      } else {
        throw 'Existing DAUComp with dbkey ${dauComp.dbkey} not found';
      }
    }
  }

  Future<void> newDAUComp(
    DAUComp newDAUComp,
  ) async {
    await _initialLoadCompleter.future;

    if (newDAUComp.dbkey == null) {
      log('Adding new DAUComp record');
      // add new record to updates Map, create a new db key first
      DatabaseReference newCompRecordKey = _db.child(daucompsPath).push();
      updates['$daucompsPath/${newCompRecordKey.key}/name'] = newDAUComp.name;
      updates['$daucompsPath/${newCompRecordKey.key}/aflFixtureJsonURL'] =
          newDAUComp.aflFixtureJsonURL.toString();
      updates['$daucompsPath/${newCompRecordKey.key}/nrlFixtureJsonURL'] =
          newDAUComp.nrlFixtureJsonURL.toString();
    } else {
      throw 'newDAUComp() called with existing DAUComp dbkey';
    }
  }

  Future<void> saveBatchOfCompAttributes() async {
    try {
      await initialLoadComplete;
      log('Saving batch of ${updates.length} database updates');
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
      int combinedRoundNumber) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getGamesForCombinedRoundNumber() waiting for initial Game load to complete');
    }

    await initialLoadComplete;

    List<Game> nrlGames = [];
    List<Game> aflGames = [];

    userGamesViewModel ??= di<GamesViewModel>();

    for (var round in _selectedDAUComp!.daurounds!) {
      if (round.dAUroundNumber == combinedRoundNumber) {
        for (var gameKey in round.gamesAsKeys) {
          Game? game = await userGamesViewModel!.findGame(gameKey);
          if (game != null) {
            if (game.league == League.nrl) {
              nrlGames.add(game);
            } else if (game.league == League.afl) {
              aflGames.add(game);
            }
          }
        }
      }
    }

    return {League.nrl: nrlGames, League.afl: aflGames};
  }

  //method to get a List<Game> of the games for a given combined round number and league
  Future<List<Game>> getGamesForCombinedRoundNumberAndLeague_DELETE(
      int combinedRoundNumber, League league) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getGamesForCombinedRoundNumberAndLeague() waiting for initial Game load to complete');
    }
    await initialLoadComplete;

    List<Game> gamesForCombinedRoundNumberAndLeague = [];

    userGamesViewModel ??= di<GamesViewModel>();

    for (var round in _selectedDAUComp!.daurounds!) {
      if (round.dAUroundNumber == combinedRoundNumber) {
        for (var gameKey in round.gamesAsKeys) {
          Game? game = await userGamesViewModel!.findGame(gameKey);
          if (game != null && game.league == league) {
            //add the game to the list
            gamesForCombinedRoundNumberAndLeague.add(game);
          }
        }
      }
    }

    notifyListeners();

    return gamesForCombinedRoundNumberAndLeague;
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
        await getGamesForCombinedRoundNumber(combinedRoundNumber);

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

  Future<String> updateScoring(DAUComp daucompToUpdate,
      Tipper? updateThisTipper, DAURound? onlyUpdateThisRound) async {
    try {
      if (onlyUpdateThisRound != null) {
        UnimplementedError(
            'the logic for this method is not yet implemented correctly');
      }

      if (_isScoring) {
        return 'Scoring already in progress';
      }

      _isScoring = true;
      notifyListeners();

      TippersViewModel tippersViewModel = di<TippersViewModel>();

      // if adminGamesViewModel is not null and the selectedDAUComp
      // is not the same as the comp we are updating then
      // create a new temp GamesViewModel for this scoring update
      userGamesViewModel ??= di<GamesViewModel>();

      // use the AllTipsViewModel as source of data for cosolidated scoring
      if (allTipsViewModel != null &&
          allTipsViewModel!.currentDAUComp != daucompToUpdate.dbkey!) {
        //invalidate the allTipsViewModel
        allTipsViewModel = null;
      }
      // if alltips is null, create a new one
      allTipsViewModel ??= TipsViewModel(
          tippersViewModel, daucompToUpdate.dbkey!, userGamesViewModel!);

      //create a map to store the tipper consolidated scores and name?
      Map<String, Map<String, dynamic>> scoringTipperCompTotals = {};

      // create a map of total scores for each Tipper, DauRound combination
      Map<String, Map<int, Map<String, int>>> scoringTipperRoundTotals = {};

      // are we updating a single tipper or all tippers?
      List<Tipper> tippers = [];
      if (updateThisTipper != null) {
        tippers = [updateThisTipper];
      } else {
        tippers = await tippersViewModel.getActiveTippers(daucompToUpdate);
      }

      // loop through each round and then each league and total up the score for this tipper
      for (Tipper tipperToScore in tippers) {
        if (tipperToScore.name == 'Toaster') {
          log('Tipper is toaster');
        }
        //init the Tipper scoring maps
        scoringTipperRoundTotals[tipperToScore.dbkey!] = {};
        scoringTipperCompTotals[tipperToScore.dbkey!] = {};

        // keep track of thenrl and afl total comp scores for this tipper
        scoringTipperCompTotals[tipperToScore.dbkey]!['total_nrl_score'] = 0;
        scoringTipperCompTotals[tipperToScore.dbkey]!['total_nrl_maxScore'] = 0;

        scoringTipperCompTotals[tipperToScore.dbkey]!['total_afl_score'] = 0;
        scoringTipperCompTotals[tipperToScore.dbkey]!['total_afl_maxScore'] = 0;

        var dauRoundsEdited = daucompToUpdate.daurounds!;

        // if onlyUpdateThisRound != null then only update the scores for this round,
        // otherwise update all rounds
        if (onlyUpdateThisRound != null) {
          dauRoundsEdited = [onlyUpdateThisRound];
        }

        for (DAURound dauRound in dauRoundsEdited) {
          // init the round
          int roundIndex = dauRound.dAUroundNumber - 1;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex] = {};

          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                  'total_score'] ==
              0;

          //init the round consolidated scores for this tipper and each league
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'afl_score'] = 0;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'afl_maxScore'] = 0;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'afl_marginTips'] = 0;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'afl_marginUPS'] = 0;

          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'nrl_score'] = 0;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'nrl_maxScore'] = 0;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'nrl_marginTips'] = 0;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'nrl_marginUPS'] = 0;

          for (var gameKey in dauRound.gamesAsKeys) {
            // find each game in this round
            Game? game = await userGamesViewModel!.findGame(gameKey);

            if (game == null) {
              throw Exception('Game not found for key: $gameKey');
            }

            // see if there is a tip for this game and tipper
            TipGame? tipGame =
                await allTipsViewModel?.findTip(game, tipperToScore);

            // fyi tip should never be null for games in the past. findTip will assign
            // a default tip if none is found

            if (tipGame != null) {
              // count the number of margin tips for this tipper for this round
              // do this even if the game has not started
              // if the tip for the game is GameResult.a or GameResult.e then count that as one margin tip
              int marginTip =
                  (tipGame.tip == GameResult.a || tipGame.tip == GameResult.e)
                      ? 1
                      : 0;

              scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                      '${game.league.name}_marginTips'] =
                  scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                          '${game.league.name}_marginTips']! +
                      marginTip;

              // if this game has started or finished with score,
              // then calculate the scores for this tipper
              if (tipGame.game.gameState != GameState.notStarted ||
                  tipGame.game.gameState != GameState.startingSoon) {
                int score = tipGame.getTipScoreCalculated();
                int maxScore = tipGame.getMaxScoreCalculated();

                // add to cumulative score
                scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                        '${game.league.name}_score'] =
                    scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                            '${game.league.name}_score']! +
                        score;

                // add to cumulative max score
                scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                        '${game.league.name}_maxScore'] =
                    scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                            '${game.league.name}_maxScore']! +
                        maxScore;

                // add this game score to the comp score based on league
                if (game.league == League.afl) {
                  scoringTipperCompTotals[tipperToScore.dbkey]![
                      'total_afl_score'] = scoringTipperCompTotals[
                          tipperToScore.dbkey]!['total_afl_score']! +
                      score;
                  scoringTipperCompTotals[tipperToScore.dbkey]![
                      'total_afl_maxScore'] = scoringTipperCompTotals[
                          tipperToScore.dbkey]!['total_afl_maxScore']! +
                      maxScore;
                } else {
                  scoringTipperCompTotals[tipperToScore.dbkey]![
                      'total_nrl_score'] = scoringTipperCompTotals[
                          tipperToScore.dbkey]!['total_nrl_score']! +
                      score;
                  scoringTipperCompTotals[tipperToScore.dbkey]![
                      'total_nrl_maxScore'] = scoringTipperCompTotals[
                          tipperToScore.dbkey]!['total_nrl_maxScore']! +
                      maxScore;
                }

                // count the number of margin ups for this round
                // if the tip for the game is GameResult.a or GameResult.e
                // and the tipper tipped GameResult.a or GameResult.e
                // then count that as one margin ups
                int marginUPS = 0;
                if (tipGame.game.scoring != null) {
                  marginUPS = (tipGame.game.scoring!
                                      .getGameResultCalculated(game.league) ==
                                  GameResult.a &&
                              tipGame.tip == GameResult.a) ||
                          (tipGame.game.scoring!
                                      .getGameResultCalculated(game.league) ==
                                  GameResult.e &&
                              tipGame.tip == GameResult.e)
                      ? 1
                      : 0;
                  scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                          '${game.league.name}_marginUPS'] =
                      scoringTipperRoundTotals[tipperToScore.dbkey]![
                              roundIndex]!['${game.league.name}_marginUPS']! +
                          marginUPS;
                }
              } // end of game started check
            } // end of tip not null check
          } // end of game loop

          // save the consolidated afl + nrl score to consolidatedScoresForRanking
          // this will be used to rank tippers per round
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
              'round_total_score'] = scoringTipperRoundTotals[
                  tipperToScore.dbkey]![roundIndex]!['afl_score']! +
              scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]![
                  'nrl_score']!;
        } // end of round loops
      } // end of tipper loop

      // rank each tipper for each round using the round_total_score
      // tippers on the same score will have the same rank

      /// if this is a full scoring update,
      /// loop through each round and rank the tippers
      /// we will use the round_total_score to rank the tippers

      if (onlyUpdateThisRound == null) {
        for (var roundIndex = 0;
            roundIndex < daucompToUpdate.daurounds!.length;
            roundIndex++) {
          // get the round total scores for each tipper
          List<MapEntry<String, int>> roundScores = [];
          for (var tipper in tippers) {
            roundScores.add(MapEntry(
                tipper.dbkey!,
                scoringTipperRoundTotals[tipper.dbkey]![roundIndex]![
                    'round_total_score']!));
          }

          // sort the tippers by score
          roundScores.sort((a, b) => b.value.compareTo(a.value));

          // assign the rank to each tipper
          // tippers on the same score will have the same rank
          int rank = 1;
          int? lastScore;
          int sameRankCount = 0;

          for (var entry in roundScores) {
            if (lastScore != null && entry.value != lastScore) {
              rank += sameRankCount + 1;
              sameRankCount = 0;
            } else if (lastScore != null && entry.value == lastScore) {
              sameRankCount++;
            }
            scoringTipperRoundTotals[entry.key]![roundIndex]!['rank'] = rank;

            // calculate the change in rank from the previous round
            if (roundIndex > 0) {
              int? lastRank =
                  scoringTipperRoundTotals[entry.key]![roundIndex - 1]!['rank'];
              int? changeInRank = lastRank! - rank;
              scoringTipperRoundTotals[entry.key]![roundIndex]![
                  'changeInRank'] = changeInRank;
            }
            lastScore = entry.value;
          }
        }
      }

      scoresViewModel ??= ScoresViewModel(_selectedDAUCompDbKey);

      await scoresViewModel?.writeScoresToDb(
          scoringTipperRoundTotals, scoringTipperCompTotals, daucompToUpdate);

      return 'Completed scoring updates for ${tippers.length} tippers and ${daucompToUpdate.daurounds!.length} games.';
    } finally {
      _isScoring = false;
      notifyListeners();
    }
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
      for (var gameKey in round.gamesAsKeys) {
        Game? game = await userGamesViewModel!.findGame(gameKey);
        if (game != null) {
          if (game.gameState == GameState.notStarted ||
              game.gameState == GameState.startingSoon) {
            allGamesPlayed = false;
            break;
          }
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

  @override
  void dispose() {
    _daucompsStream.cancel(); // stop listening to stream
    userGamesViewModel?.removeListener(update);

    // create a new Completer if the old one was completed:
    if (_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter = Completer<void>();
    }
    super.dispose();
  }
}
