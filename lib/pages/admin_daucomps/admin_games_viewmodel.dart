import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/location_latlong.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:json_diff/json_diff.dart';

const gamesPathRoot = '/DAUCompsGames';

class GamesViewModel extends ChangeNotifier {
  // Properties
  List<Game> _games = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _gamesStream;
  late Map<int, List<Game>> _nestedGroups;
  bool _savingGame = false;
  Completer<void> _initialLoadCompleter = Completer<void>();

  String parentDAUCompDBkey;
  late TeamsViewModel _teamsViewModel;

  // Getters
  List<Game> get games => _games;
  bool get savingGame => _savingGame;
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  // Constructor
  GamesViewModel(this.parentDAUCompDBkey) {
    _teamsViewModel = TeamsViewModel();
    _listenToGames();
  }

  // Database listeners
  void _listenToGames() {
    _gamesStream =
        _db.child('$gamesPathRoot/$parentDAUCompDBkey').onValue.listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        final allGames =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        List<Game?> gamesList =
            await Future.wait(allGames.entries.map((entry) async {
          String key = entry.key; // Retrieve the Firebase key
          dynamic gameAsJSON = entry.value;

          //we need to deserialize the locationlatlng before we can deserialize the game
          LatLng? locationLatLng;
          if (gameAsJSON['locationLatLng'] != null) {
            locationLatLng = LatLng.fromJson(
                Map<String, dynamic>.from(gameAsJSON['locationLatLng']));
          }
          //we need to find and deserialize the home and away teams first before we can deserialize the game
          Team? homeTeam =
              await _teamsViewModel.findTeam(gameAsJSON['homeTeamDbKey']);
          Team? awayTeam =
              await _teamsViewModel.findTeam(gameAsJSON['awayTeamDbKey']);

          if (homeTeam != null && awayTeam != null) {
            return Game.fromJson(Map<String, dynamic>.from(gameAsJSON), key,
                homeTeam, awayTeam, locationLatLng);
          } else {
            // Handle the case where homeTeam or awayTeam is null
            throw Exception(
                'Error in GamesViewModel_handleEvent: homeTeam or awayTeam is null');
          }
        }).toList());

        _games = gamesList.where((game) => game != null).cast<Game>().toList();
        _games.sort();
      } else {
        log('No games found for DAUComp $parentDAUCompDBkey');
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

  //method to get a List<int> of the combined round numbers
  Future<List<int>> getCombinedRoundNumbers() async {
    log('getCombinedRoundNumbers() waiting for initial Game load to complete');
    await initialLoadComplete;
    log('getCombinedRoundNumbers() initial Game load COMPLETED');

    List<int> combinedRoundNumbers = [];
    for (var game in _games) {
      if (!combinedRoundNumbers.contains(game.combinedRoundNumber)) {
        combinedRoundNumbers.add(game.combinedRoundNumber);
      }
    }
    combinedRoundNumbers.sort();
    return combinedRoundNumbers;
  }

  //method to get a List<Game> of the games for a given combined round number and league
  Future<List<Game>> getGamesForCombinedRoundNumberAndLeague(
      int combinedRoundNumber, League league) async {
    log('getGamesForCombinedRoundNumberAndLeague() waiting for initial Game load to complete');
    await initialLoadComplete;
    log('getGamesForCombinedRoundNumberAndLeague() COMPLETED waiting for initial Game load to complete');

    List<Game> gamesForCombinedRoundNumberAndLeague = [];
    for (var game in _games) {
      if (game.combinedRoundNumber == combinedRoundNumber &&
          game.league == league) {
        gamesForCombinedRoundNumberAndLeague.add(game);
      }
    }
    return gamesForCombinedRoundNumberAndLeague;
  }

  // Game operations
  Future<Map<int, List<Game>>> getNestedGames() async {
    log('getNestedGames() waiting for initial Game load to complete');
    await initialLoadComplete;
    log('getNestedGames() COMPLETED waiting for initial Game load to complete');

    _nestedGroups = groupBy(_games, (game) => game.combinedRoundNumber);

    return _nestedGroups;
  }

  //method to get default tips for a given combined round number and league
  Future<String> getDefaultTipsForCombinedRoundNumber(
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

  Future<void> updateGame(Game updatedGame) async {
    await _initialLoadCompleter.future;
    _savingGame = true;
    notifyListeners();

    Game? originalGame = _games.firstWhereOrNull(
        (existingGame) => existingGame.dbkey == updatedGame.dbkey);

    if (originalGame != null) {
      // preserve the original game's locationLatLng and combinedRoundNumber
      //updatedGame.locationLatLng = originalGame.locationLatLng;
      if (originalGame.combinedRoundNumber != 0) {
        updatedGame.combinedRoundNumber = originalGame.combinedRoundNumber;
      }

      _editGame(updatedGame, originalGame);
    } else {
      log('Game: ${updatedGame.dbkey} does not exist in the database, adding record');
      _addGame(updatedGame);
    }

    _savingGame = false;
    notifyListeners();
  }

  Future<void> _addGame(Game gameData) async {
    try {
      _savingGame = true;
      notifyListeners();

      //make sure the related team records exist
      _teamsViewModel.addTeam(gameData.awayTeam);
      _teamsViewModel.addTeam(gameData.homeTeam);

      final postData = gameData.toJson();

      final Map<String, Map> updates = {};
      updates['$gamesPathRoot/$parentDAUCompDBkey/${gameData.dbkey}'] =
          postData;

      await _db.update(updates);
    } finally {
      _savingGame = false;
      notifyListeners();
    }
  }

  Future<void> _editGame(Game updatedGame, Game originalGame) async {
    await _initialLoadCompleter.future;
    log('Initial game load completed. editGame()');

    // Convert the original and updated game to JSON
    Map<String, dynamic> originalJson = originalGame.toJson();
    Map<String, dynamic> updatedJson = updatedGame.toJson();

    // Use JsonDiffer to get the differences
    JsonDiffer differ = JsonDiffer.fromJson(originalJson, updatedJson);
    DiffNode diff = differ.diff();

    // Initialize an empty map to hold all updates
    Map<String, dynamic> updates = {};

    //log('Game: $gamesPathRoot/${updatedGame.dbkey} has: ${diff.changed.length} changes.');
    // transform the changes from JsonDiffer format to Firebase format
    Map changed = diff.changed;
    changed.keys.toList().forEach((key) async {
      if (changed[key] is List && (changed[key] as List).isNotEmpty) {
        // Add the update to the updates map
        updates['$gamesPathRoot/$parentDAUCompDBkey/${updatedGame.dbkey}/$key'] =
            changed[key][1];

        // Apply any updates to Firebase
        try {
          _savingGame = true;
          notifyListeners();
          await _db.update(updates);
          log('Game updated in db to: $updates');

          // Log the event to Firebase Analytics
          FirebaseAnalytics.instance.logEvent(
            name: 'game_updated',
            parameters: <String, dynamic>{
              'game_key': updatedGame.dbkey,
              'update': updates.toString(), //TODO - check is this is working
            },
          );
        } finally {
          _savingGame = false;
          notifyListeners();
        }
      } else {
        log('Game: $gamesPathRoot/${updatedGame.dbkey} has: no changes.');
      }
    });
  }

  Future<Game?> findGame(String gameDbKey) async {
    await _initialLoadCompleter.future;
    log('initial Game load to complete  findGame()');
    return _games.firstWhereOrNull((game) => game.dbkey == gameDbKey);
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
  void updateCombinedRoundNumber() {
    log('In updateCombinedRoundNumber()');

    // Group games by league and round number
    var groups = groupBy(_games, (g) => '${g.league}-${g.roundNumber}');

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

    // Update combined round number for each game
    for (var i = 0; i < combinedRounds.length; i++) {
      for (var game in combinedRounds[i]) {
        if (game.combinedRoundNumber != i + 1) {
          log('Updating combined round number for game: ${game.dbkey}');
          Game updatedGame = Game(
              matchNumber: game.matchNumber,
              awayTeam: game.awayTeam,
              homeTeam: game.homeTeam,
              league: game.league,
              roundNumber: game.roundNumber,
              startTimeUTC: game.startTimeUTC,
              location: game.location,
              dbkey: game.dbkey,
              combinedRoundNumber: i + 1);
          updateGame(updatedGame); //write changes to firebase
        } else {
          log('Game: ${game.dbkey} already has combined round number: ${game.combinedRoundNumber}');
        }
      }
    }
    log('out updateCombinedRoundNumber()');
  }

  // Method to return the current combined round number.
  // From this list of all games, exclude those where the gamestate
  // is 'resultKnown'.
  // of the remaining games sort my gamestarttimeutc and
  //return the combinedRoundNumber of the first game in the list

  Future<int> getCurrentCombinedRoundNumber() async {
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
      currentCombinedRoundNumber = gamesToProcess.first.combinedRoundNumber;
    }
    if (currentCombinedRoundNumber == 0) {
      log('getCurrentCombinedRoundNumber() - no games found with gamestate == GameState.notStarted ot GameState.resultNotKnown');
    }
    return currentCombinedRoundNumber;
  }

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
