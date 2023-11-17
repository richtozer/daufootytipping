import 'dart:async';
import 'package:daufootytipping/classes/dau.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// this provider model is based on the examples in this good Youtube tutorial:
// https://youtu.be/sXBJZD0fBa4?si=o1z2fTJzgsRhw5jw

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

  void _listenToTippers() {
    _tippersStream = _db.child(tippersPath).onValue.listen((event) {
      final allTippers =
          Map<String, dynamic>.from(event.snapshot.value as dynamic);
      _tippers = allTippers.values
          .map((tipperasJSON) =>
              Tipper.fromJson(Map<String, dynamic>.from(tipperasJSON)))
          .toList();

      notifyListeners();
    });
  }

  @override
  void dispose() {
    _tippersStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
