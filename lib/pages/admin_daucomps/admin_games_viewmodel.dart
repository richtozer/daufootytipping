import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daurounds_viewmodel.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const gamesPathRoot = '/DAUCompsGames';

class GamesViewModel extends ChangeNotifier {
  List<Game> _games = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _gamesStream;
  bool _savingGame = false;
  bool _initialLoadComplete =
      true; //TODO if our concunrrency model is ok now, we can remove this check
  String parentDAUCompDBkey;

  Map _groupedGames = {};
  Map get groupedGames => _groupedGames;

  final TeamsViewModel _teamsViewModel;
  final DAURoundsViewModel _dauRoundsViewModel;

  List<Game> get games => _games;
  bool get savingGame => _savingGame;

  //constructor
  GamesViewModel(
      this.parentDAUCompDBkey, this._teamsViewModel, this._dauRoundsViewModel) {
    _listenToGames();
  }

  void _listenToGames() {
    _gamesStream =
        _db.child('$gamesPathRoot/$parentDAUCompDBkey').onValue.listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    if (event.snapshot.exists) {
      final allGames =
          Map<String, dynamic>.from(event.snapshot.value as dynamic);

      List<Game?> gamesList =
          await Future.wait(allGames.entries.map((entry) async {
        String key = entry.key; // Retrieve the Firebase key
        dynamic gameAsJSON = entry.value;

        //we need to find and deserialize the DAuROund, home and away teams first before we can deserialize the game
        Team? homeTeam =
            await _teamsViewModel.findTeam(gameAsJSON['homeTeamDbKey']);
        Team? awayTeam =
            await _teamsViewModel.findTeam(gameAsJSON['awayTeamDbKey']);

        DAURound? dauRound;
        if (gameAsJSON['dauRoundDbkey'] != null) {
          dauRound = await _dauRoundsViewModel
              .findDAURound(gameAsJSON['dauRoundDbkey']);
        } else {
          dauRound = null;
        }

        if (homeTeam != null && awayTeam != null) {
          return Game.fromJson(Map<String, dynamic>.from(gameAsJSON), key,
              homeTeam, awayTeam, dauRound);
        } else {
          // Handle the case where homeTeam or awayTeam is null
          return null;
        }
      }).toList());

      _games = gamesList.where((game) => game != null).cast<Game>().toList();
      _games.sort();

      _groupedGames = groupBy(_games, (game) => game.gameState);
    } else {
      log('No games found for DAUComp $parentDAUCompDBkey');
    }
    _initialLoadComplete = true;

    notifyListeners();
  }

  // this function should only be triggered by fixture download service
  void editGame(Game game) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial Game load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }
      _savingGame = true;
      notifyListeners();

      //TODO test slow saves - in UI the back button should be disabled during the wait
      await Future.delayed(const Duration(seconds: 5), () {
        log('delayed save');
      });

      //TODO only saved changed attributes to the firebase database

      // Implement the logic to edit the game in Firebase here
      final Map<String, Map> updates = {};
      updates['$gamesPathRoot/$parentDAUCompDBkey/${game.dbkey}'] =
          game.toJson();
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingGame = false;
      notifyListeners();
    }
  }

  void addGame(Game gameData, DAUComp daucomp) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial Game load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }

      _savingGame = true;
      notifyListeners();

      _teamsViewModel.addTeam(gameData.awayTeam);
      _teamsViewModel.addTeam(gameData.homeTeam);

      // A post entry. //TODO
      final postData = gameData.toJson();

      // Write the new post's data simultaneously in the posts list and the
      // user's post list. //TODO
      final Map<String, Map> updates = {};
      updates['$gamesPathRoot/$parentDAUCompDBkey/${gameData.dbkey}'] =
          postData;
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingGame = false;
      notifyListeners();
    }
  }

  // this function finds the provided Game dbKey in the _Games list and returns it
  Future<Game> findGame(String gameDbKey) async {
    while (!_initialLoadComplete) {
      log('Waiting for initial Game load to complete in findGame');
      await Future.delayed(const Duration(seconds: 1));
    }
    return _games.firstWhere((game) => game.dbkey == gameDbKey);
  }

  @override
  void dispose() {
    _gamesStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
