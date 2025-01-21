import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/location_latlong.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

const gamesPathRoot = '/DAUCompsGames';

class GamesViewModel extends ChangeNotifier {
  // Properties
  List<Game> _games = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _gamesStream;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  DAUComp selectedDAUComp;
  late TeamsViewModel _teamsViewModel;

  final List<DAURound> _roundsThatNeedScoringUpdate = [];

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

      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }

      // Now that we have all the games from db
      // call linkGamesWithRounds() to link the games with the rounds
      DAUCompsViewModel dauCompsViewModel = di<DAUCompsViewModel>();
      await dauCompsViewModel.linkGameWithRounds(selectedDAUComp, this);

      // now that we know the state of each roumd,  setup the fixture download trigger
      await dauCompsViewModel.fixtureUpdateTrigger();

      notifyListeners();
      log('GamesViewModel_handleEvent: notifyListeners()');
    } catch (e) {
      log('Error in GamesViewModel_handleEvent: $e');
      if (!_initialLoadCompleter.isCompleted) _initialLoadCompleter.complete();
      rethrow;
    }
  }

  final Map<String, dynamic> updates = {};

  Future<void> updateGameAttribute(String gameDbKey, String attributeName,
      dynamic attributeValue, String league) async {
    await initialLoadComplete;

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
          // the score has changed, add the round to the list of rounds that need scoring updates
          // avoid adding rounds multiple times
          if (!_roundsThatNeedScoringUpdate
              .contains(gameToUpdate.getDAURound(selectedDAUComp))) {
            _roundsThatNeedScoringUpdate
                .add(gameToUpdate.getDAURound(selectedDAUComp));
          }
        }
      }
    } else {
      log('Game: $gameDbKey not found in local list. adding full game record');
      // add new record to updates Map
      updates['$gamesPathRoot/${selectedDAUComp.dbkey}/$gameDbKey/$attributeName'] =
          attributeValue;
    }
  }

  Future<void> saveBatchOfGameAttributes() async {
    try {
      // check if there are any updates to save
      if (updates.isEmpty) {
        log('GamesViewModel_saveBatchOfGameAttributes: no updates to save');
        return;
      }
      await initialLoadComplete;
      // turn off listeners
      _gamesStream.cancel();
      await _db.update(updates);
      // turn listeners back on
      _listenToGames();

      // if any game scores have changes, the round will be flagged for scoring
      // update in List<DAURound> _roundsThatNeedScoringUpdate
      // update the round scores then remove the round from the list
      for (DAURound dauRound in _roundsThatNeedScoringUpdate) {
        log('GamesViewModel_saveBatchOfGameAttributes: updating scoring for round ${dauRound.dAUroundNumber}');
        await di<StatsViewModel>().updateStats(selectedDAUComp, dauRound, null);
      }
      // clear the list
      _roundsThatNeedScoringUpdate.clear();
    } finally {
      notifyListeners();
      log('GamesViewModel_saveBatchOfGameAttributes: notifyListeners()');
    }
  }

  Future<List<Game>> getGames() async {
    await initialLoadComplete;
    return _games;
  }

  Future<Game?> findGame(String gameDbKey) async {
    await initialLoadComplete;
    return _games.firstWhereOrNull((game) => game.dbkey == gameDbKey);
  }

  Future<List<Game>> getGamesForRound(DAURound dauRound) async {
    await initialLoadComplete;
    List<Game> gamesForRound =
        _games.where((game) => (game.isGameInRound(dauRound))).toList();

    // TODO hack - for the 2024 comp exclude games with the following dbkeys:
    // afl-25-208
    // afl-25-209
    // afl-25-210
    // afl-25-211

    if (selectedDAUComp.dbkey == '-Nk88l-ww9pYF1j_jUq7') {
      gamesForRound.removeWhere((game) => game.dbkey == 'afl-25-208');
      gamesForRound.removeWhere((game) => game.dbkey == 'afl-25-209');
      gamesForRound.removeWhere((game) => game.dbkey == 'afl-25-210');
      gamesForRound.removeWhere((game) => game.dbkey == 'afl-25-211');
    }

    return gamesForRound;
  }

  @override
  void dispose() {
    _gamesStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
