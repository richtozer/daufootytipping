import 'dart:async';
import 'package:daufootytipping/models/tipper.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database locations
const tippersPath = '/Tippers';

class TippersViewModel extends ChangeNotifier {
  List<Tipper> _tippers = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _tippersStream;

  List<Tipper> get tippers => _tippers;

  bool _savingTipper = false;
  bool get savingTipper => _savingTipper;

  //List<Tipper> get admins =>
  //    _tippers.where((tipper) => tipper.name.contains('Phil'));
  //List<Team> get teams => _teams;

  //constructor
  TippersViewModel() {
    _listenToTippers();
  }

  // monitor changes to tippers records in DB and notify listeners of any changes
  void _listenToTippers() {
    _tippersStream = _db.child(tippersPath).onValue.listen((event) {
      if (event.snapshot.exists) {
        final allTippers =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        _tippers = allTippers.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic tipperasJSON = entry.value;

          return Tipper.fromJson(Map<String, dynamic>.from(tipperasJSON), key);
        }).toList();

        _tippers.sort();

        notifyListeners();
      }
    });
  }

  Future<void> editTipper(Tipper tipper) async {
    try {
      _savingTipper = true;
      notifyListeners();

      // Implement the logic to edit the tipper in Firebase here
      final Map<String, Map> updates = {};
      updates['$tippersPath/${tipper.dbkey}'] = tipper.toJson();
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingTipper = false;
      notifyListeners();
    }
  }

  Future<void> addTipper(Tipper tipperData) async {
    try {
      _savingTipper = true;
      notifyListeners();

      // A post entry.
      final postData = tipperData.toJson();

      // Get a key for a new Post.
      final newTipperKey = _db.child(tippersPath).push().key;

      // Write the new post's data simultaneously in the posts list and the
      // user's post list.
      final Map<String, Map> updates = {};
      updates['$tippersPath/$newTipperKey'] = postData;
      //updates['/user-posts/$uid/$newPostKey'] = postData;
      _db.update(updates);
    } finally {
      _savingTipper = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
