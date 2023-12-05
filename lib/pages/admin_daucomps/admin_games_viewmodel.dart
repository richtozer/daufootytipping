import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/team.dart';
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
  String parentDAUCompDBkey;
  TeamsViewModel teamsViewModel;

  List<Game> get games => _games;
  bool get savingGame => _savingGame;

  //constructor
  GamesViewModel(this.parentDAUCompDBkey, this.teamsViewModel) {
    _listenToGames();
  }

  // monitor changes to games records in DB and notify listeners of any changes
  void _listenToGames() {
    _gamesStream =
        _db.child('$gamesPathRoot/$parentDAUCompDBkey').onValue.listen((event) {
      if (event.snapshot.exists) {
        final allGames =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        _games = allGames.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic gameAsJSON = entry.value;

          //we need to find and deserialize the home and away teams first before we can deserialize the game
          Team? homeTeam = teamsViewModel.findTeam(gameAsJSON['homeTeamDbKey']);
          Team? awayTeam = teamsViewModel.findTeam(gameAsJSON['homeTeamDbKey']);

          return Game.fromJson(
              Map<String, dynamic>.from(gameAsJSON), key, homeTeam!, awayTeam!);
        }).toList();

        _games.sort(); //TODO - consider replacing with Firebase orderby method

        notifyListeners();
      }
    });
  }

  // this function should only be triggered by fixture download service
  Future<void> editGame(Game game) async {
    try {
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

  Future<void> addGame(Game gameData, DAUComp daucomp) async {
    try {
      _savingGame = true;
      notifyListeners();

      teamsViewModel.addTeam(gameData.awayTeam);
      teamsViewModel.addTeam(gameData.homeTeam);

      // A post entry.
      final postData = gameData.toJson();

      // Write the new post's data simultaneously in the posts list and the
      // user's post list.
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

  @override
  void dispose() {
    _gamesStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
