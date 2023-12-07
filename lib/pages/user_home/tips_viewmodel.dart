import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const tipsPathRoot = '/Tips';

class TipsViewModel extends ChangeNotifier {
  List<Tip> _tips = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;
  bool _savingTip = false;
  bool _initialLoadComplete = false;
  Tipper tipper;

  List<Tip> get tips => _tips;
  bool get savingTip => _savingTip;

  //constructor
  TipsViewModel(this.tipper) {
    _listenToTips();
  }

  void _listenToTips() {
    _tipsStream =
        _db.child('$tipsPathRoot/${tipper.dbkey}').onValue.listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    if (event.snapshot.exists) {
      final allTips =
          Map<String, dynamic>.from(event.snapshot.value as dynamic);

      List<Tip?> tipsList =
          await Future.wait(allTips.entries.map((entry) async {
        String key = entry.key; // Retrieve the Firebase key
        dynamic tipAsJSON = entry.value;

        //we need to find and deserialize the home and away teams first before we can deserialize the game
        //Team? homeTeam = _teamsViewModel.findTeam(gameAsJSON['homeTeamDbKey']);
        //Team? awayTeam = _teamsViewModel.findTeam(gameAsJSON['awayTeamDbKey']);

        //if (homeTeam != null && awayTeam != null) {
        return Tip.fromJson(Map<String, dynamic>.from(tipAsJSON), key);
        //} else {
        // Handle the case where homeTeam or awayTeam is null
        // return null;
        //}
      }).toList());

      _tips = tipsList.where((game) => game != null).cast<Tip>().toList();
      _tips.sort();
    } else {
      log('No tips found for Tipper ${tipper.name}');
    }
    _initialLoadComplete = true;

    notifyListeners();
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

      // Write the new post's data simultaneously in the posts list and the
      // user's post list. //TODO
      final Map<String, Map> updates = {};
      updates['$tipsPathRoot/${tip.tipper.dbkey}/${tip.game.dbkey}'] = tipJson;
      updates['$tipsPathRoot/${tip.game.dbkey}/${tip.tipper.dbkey}'] = tipJson;
      _db.update(updates);
    } finally {
      _savingTip = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
