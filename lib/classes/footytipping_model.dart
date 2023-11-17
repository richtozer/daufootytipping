import 'dart:async';
import 'package:daufootytipping/classes/dau.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define some constants for firestore database locations
const tippersPath = '/Tippers';
const teamsPath = '/Teams';
const dauCompsPath = '/DAUComps';

class FootyTippingModel extends ChangeNotifier {
  static const tippersPath = 'Tippers';
  static const teamsPath = 'Teams';
  static const dauCompsPath = 'DAUComps';

  List<Tipper> _tippers = [];
  //List<Team> _teams = [];

  final _db = FirebaseDatabase.instance.ref();

  late StreamSubscription<DatabaseEvent> _tippersStream;

  List<Tipper> get tippers => _tippers;
  //List<Team> get teams => _teams;

  //constructor
  FootyTippingModel() {
    _listenToTippers();
  }

  // monitor changes to tippers records in DB and notify listeners of any changes
  void _listenToTippers() {
    _tippersStream = _db.child(tippersPath).onValue.listen((event) {
      final allTippers =
          Map<String, dynamic>.from(event.snapshot.value as dynamic);

      _tippers = allTippers.entries.map((entry) {
        String key = entry.key; // Retrieve the Firebase key
        dynamic tipperasJSON = entry.value;

        return Tipper.fromJson(Map<String, dynamic>.from(tipperasJSON), key);
      }).toList();

      notifyListeners();
    });
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
