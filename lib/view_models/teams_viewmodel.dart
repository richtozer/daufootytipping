import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/auth_aware_stream.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:json_diff/json_diff.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class TeamsViewModel extends ChangeNotifier {
  List<Team> _teams = [];
  DatabaseReference get _db => configuredDatabaseRef();
  late StreamSubscription<DatabaseEvent> _teamsStream;
  final Completer<void> _initialLoadCompleter = Completer<void>();
  Map _groupedTeams = {};

  List<Team> get teams => _teams;
  Map get groupedTeams => _groupedTeams;
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  TeamsViewModel() {
    _listenToTeams();
  }

  // Teams need a session under the R2 rules, so the listener opens once a user is
  // signed in (see authAwareStream), not when this view model is created.
  void _listenToTeams() {
    _teamsStream =
        authAwareStream<DatabaseEvent>(
          signedIn: firebaseSignedInStream,
          open: () => _db.child(p.teamsPathRoot).onValue,
        ).listen((event) {
          if (event.snapshot.exists) {
            _processTeams(event);
          } else {
            log('No teams found in database');
          }

          if (!_initialLoadCompleter.isCompleted) {
            _initialLoadCompleter.complete();
          }
          notifyListeners();
        });
  }

  void _processTeams(DatabaseEvent event) {
    final allTeams = Map<String, dynamic>.from(event.snapshot.value as dynamic);

    _teams = allTeams.entries.map((entry) {
      String key = entry.key;
      dynamic teamAsJSON = entry.value;

      return Team.fromJson(Map<String, dynamic>.from(teamAsJSON), key);
    }).toList();

    _teams.sort();
    _groupedTeams = groupBy(_teams, (team) => team.league.name);
  }

  Future<void> editTeam(Team updatedTeam) async {
    await _initialLoadCompleter.future;

    Team? originalTeam = _teams.firstWhereOrNull(
      (existingTeam) => existingTeam.dbkey == updatedTeam.dbkey,
    );

    if (originalTeam != null) {
      await _editExistingTeam(originalTeam, updatedTeam);
    } else {
      log(
        'Team: ${updatedTeam.dbkey} does not exist in the database, ignoring edit request',
      );
    }
    // The UI updates when the database listener in _listenToTeams() receives
    // the change.
  }

  Future<void> _editExistingTeam(Team originalTeam, Team updatedTeam) async {
    Map<String, dynamic> originalJson = originalTeam.toJson();
    Map<String, dynamic> updatedJson = updatedTeam.toJson();

    JsonDiffer differ = JsonDiffer.fromJson(originalJson, updatedJson);
    DiffNode diff = differ.diff();

    Map<String, dynamic> updates = {};

    Map changed = diff.changed;
    changed.keys.toList().forEach((key) {
      if (changed[key] is List && (changed[key] as List).isNotEmpty) {
        updates['${p.teamsPathRoot}/${updatedTeam.dbkey}/$key'] =
            changed[key][1];
      }
    });

    await _db.update(updates);
  }

  Future<void> addTeam(Team team) async {
    await _initialLoadCompleter.future;

    Team? foundTeam = teams.firstWhereOrNull(
      (existingTeam) =>
          existingTeam.dbkey.toLowerCase() == team.dbkey.toLowerCase(),
    );

    if (foundTeam == null) {
      _addNewTeam(team);
      log('Team: ${team.dbkey.toLowerCase()} added to the database');
    }
  }

  Future<void> _addNewTeam(Team team) async {
    final postData = team.toJson();

    final Map<String, Map> updates = {};
    updates['${p.teamsPathRoot}/${team.dbkey.toLowerCase()}'] = postData;

    await _db.update(updates);
  }

  Team? findTeam(String teamDbKey) {
    // if the initial load is not complete, throw an exception
    if (!_initialLoadCompleter.isCompleted) {
      throw Exception(
        'TeamsViewModel.findTeam() Initial Teams load not complete',
      );
    }
    return _teams.firstWhereOrNull(
      (team) => team.dbkey.toLowerCase() == teamDbKey.toLowerCase(),
    );
  }

  @override
  void dispose() {
    _teamsStream.cancel();
    super.dispose();
  }
}
