import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_tips_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

// define constant for firestore database locations - TODO move to env file
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

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  bool _isLegacySyncing = false;
  bool get isLegacySyncing => _isLegacySyncing;

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
    } finally {
      _savingDAUComp = false;
      notifyListeners();
    }
  }

  Future<String> getNetworkFixtureData(DAUComp newdaucomp) async {
    try {
      _isDownloading = true;
      notifyListeners();

      while (!_initialLoadComplete) {
        log('Waiting for initial DAUComps load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }

      FixtureDownloadService fds = FixtureDownloadService();

      List<dynamic> nrlGames = [];
      try {
        nrlGames = await fds.getLeagueFixtureRaw(
            newdaucomp.nrlFixtureJsonURL, League.nrl);
      } catch (e) {
        throw 'Error loading NRL fixture data. Exception was: $e';
        //return 'Error loading NRL fixture data. Exception was: $e'; // TODO - exceptions is not being passed to caller
      }

      List<dynamic> aflGames = [];
      try {
        aflGames = await fds.getLeagueFixtureRaw(
            newdaucomp.aflFixtureJsonURL, League.afl);
      } catch (e) {
        throw 'Error loading AFL fixture data. Exception was: $e';

        //return 'Error loading AFL fixture data. Exception was: $e';  // TODO - exceptions is not being passed to caller
      }

      GamesViewModel gamesViewModel = GamesViewModel(newdaucomp.dbkey!);

      List<Future> gamesFuture = [];

      for (var gamejson in nrlGames) {
        String dbkey =
            '${League.nrl.name}-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        for (var attribute in gamejson.keys) {
          gamesFuture.add(gamesViewModel.updateGameAttribute(
              dbkey, attribute, gamejson[attribute], League.nrl.name));
        }
      }

      for (var gamejson in aflGames) {
        String dbkey =
            '${League.afl.name}-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        for (var attribute in gamejson.keys) {
          gamesFuture.add(gamesViewModel.updateGameAttribute(
              dbkey, attribute, gamejson[attribute], League.afl.name));
        }
      }

      await Future.wait(gamesFuture);

      //save all updates
      await gamesViewModel.saveBatchOfGameAttributes();

      //once all the data is loaded, update the combinedRound field
      gamesViewModel.updateCombinedRoundNumber();

      return 'Fixture data loaded. Found ${nrlGames.length} NRL games and ${aflGames.length} AFL games';
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> syncTipsWithLegacy(DAUComp newdaucomp) async {
    try {
      _isLegacySyncing = true;
      notifyListeners();

      while (!_initialLoadComplete) {
        log('Waiting for initial DAUComps load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }

      //get reference to legacy tipping service so that we can sync tips
      LegacyTippingService tippingService =
          GetIt.instance<LegacyTippingService>();

      TippersViewModel tippersViewModel = TippersViewModel();

      AllTipsViewModel allTipsViewModel =
          AllTipsViewModel(tippersViewModel, newdaucomp.dbkey!);

      GamesViewModel gamesViewModel = GamesViewModel(newdaucomp.dbkey!);

      //sync tips to legacy
      await tippingService.initialized();
      tippingService.syncTipsToLegacyDiffOnly(allTipsViewModel, gamesViewModel);
    } finally {
      _isLegacySyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _daucompsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
