import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:json_diff/json_diff.dart';

// define  constant for firestore database location
const teamsPathRoot = '/Teams';

class TeamsViewModel extends ChangeNotifier {
  List<Team> _teams = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _teamsStream;
  bool _savingTeam = false;
  bool _initialLoadComplete = false;
  Map _groupedTeams = {};

  //property
  bool get savingTeam => _savingTeam;

  //property
  List<Team> get teams => _teams;
  //property
  Map get groupedTeams => _groupedTeams;

  //constructor
  TeamsViewModel() {
    _listenToTeams();
  }

  // monitor changes to teams records in DB and notify listeners of any changes
  void _listenToTeams() {
    _teamsStream = _db.child(teamsPathRoot).onValue.listen((event) {
      if (event.snapshot.exists) {
        final allTeams =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        _teams = allTeams.entries.map((entry) {
          String key = entry.key; // Retrieve the Firebase key
          dynamic teamAsJSON = entry.value;

          return Team.fromJson(Map<String, dynamic>.from(teamAsJSON), key);
        }).toList();

        _teams.sort(); //TODO - consider replacing with Firebase orderby method
        _groupedTeams = groupBy(_teams, (team) => team.league.name);

        _initialLoadComplete = true;

        notifyListeners();
      }
    });
  }

  // this function should only be called by the fixture download service
  void editTeam(Team updatedTeam) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial Team load to complete in editTeam');
        await Future.delayed(const Duration(seconds: 1));
      }

      _savingTeam = true;
      notifyListeners();

      //the original Team record should be in our list of teams
      Team? originalTeam = _teams.firstWhereOrNull(
          (existingTeam) => existingTeam.dbkey == updatedTeam.dbkey);

      //only edit the Team record if it already exists, otherwise ignore
      if (originalTeam != null) {
        // Convert the original and updated tippers to JSON
        Map<String, dynamic> originalJson = originalTeam.toJson();
        Map<String, dynamic> updatedJson = updatedTeam.toJson();

        // Use JsonDiffer to get the differences
        JsonDiffer differ = JsonDiffer.fromJson(originalJson, updatedJson);
        DiffNode diff = differ.diff();

        // Initialize an empty map to hold all updates
        Map<String, dynamic> updates = {};

        // transform the changes from JsonDiffer format to Firebase format
        Map changed = diff.changed;
        changed.keys.toList().forEach((key) {
          if (changed[key] is List && (changed[key] as List).isNotEmpty) {
            // Add the update to the updates map
            updates['$teamsPathRoot/${updatedTeam.dbkey}/$key'] =
                changed[key][1];
          }
        });

        // Apply any updates to Firebase
        _db.update(updates);
      } else {
        log('Team: ${updatedTeam.dbkey} does not exist in the database, ignoring edit request');
      }
    } finally {
      _savingTeam = false;
      notifyListeners();
    }
  }

// this function should only be called by the fixture download service
  void addTeam(Team team) async {
    try {
      while (!_initialLoadComplete) {
        log('Waiting for initial Team load to complete in addTeam');
        await Future.delayed(const Duration(seconds: 1));
      }
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
        updates['$teamsPathRoot/${team.dbkey}'] = postData;
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

  // this function finds the provided Team dbKey in the _Teams list and returns it
  Future<Team?> findTeam(String teamDbKey) async {
    while (!_initialLoadComplete) {
      log('Waiting for initial team load to complete in findTeam');
      await Future.delayed(const Duration(seconds: 1));
    }
    return _teams.firstWhereOrNull((team) => team.dbkey == teamDbKey);
  }

  @override
  void dispose() {
    _teamsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
