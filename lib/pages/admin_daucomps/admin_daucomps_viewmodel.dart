import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_tips_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

// define constant for firestore database locations - TODO move to env file
const daucompsPath = '/DAUComps';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];

  String selectedDAUCompDBKey = '';

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _daucompsStream;

  late GamesViewModel _gamesViewModel;

  String _currentDAUComp;
  String get currentDAUComp => _currentDAUComp;
  void setCurrentDAUComp(String newDAUComp) {
    _currentDAUComp = newDAUComp;
    //reset the gamesViewModel
    _gamesViewModel = GamesViewModel(_currentDAUComp);

    notifyListeners();
  }

  bool _savingDAUComp = false;
  bool get savingDAUComp => _savingDAUComp;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

  //constructor
  DAUCompsViewModel(this._currentDAUComp) {
    _gamesViewModel = GamesViewModel(_currentDAUComp);
    _listenToDAUComps();
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

          return DAUComp.fromJson(
              Map<String, dynamic>.from(daucompAsJSON), key, daurounds);
        }).toList();

        //_daucomps.sort();
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

  Future<String> getNetworkFixtureData(DAUComp daucompToUpdate) async {
    try {
      if (!_initialLoadCompleter.isCompleted) {
        log('getNetworkFixtureData() waiting for initial DAUCompsViewModel load to complete');
      }
      await initialLoadComplete;
      _isDownloading = true;
      notifyListeners();

      FixtureDownloadService fds = FixtureDownloadService();

      List<dynamic> nrlGames = [];
      try {
        nrlGames = await fds.getLeagueFixtureRaw(
            daucompToUpdate.nrlFixtureJsonURL, League.nrl);
      } catch (e) {
        throw 'Error loading NRL fixture data. Exception was: $e';
        //return 'Error loading NRL fixture data. Exception was: $e'; // TODO - exceptions is not being passed to caller
      }

      List<dynamic> aflGames = [];
      try {
        aflGames = await fds.getLeagueFixtureRaw(
            daucompToUpdate.aflFixtureJsonURL, League.afl);
      } catch (e) {
        throw 'Error loading AFL fixture data. Exception was: $e';

        //return 'Error loading AFL fixture data. Exception was: $e';  // TODO - exceptions is not being passed to caller
      }

      GamesViewModel gamesViewModel = GamesViewModel(daucompToUpdate.dbkey!);

      List<Future> gamesFuture = [];

      for (var gamejson in nrlGames) {
        String dbkey =
            '${League.nrl.name}-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        for (var attribute in gamejson.keys) {
          gamesFuture.add(gamesViewModel.updateGameAttribute(
              dbkey, attribute, gamejson[attribute], League.nrl.name));
        }
      }

      for (var gamejson in aflGames) {
        String dbkey =
            '${League.afl.name}-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        for (var attribute in gamejson.keys) {
          gamesFuture.add(gamesViewModel.updateGameAttribute(
              dbkey, attribute, gamejson[attribute], League.afl.name));
        }
      }

      await Future.wait(gamesFuture);

      //save all updates
      await gamesViewModel.saveBatchOfGameAttributes();

      //once all the data is loaded, update all scoring
      //updateScoring(daucompToUpdate, gamesViewModel);

      //once all the data is loaded, update the combinedRound field
      updateCombinedRoundNumber(daucompToUpdate, gamesViewModel);

      return 'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<String> syncTipsWithLegacy(DAUComp newdaucomp) async {
    try {
      await initialLoadComplete;

      _isLegacySyncing = true;
      notifyListeners();

      //get reference to legacy tipping service so that we can sync tips
      LegacyTippingService tippingService =
          GetIt.instance<LegacyTippingService>();

      TippersViewModel tippersViewModel = TippersViewModel(null);

      AllTipsViewModel allTipsViewModel = AllTipsViewModel(
          tippersViewModel, newdaucomp.dbkey!, _gamesViewModel);

      //sync tips to legacy
      await tippingService.initialized();
      return await tippingService.syncTipsToLegacyDiffOnly(
          allTipsViewModel, this);
    } finally {
      _isLegacySyncing = false;
      notifyListeners();
    }
  }

  // lets group the games for NRL and AFL into our own combined rounds based on this logic:
  // 1) Each league has games grouped by round number - the logic should preserve this grouping
  // 2) group the games by Game.league and Game.roundNumber
  // 3) find the min Game.startTimeUTC for each league-roundnumber group - this is the start time of the group of games
  // 4) find the max Game.startTimeUTC for each group - this is the end time of the group of games
  // 5) sort the groups by the min Game.startTimeUTC
  // 6) take the 1st group, this will be the basis for our combined AFL and NRL round 1
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
      //find the DAUComp in the local list. it it's there, compare the attribute value and update if different
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
    await initialLoadComplete;
    return _daucomps;
  }

  //method to get a List<int> of the combined round numbers
  Future<List<int>> getCombinedRoundNumbers() async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getCombinedRoundNumbers() waiting for initial Game load to complete');
    }

    await initialLoadComplete;

    //get the current DAUComp
    DAUComp? daucomp = await findComp(_currentDAUComp);

    List<int> combinedRoundNumbers = [];
    for (var round in daucomp!.daurounds!) {
      combinedRoundNumbers.add(round.dAUroundNumber);
    }

    combinedRoundNumbers.sort();
    return combinedRoundNumbers;
  }

  //method to get a List<Game> of the games for a given combined round number and league
  Future<List<Game>> getGamesForCombinedRoundNumberAndLeague(
      int combinedRoundNumber, League league) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getGamesForCombinedRoundNumberAndLeague() waiting for initial Game load to complete');
    }
    await initialLoadComplete;

    List<Game> gamesForCombinedRoundNumberAndLeague = [];
    DAUComp? daucomp = await findComp(_currentDAUComp);
    for (var round in daucomp!.daurounds!) {
      if (round.dAUroundNumber == combinedRoundNumber) {
        for (var gameKey in round.gamesAsKeys) {
          Game? game = await _gamesViewModel.findGame(gameKey);
          if (game != null && game.league == league) {
            // allow for reverse lookup of round from a game object
            game.dauRound = daucomp.daurounds![combinedRoundNumber - 1];
            log('Associating game record ${game.dbkey} to combined round: ${daucomp.daurounds![combinedRoundNumber - 1].dAUroundNumber}');
            //add the game to the list
            gamesForCombinedRoundNumberAndLeague.add(game);
          }
        }
      }
    }

    return gamesForCombinedRoundNumberAndLeague;
  }

  //method to get default tips for a given combined round number and league
  Future<String> getDefaultTipsForCombinedRoundNumber(
      int combinedRoundNumber) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('getDefaultTipsForCombinedRoundNumber() waiting for initial Game load to complete');
    }
    await initialLoadComplete;

    //filter games to find all games where combinedRoundNumber == combinedRoundNumber and league == league
    List<Game> filteredNrlGames = await getGamesForCombinedRoundNumberAndLeague(
        combinedRoundNumber, League.nrl);

    //filter games to find all games where combinedRoundNumber == combinedRoundNumber and league == league
    List<Game> filteredAflGames = await getGamesForCombinedRoundNumberAndLeague(
        combinedRoundNumber, League.afl);

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

  @override
  void dispose() {
    _daucompsStream.cancel(); // stop listening to stream
    super.dispose();
  }

  /* void updateScoring(DAUComp daucompToUpdate, GamesViewModel gamesViewModel) {
    //using GamesViewModel.getGames() filter games where HomeTeamScore and AwayTeamScore are not null
    //then for each game, calculate the game result and update the game result attribute

    // loop through all tippers
    TippersViewModel tippersViewModel = TippersViewModel();
    tippersViewModel.getTippers().then((tippers) {
      for (var tipper in tippers) {
        // keep track of afl and nrl ladder scores per tipper
        int ladderAflScore = 0;
        int latterNrlScore = 0;

        // loop through each round and then each league and total up the score for this tipper
        for (var round in daucompToUpdate.daurounds!) {
          for (var gameKey in round.gamesAsKeys) {
            gamesViewModel.findGame(gameKey).then((game) {
              if (game != null &&
                  game.scoring != null &&
                  game.scoring!.homeTeamScore != null &&
                  game.scoring!.awayTeamScore != null) {
                AllTipsViewModel adminTipsViewModel = AllTipsViewModel(
                    tippersViewModel, daucompToUpdate.dbkey!, gamesViewModel);
                adminTipsViewModel.getLatestGameTip(game, tipper).then((tip) {
                  if (tip != null) {
                    //calculate the game result
                    GameResult gameResult =
                        game.scoring!.getGameResultCalculated(game.league);
                    //update the tip result
                    adminTipsViewModel.updateTipAttribute(
                        tip, 'result', gameResult);
                  }
                });
              }
            });
          }
        }
      }
    });
    //update consolidated scoring for all tippers in the comp
    AllTipsViewModel allTipsViewModel =
        AllTipsViewModel(_currentDAUComp, gamesViewModel, this);
  } */
}
