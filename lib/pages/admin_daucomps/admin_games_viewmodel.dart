import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/location_latlong.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

const gamesPathRoot = '/DAUCompsGames';

class GamesViewModel extends ChangeNotifier {
  // Properties
  List<Game> _games = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _gamesStream;

  bool _savingGame = false;
  Completer<void> _initialLoadCompleter = Completer<void>();

  String currentDAUComp;
  late TeamsViewModel _teamsViewModel;

  // Getters
  //List<Game> get games => _games;
  Future<List<Game>> getGames() async {
    await initialLoadComplete;
    return _games;
  }

  bool get savingGame => _savingGame;
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  // Constructor
  GamesViewModel(this.currentDAUComp) {
    _teamsViewModel = TeamsViewModel();
    _listenToGames();
  }

  // Database listeners
  void _listenToGames() {
    _gamesStream =
        _db.child('$gamesPathRoot/$currentDAUComp').onValue.listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('***GamesViewModel_handleEvent()***');
      if (event.snapshot.exists) {
        final allGames =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        // Deserialize the games
        List<Game> gamesList =
            await Future.wait(allGames.entries.map((entry) async {
          String key = entry.key; // Retrieve the Firebase key
          String league = key.split('-').first;
          dynamic gameAsJSON = entry.value;

          //we need to deserialize the locationlatlng before we can deserialize the game
          LatLng? locationLatLng;
          if (gameAsJSON['locationLatLng'] != null) {
            locationLatLng = LatLng.fromJson(
                Map<String, dynamic>.from(gameAsJSON['locationLatLng']));
          }
          //we need to find and deserialize the home and away teams first before we can deserialize the game
          Team? homeTeam = await _teamsViewModel
              .findTeam('$league-${gameAsJSON['HomeTeam']}');
          Team? awayTeam = await _teamsViewModel
              .findTeam('$league-${gameAsJSON['AwayTeam']}');

          Scoring? scoring = Scoring(
              homeTeamScore: gameAsJSON['HomeTeamScore'],
              awayTeamScore: gameAsJSON['AwayTeamScore']);

          if (homeTeam != null && awayTeam != null) {
            log('Game: $key about to be deserialized');
            Game game = Game.fromFixtureJson(
                key, Map<String, dynamic>.from(gameAsJSON), homeTeam, awayTeam);
            game.locationLatLong = locationLatLng;
            game.scoring = scoring;
            return game;
          } else {
            // homeTeam or awayTeam should not be null
            throw Exception(
                'Error in GamesViewModel_handleEvent: homeTeam or awayTeam is null');
          }
        }).toList());

        //_games = gamesList.where((game) => game != null).cast<Game>().toList();
        _games = gamesList;
        _games.sort();
      } else {
        log('No games found for DAUComp $currentDAUComp');
      }
    } catch (e) {
      log('Error in GamesViewModel_handleEvent: $e');
      rethrow;
    } finally {
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
    }
  }

/*   // Game operations // TODO this function can be deleted
  Future<Map<int, List<Game>>> getNestedGames() async {
    log('getNestedGames() waiting for initial Game load to complete');
    await initialLoadComplete;
    log('getNestedGames() COMPLETED waiting for initial Game load to complete');

    _nestedGroups = groupBy(_games, (game) => game.combinedRoundNumber);

    return _nestedGroups;
  } */

  //method to get default tips for a given combined round number and league
  /*  Future<String> getDefaultTipsForCombinedRoundNumber_OLD(
      int combinedRoundNumber) async {
    log('getDefaultTipsForCombinedRoundNumber() waiting for initial Game load to complete');
    await initialLoadComplete;
    log('getDefaultTipsForCombinedRoundNumber() initial Game load to COMPLETED');

    //filter _games to find all games where combinedRoundNumber == combinedRoundNumber and league == league
    List<Game> filteredNrlGames = _games
        .where((game) =>
            game.combinedRoundNumber == combinedRoundNumber &&
            game.league == League.nrl)
        .toList();

    List<Game> filteredAflGames = _games
        .where((game) =>
            game.combinedRoundNumber == combinedRoundNumber &&
            game.league == League.afl)
        .toList();

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
 */
  final Map<String, dynamic> updates = {};

  Future<void> updateGameAttribute(String gameDbKey, String attributeName,
      dynamic attributeValue, String league) async {
    await _initialLoadCompleter.future;

    //make sure the related team records exist
    if (attributeName == 'HomeTeam' || attributeName == 'AwayTeam') {
      Team team = Team(
          dbkey: '$league-$attributeValue',
          name: attributeValue,
          league: League.values.firstWhere((e) => e.name == league));
      //make sure the related team records exist
      _teamsViewModel.addTeam(team);
    }

    //find the game in the local list. it it's there, compare the attribute value and update if different
    Game? gameToUpdate = await findGame(gameDbKey);
    if (gameToUpdate != null) {
      dynamic oldValue = gameToUpdate.toFixtureJson()[attributeName];
      if (attributeValue != oldValue) {
        log('Game: $gameDbKey needs update for attribute $attributeName: $attributeValue');
        updates['$gamesPathRoot/$currentDAUComp/$gameDbKey/$attributeName'] =
            attributeValue;
      } else {
        log('Game: $gameDbKey already has $attributeName: $attributeValue');
      }
    } else {
      log('Game: $gameDbKey not found in local list. adding full game record');
      // add new record to updates Map
      updates['$gamesPathRoot/$currentDAUComp/$gameDbKey/$attributeName'] =
          attributeValue;
    }
  }

  Future<void> saveBatchOfGameAttributes() async {
    try {
      await initialLoadComplete;
      await _db.update(updates);
    } finally {
      _savingGame = false;
      notifyListeners();
    }
  }

  Future<Game?> findGame(String gameDbKey) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for Game load to complete findGame()');
    }
    await _initialLoadCompleter.future;
    return _games.firstWhereOrNull((game) => game.dbkey == gameDbKey);
  }

  // Method to return the current combined round number.
  // From this list of all games, exclude those where the gamestate
  // is 'resultKnown'.
  // of the remaining games sort my gamestarttimeutc and
  //return the combinedRoundNumber of the first game in the list

  /* Future<int> getCurrentCombinedRoundNumber_OLC() async {
    log('getCurrentCombinedRoundNumber() waiting for initial Game load to complete');
    await _initialLoadCompleter.future;
    log('getCurrentCombinedRoundNumber() initial Game load COMPLETED');

    int currentCombinedRoundNumber =
        0; // TODO test UI behaviour with this set to 0
    List<Game> gamesToProcess = [];
    for (var game in _games) {
      if (game.gameState == GameState.resultNotKnown ||
          game.gameState == GameState.notStarted) {
        gamesToProcess.add(game);
      }
    }
    gamesToProcess.sort((a, b) => a.startTimeUTC.compareTo(b.startTimeUTC));
    if (gamesToProcess.isNotEmpty) {
      Game firstGame = gamesToProcess.first;
      // find this game in the DAUCompsViewModel to get the combinedRoundNumber
      
      currentCombinedRoundNumber = gamesToProcess.first.combinedRoundNumber;
    }
    if (currentCombinedRoundNumber == 0) {
      log('getCurrentCombinedRoundNumber() - no games found with gamestate == GameState.notStarted ot GameState.resultNotKnown');
    }
    return currentCombinedRoundNumber;
  } */

  // Cleanup
  @override
  void dispose() {
    _gamesStream.cancel(); // stop listening to stream

    // create a new Completer if the old one was completed:
    if (_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter = Completer<void>();
    }

    super.dispose();
  }
}
