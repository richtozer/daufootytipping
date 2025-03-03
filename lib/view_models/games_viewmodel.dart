import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
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
  get teamsViewModel => _teamsViewModel;

  final List<DAURound> _roundsThatNeedScoringUpdate = [];

  final DAUCompsViewModel _dauCompsViewModel;

  bool _isUpdating = false;

  // Constructor
  GamesViewModel(this.selectedDAUComp, this._dauCompsViewModel) {
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
    if (_isUpdating) {
      log('GamesViewModel_handleEvent: _isUpdating is true. Returning.');
      return; // Prevent re-entrant updates
    }
    _isUpdating = true;
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
      await _dauCompsViewModel.linkGameWithRounds(selectedDAUComp, this);
    } catch (e) {
      log('Error in GamesViewModel_handleEvent: $e');
      if (!_initialLoadCompleter.isCompleted) _initialLoadCompleter.complete();
      rethrow;
    } finally {
      notifyListeners();
      log('GamesViewModel_handleEvent: notifyListeners()');
      _isUpdating = false;
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
    if (_isUpdating) return; // Prevent re-entrant updates
    _isUpdating = true;
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
        await di<StatsViewModel>()
            .updateStats(selectedDAUComp, dauRound, null, null);
      }
      // clear the list
      _roundsThatNeedScoringUpdate.clear();
    } finally {
      log('GamesViewModel_saveBatchOfGameAttributes: notifyListeners()');
      _isUpdating = false;
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

    // if (dauRound.dAUroundNumber == 27) {
    //   log('Round 27 detected. TESTING.');
    // }
    List<Game> gamesForRound =
        _games.where((game) => (game.isGameInRound(dauRound))).toList();

    // loop through the games and remove any where the startTimeUTC is past aflRegularCompEndDateUTC or nrlRegularCompEndDateUTC
    removeGamesOutsideRegularComp(gamesForRound);

    return gamesForRound;
  }

  void removeGamesOutsideRegularComp(List<Game> gamesForRound) {
    // loop through the games and remove any where the startTimeUTC is past aflRegularCompEndDateUTC or nrlRegularCompEndDateUTC
    gamesForRound.removeWhere((game) {
      bool shouldRemove = false;

      if (game.league == League.afl &&
          selectedDAUComp.aflRegularCompEndDateUTC != null) {
        shouldRemove = game.startTimeUTC
            .isAfter(selectedDAUComp.aflRegularCompEndDateUTC!);
      } else if (game.league == League.nrl &&
          selectedDAUComp.nrlRegularCompEndDateUTC != null) {
        shouldRemove = game.startTimeUTC
            .isAfter(selectedDAUComp.nrlRegularCompEndDateUTC!);
      }

      if (shouldRemove) {
        log('removeGamesOutsideRegularComp() Removing game: ${game.dbkey}, Start Time: ${game.startTimeUTC}');
      }

      return shouldRemove;
    });
  }

  @override
  void dispose() {
    _gamesStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
