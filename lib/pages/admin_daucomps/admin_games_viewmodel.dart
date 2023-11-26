import 'dart:async';

import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const gamesPath = '/Games';

class GamesViewModel extends ChangeNotifier {
  List<Game> _games = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _gamesStream;
  List<Game> get games => _games;
  bool _savingGame = false;
  bool get savingGame => _savingGame;

  //constructor
  GamesViewModel() {
    //_listenToGames();  //TODO - enable this method
  }

  // monitor changes to games records in DB and notify listeners of any changes
  void _listenToGames() {
    _gamesStream = _db.child(gamesPath).onValue.listen((event) {
      if (event.snapshot.exists) {
        final allGames =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        _games = allGames.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic gameAsJSON = entry.value;

          return Game.fromJson(Map<String, dynamic>.from(gameAsJSON), key);
        }).toList();

        _games.sort(); //TODO - consider replacing with Firebase orderby method

        notifyListeners();
      }
    });
  }

  Future<void> editGame(Game game) async {
    try {
      _savingGame = true;
      notifyListeners();

      // Implement the logic to edit the game in Firebase here
      final Map<String, Map> updates = {};
      updates['$gamesPath/${game.dbkey}'] = game.toJson();
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingGame = false;
      notifyListeners();
    }
  }

  Future<void> addGame(Game gameData, TeamsViewModel teamsViewModel) async {
    try {
      _savingGame = true;
      notifyListeners();

      //before we add a game entry, lets make sure the teams are represented in the DB
      //TeamsViewModel teamsViewModel = TeamsViewModel();

      teamsViewModel.addTeam(gameData.awayTeam);
      teamsViewModel.addTeam(gameData.homeTeam);

      // A post entry.
      final postData = gameData.toJson();

      // Write the new post's data simultaneously in the posts list and the
      // user's post list.
      final Map<String, Map> updates = {};
      updates['$gamesPath/${gameData.dbkey}'] = postData;
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingGame = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _gamesStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
