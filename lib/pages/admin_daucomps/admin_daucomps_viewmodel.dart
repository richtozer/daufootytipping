import 'dart:async';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database locations
const daucompsPath = '/DAUComps';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _daucompsStream;

  List<DAUComp> get daucomps => _daucomps;

  bool _savingDAUComp = false;
  bool get savingDAUComp => _savingDAUComp;

  //constructor
  DAUCompsViewModel() {
    _listenToDAUComps();
  }

  // monitor changes to DAUComp records in DB and notify listeners of any changes
  void _listenToDAUComps() {
    _daucompsStream = _db.child(daucompsPath).onValue.listen((event) {
      if (event.snapshot.exists) {
        final allDAUComps =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        _daucomps = allDAUComps.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic daucompasJSON = entry.value;

          return DAUComp.fromJson(
              Map<String, dynamic>.from(daucompasJSON), key);
        }).toList();

        _daucomps.sort();

        notifyListeners();
      }
    });
  }

  Future<void> editDAUComp(
      DAUComp daucomp, TeamsViewModel teamsViewModel) async {
    try {
      _savingDAUComp = true;
      notifyListeners();

      // update the record in firebase
      final Map<String, Map> updates = {};
      updates['$daucompsPath/${daucomp.dbkey}'] = daucomp.toJson();
      _db.update(updates);

      //TODO this is a test - remove this next line of code
      getNetworkFixtureData(daucomp, teamsViewModel);
    } finally {
      _savingDAUComp = false;
      notifyListeners();
    }
  }

  Future<void> addDAUComp(
      DAUComp newdaucomp, TeamsViewModel teamsViewModel) async {
    try {
      _savingDAUComp = true;
      notifyListeners();

      // add a new record to the firebase
      final postData = newdaucomp.toJson();
      final newdaucompKey = _db.child(daucompsPath).push().key;

      final Map<String, Map> updates = {};
      updates['$daucompsPath/$newdaucompKey'] = postData;
      //updates['blah'] = postData;
      _db.update(updates);

      // as this is a new comp, lets do the first time population of game and dauround data from the fixture json service
      getNetworkFixtureData(newdaucomp, teamsViewModel);
    } finally {
      _savingDAUComp = false;
      notifyListeners();
    }
  }

  Future<void> getNetworkFixtureData(
      DAUComp newdaucomp, TeamsViewModel teamsViewModel) async {
    FixtureDownloadService fds = FixtureDownloadService();

    List<Game> nrlGames =
        await fds.getLeagueFixture(newdaucomp.nrlFixtureJsonURL, League.nrl);

    List<Game> aflGames =
        await fds.getLeagueFixture(newdaucomp.aflFixtureJsonURL, League.afl);

    for (Game game in nrlGames) {
      GamesViewModel gamesViewModel = GamesViewModel();
      gamesViewModel.addGame(game, teamsViewModel);
    }

    for (Game game in aflGames) {
      GamesViewModel gamesViewModel = GamesViewModel();
      gamesViewModel.addGame(game, teamsViewModel);
    }
  }

  @override
  void dispose() {
    _daucompsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
