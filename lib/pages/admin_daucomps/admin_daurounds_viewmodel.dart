/*
import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const dauRoundsPathRoot = '/DAUCompsRounds';

class DAURoundsViewModel extends ChangeNotifier {
  List<DAURound> _dauRounds = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _dauRoundsStream;
  bool _savingDAURound = false;
  bool _initialLoadComplete =
      true; //TODO if our concunrrency model is ok now, we can remove this check
  String parentDAUCompDBkey;

  List<DAURound> get dauRounds => _dauRounds;
  bool get savingDAURound => _savingDAURound;

  //constructor
  DAURoundsViewModel(this.parentDAUCompDBkey) {
    _listenToDAURounds();
  }

  void _listenToDAURounds() {
    _dauRoundsStream = _db
        .child('$dauRoundsPathRoot/$parentDAUCompDBkey')
        .onValue
        .listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    if (event.snapshot.exists) {
      final allDAURounds =
          Map<String, dynamic>.from(event.snapshot.value as dynamic);

      List<DAURound?> dauRoundsList =
          await Future.wait(allDAURounds.entries.map((entry) async {
        String key = entry.key; // Retrieve the Firebase key
        dynamic gameAsJSON = entry.value;

        return DAURound.fromJson(Map<String, dynamic>.from(gameAsJSON), key);
      }).toList());
      _dauRounds = dauRoundsList.cast<DAURound>().toList();

      _dauRounds.sort();
    } else {
      log('No dauRounds found for DAUComp $parentDAUCompDBkey');
    }
    _initialLoadComplete = true;

    notifyListeners();
  }

  // this function should only be triggered by fixture download service
  void editDAURound(DAURound game) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial DAURound load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }
      _savingDAURound = true;

      //TODO test slow saves - in UI the back button should be disabled during the wait
      await Future.delayed(const Duration(seconds: 5), () {
        log('delayed save');
      });

      //TODO only saved changed attributes to the firebase database

      // Implement the logic to edit the game in Firebase here
      final Map<String, Map> updates = {};
      updates['$dauRoundsPathRoot/$parentDAUCompDBkey/${game.dbkey}'] =
          game.toJson();
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingDAURound = false;
    }
  }

  void addDAURound(DAURound gameData, DAUComp daucomp) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial DAURound load to complete');
        await Future.delayed(const Duration(seconds: 1));
      }

      _savingDAURound = true;


      // A post entry. //TODO
      final postData = gameData.toJson();

      // Write the new post's data simultaneously in the posts list and the
      // user's post list. //TODO
      final Map<String, Map> updates = {};
      updates['$dauRoundsPathRoot/$parentDAUCompDBkey/${gameData.dbkey}'] =
          postData;
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingDAURound = false;
    }
  }

  // this function finds the provided DAURound dbKey in the _DAURounds list and returns it
  Future<DAURound?> findDAURound(String gameDbKey) async {
    while (!_initialLoadComplete) {
      log('Waiting for initial DAURound load to complete in findDAURound');
      await Future.delayed(const Duration(seconds: 1));
    }
    return _dauRounds.firstWhereOrNull((game) => game.dbkey == gameDbKey);
  }

  @override
  void dispose() {
    _dauRoundsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
*/