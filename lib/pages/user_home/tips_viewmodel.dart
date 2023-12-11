import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const tipsPathRoot = '/Tips';

class TipsViewModel extends ChangeNotifier {
  List<Tip> _tips = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;
  bool _savingTip = false;
  bool _initialLoadComplete = true;

  final TippersViewModel _tippersViewModel;
  late GamesViewModel _gamesViewModel;
  final String parentDAUCompDBkey;

  List<Tip> get tips => _tips;
  List<Game> get games => _gamesViewModel.games;
  bool get savingTip => _savingTip;

  //constructor
  TipsViewModel(this.parentDAUCompDBkey, this._tippersViewModel) {
    _gamesViewModel = GamesViewModel(parentDAUCompDBkey);
    _gamesViewModel.addListener(
        update); //listen for changes to _gamesViewModel so that we can notify our consumers that the data may have changed
    _listenToTips();
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the gamesviewmodel.games data
  }

  void _listenToTips() {
    _tipsStream = _db
        .child(
            '$tipsPathRoot/$parentDAUCompDBkey/${_tippersViewModel.tippers[_tippersViewModel.currentTipperIndex].dbkey}')
        .onValue
        .listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    if (event.snapshot.exists) {
      final allTips =
          deepMapFromObject(event.snapshot.value as Map<Object?, Object?>);

      _tips = await deserializeTips(allTips,
          _tippersViewModel.tippers[_tippersViewModel.currentTipperIndex]);
      _tips.sort();
    } else {
      log('No tips found for Tipper ${_tippersViewModel.tippers[_tippersViewModel.currentTipperIndex].name}');
    }
    _initialLoadComplete = true;

    notifyListeners();
  }

  Map<String, dynamic> deepMapFromObject(Map<Object?, Object?> map) {
    return Map<String, dynamic>.from(map.map((key, value) {
      if (value is Map<Object?, Object?>) {
        return MapEntry(key.toString(), deepMapFromObject(value));
      } else {
        return MapEntry(key.toString(), value);
      }
    }));
  }

  Future<List<Tip>> deserializeTips(Map<String, dynamic> json, tipper) async {
    List<Future<Tip>> futureTips = [];

    for (var entry in json.entries) {
      String gameKey = entry.key;
      Map<String, dynamic> tipData = entry.value;

      futureTips.addAll(tipData.entries.map((entry) async {
        String key = entry.key;
        Map<String, dynamic> data = entry.value;

        Game game = await _gamesViewModel.findGame(gameKey);
        return Tip.fromJson(data, key, tipper, game);
      }));
    }

    return await Future.wait(futureTips);
  }

  void addTip(Tip tip) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial Tip load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }

      _savingTip = true;
      notifyListeners();

      // create a json representation of the tip
      final tipJson = tip.toJson();

      //get a unique db key for this tip
      final newTipKey = _db
          .child(
              '$tipsPathRoot/$parentDAUCompDBkey/${tip.tipper.dbkey}/${tip.game.dbkey}')
          .push()
          .key;

      // Write the new post's data simultaneously in the posts list and the
      // user's post list. //TODO
      final Map<String, Map> updates = {};
      updates['$tipsPathRoot/$parentDAUCompDBkey/${tip.tipper.dbkey}/${tip.game.dbkey}/$newTipKey'] =
          tipJson;
      _db.update(updates);
    } finally {
      _savingTip = false;
      notifyListeners();
    }
  }

  Tip? getLatestGameTip(String gameDbkey) {
    while (!_initialLoadComplete) {
      log('Waiting for initial tips load to complete, getLatestGameTip()');
      Future.delayed(const Duration(seconds: 1));
    }
    log('tips load complete, getLatestGameTip()');
    return _tips.firstWhereOrNull((tip) => tip.game.dbkey == gameDbkey);
  }

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(update);
    super.dispose();
  }
}
