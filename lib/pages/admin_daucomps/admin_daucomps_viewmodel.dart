import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

// define  constant for firestore database locations
const daucompsPath = '/DAUComps';

class DAUCompsViewModel extends ChangeNotifier {
  List<DAUComp> _daucomps = [];

  String selectedDAUCompDBKey = '';

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _daucompsStream;

  List<DAUComp> get daucomps => _daucomps;

  bool _savingDAUComp = false;
  bool get savingDAUComp => _savingDAUComp;
  bool _initialLoadComplete = false;

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
        _initialLoadComplete = true;

        notifyListeners();
      }
    });
  }

  void editDAUComp(DAUComp daucomp) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial DAUComps load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }
      _savingDAUComp = true;
      notifyListeners();

      //TODO only saved changed attributes to the firebase database

      // update the record in firebase
      final Map<String, Map> updates = {};
      updates['$daucompsPath/${daucomp.dbkey}'] = daucomp.toJson();
      await _db.update(updates);

      //TODO this is a test - remove this next line of code
      getNetworkFixtureData(daucomp);
    } finally {
      _savingDAUComp = false;
      notifyListeners();
    }
  }

  void addDAUComp(DAUComp newdaucomp) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial DAUComps load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }
      _savingDAUComp = true;
      notifyListeners();

      // add a new record to the firebase
      final postData = newdaucomp.toJson();
      final newdaucompKey = _db.child(daucompsPath).push().key;

      final Map<String, Map> updates = {};
      updates['$daucompsPath/$newdaucompKey'] = postData;

      await _db.update(updates);

      //update the dbkey in the local object
      newdaucomp.dbkey = newdaucompKey;

      // as this is a new comp, lets do the first time population of game and dauround data from the fixture json service
      getNetworkFixtureData(newdaucomp);
    } finally {
      _savingDAUComp = false;
      notifyListeners();
    }
  }

  void getNetworkFixtureData(DAUComp newdaucomp) async {
    while (!_initialLoadComplete) {
      log('Waiting for initial DAUComps load to complete');
      await Future.delayed(const Duration(seconds: 1));
    }

    FixtureDownloadService fds = FixtureDownloadService();

    List<Game> nrlGames =
        await fds.getLeagueFixture(newdaucomp.nrlFixtureJsonURL, League.nrl);

    List<Game> aflGames =
        await fds.getLeagueFixture(newdaucomp.aflFixtureJsonURL, League.afl);

    GamesViewModel gamesViewModel =
        GamesViewModel(newdaucomp.dbkey!); //get the provider instance

    List<Future> gamesFuture = []; //TODO use this wait pattern elsewhere

    for (Game game in nrlGames) {
      gamesFuture.add(gamesViewModel.updateGame(game));
    }

    for (Game game in aflGames) {
      gamesFuture.add(gamesViewModel.updateGame(game));
    }

    await Future.wait(gamesFuture);

    //once all the data is loaded, update the combinedRound field
    gamesViewModel.updateCombinedRoundNumber();

    //update the legacy tipping sheet with the default tips
    LegacyTippingService tippingService =
        GetIt.instance<LegacyTippingService>();

    //loop through all the tippers, and assign them default tips
    TippersViewModel tippersViewModel = TippersViewModel();
    List<Tipper> tippers = await tippersViewModel.getTippers();
    for (Tipper tipper in tippers) {
      tippingService.submitDefaultTips(tipper.name, gamesViewModel);
    }
  }

  @override
  void dispose() {
    _daucompsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
