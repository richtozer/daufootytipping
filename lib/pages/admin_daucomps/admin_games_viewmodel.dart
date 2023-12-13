import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/locator.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
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

  late Map<int, List<Game>> _nestedGroups;

  bool _savingGame = false;
  bool _initialLoadComplete =
      false; //TODO if our concunrrency model is ok now, we can remove this check
  String parentDAUCompDBkey;

  Future<Map<int, List<Game>>> get nestedGames async {
    while (!_initialLoadComplete) {
      log('Waiting for initial Game load to complete');
      await Future.delayed(const Duration(seconds: 1));
    }
    return _nestedGroups;
  }

  List<Game> get games => _games;
  bool get savingGame => _savingGame;

  late TeamsViewModel _teamsViewModel;

  //constructor
  GamesViewModel(this.parentDAUCompDBkey) {
    _teamsViewModel = locator<TeamsViewModel>();
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

        if (homeTeam != null && awayTeam != null) {
          return Game.fromJson(
              Map<String, dynamic>.from(gameAsJSON), key, homeTeam, awayTeam);
        } else {
          // Handle the case where homeTeam or awayTeam is null
          return null;
        }
      }).toList());

      _games = gamesList.where((game) => game != null).cast<Game>().toList();
      _games.sort();

      _nestedGroups = groupBy(_games, (game) => game.combinedRoundNumber);

      updateCombinedRoundNumber();
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

  void updateCombinedRoundNumber() {
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
        game.setCombinedRoundNumber = i + 1;
        editGame(game); //write changes to firebase
      }
    }
  }

  @override
  void dispose() {
    _gamesStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
