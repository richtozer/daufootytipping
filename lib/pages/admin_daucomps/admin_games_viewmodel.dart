import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/location_latlong.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

const gamesPathRoot = '/DAUCompsGames';

class GamesViewModel extends ChangeNotifier {
  // Properties
  List<Game> _games = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _gamesStream;

  bool _savingGame = false;
  Completer<void> _initialLoadCompleter = Completer<void>();

  DAUComp selectedDAUComp;
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
  GamesViewModel(this.selectedDAUComp) {
    _teamsViewModel = TeamsViewModel();
    _listenToGames();
  }

  // Database listeners
  void _listenToGames() {
    _gamesStream = _db
        .child('$gamesPathRoot/${selectedDAUComp.dbkey}')
        .onValue
        .listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        final allGames =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        // Deserialize the games
        List<Game> gamesList =
            await Future.wait(allGames.entries.map((entry) async {
          String dbKey = entry.key; // Retrieve the Firebase key
          String league = dbKey.split('-').first;
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
            Game game = Game.fromFixtureJson(dbKey,
                Map<String, dynamic>.from(gameAsJSON), homeTeam, awayTeam);
            game.locationLatLong = locationLatLng;
            game.scoring = scoring;

            return game;
          } else {
            // homeTeam or awayTeam should not be null
            throw Exception(
                'Error in GamesViewModel_handleEvent: homeTeam or awayTeam is null');
          }
        }).toList());

        _games = gamesList;
        _games.sort();
        log('GamesViewModel_handleEvent: ${_games.length} games found for DAUComp ${selectedDAUComp.name}');
      } else {
        log('No games found for DAUComp ${selectedDAUComp.name}');
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

  final Map<String, dynamic> updates = {};

  Future<void> updateGameAttribute(String gameDbKey, String attributeName,
      dynamic attributeValue, String league) async {
    await _initialLoadCompleter.future;

    bool flagScoresUpdated = false;

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
      dynamic oldValue = gameToUpdate.toJson()[attributeName];
      if (attributeValue != oldValue) {
        log('Game: $gameDbKey needs update for attribute $attributeName: $attributeValue');
        updates['$gamesPathRoot/${selectedDAUComp.dbkey}/$gameDbKey/$attributeName'] =
            attributeValue;
        if (attributeName == 'HomeTeamScore' ||
            attributeName == 'AwayTeamScore') {
          flagScoresUpdated = true;
        }
      }
    } else {
      log('Game: $gameDbKey not found in local list. adding full game record');
      // add new record to updates Map
      updates['$gamesPathRoot/${selectedDAUComp.dbkey}/$gameDbKey/$attributeName'] =
          attributeValue;
    }

    // if the scores have been updated, we need to update scoring
    if (flagScoresUpdated) {
      // String result = await di<DAUCompsViewModel>()
      //     .updateScoring(selectedDAUComp, null, linkedDauRound); // TODO updating scores for only a single round - does not work
      String result = await di<ScoresViewModel>()
          .calculateScoring(selectedDAUComp, null, null);

      log('updateScoring result: $result');
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
      await _initialLoadCompleter.future;
    }
    return _games.firstWhereOrNull((game) => game.dbkey == gameDbKey);
  }

  Future<List<Game>> getGamesForRound(DAURound dauRound) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for Game load to complete findGame()');
      await _initialLoadCompleter.future;
    }

    List<Game> gamesForRound =
        _games.where((game) => (game.isGameInRound(dauRound))).toList();

    return gamesForRound;
  }

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
