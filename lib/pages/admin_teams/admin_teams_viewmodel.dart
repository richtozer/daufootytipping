import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const teamsPath = '/Teams';

class TeamsViewModel extends ChangeNotifier {
  List<Team> _teams = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _teamsStream;
  bool _savingTeam = false;

  //property
  bool get savingTeam => _savingTeam;

  //property
  List<Team> get teams => _teams;

  //constructor
  TeamsViewModel() {
    _listenToTeams();
  }

  // monitor changes to teams records in DB and notify listeners of any changes
  void _listenToTeams() async {
    _teamsStream = _db.child(teamsPath).onValue.listen((event) {
      if (event.snapshot.exists) {
        final allTeams =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        _teams = allTeams.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic teamAsJSON = entry.value;

          return Team.fromJson(Map<String, dynamic>.from(teamAsJSON), key);
        }).toList();

        _teams.sort(); //TODO - consider replacing with Firebase orderby method

        notifyListeners();
      }
    });
  }

  Future<void> editTeam(Team team) async {
    try {
      _savingTeam = true;
      notifyListeners();

      //let check if the team record already exists
      Team? foundTeam = teams
          .firstWhereOrNull((existingTeam) => existingTeam.dbkey == team.dbkey);

      //only edit the team if it already exists, otherwise ignore
      if (foundTeam != null) {
        // Implement the logic to edit the team in Firebase here

        final Map<String, Map> updates = {};
        updates['$teamsPath/${team.dbkey}'] = team.toJson();
        //updates['/user-posts/$uid/$newPostKey'] = postData;
        _db.update(updates);
      } else {
        log('Team: ${team.dbkey} does not exist in the database, ignoring edit request');
      }
    } finally {
      _savingTeam = false;
      notifyListeners();
    }
  }

  Future<void> addTeam(Team team) async {
    try {
      _savingTeam = true;
      notifyListeners();

      //let check if the team record already exists
      Team? foundTeam = teams
          .firstWhereOrNull((existingTeam) => existingTeam.dbkey == team.dbkey);

      //only add the team if this is the first run, otherwise ignore
      if (foundTeam == null) {
        // create a new team database entry
        final postData = team.toJson();

        final Map<String, Map> updates = {};
        updates['$teamsPath/${team.dbkey}'] = postData;
        //updates['/user-posts/$uid/$newPostKey'] = postData;
        _db.update(updates);
      } else {
        log('Team: ${foundTeam.dbkey} already exists in the database, ignoring add request');
      }
    } finally {
      _savingTeam = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _teamsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
