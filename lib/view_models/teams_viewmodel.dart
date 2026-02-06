import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:json_diff/json_diff.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class TeamsViewModel extends ChangeNotifier {
  List<Team> _teams = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _teamsStream;
  bool _savingTeam = false;
  final Completer<void> _initialLoadCompleter = Completer<void>();
  Map _groupedTeams = {};

  bool get savingTeam => _savingTeam;
  List<Team> get teams => _teams;
  Map get groupedTeams => _groupedTeams;
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  TeamsViewModel() {
    _listenToTeams();
  }

  void _listenToTeams() {
    _teamsStream = _db.child(p.teamsPathRoot).onValue.listen((event) {
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
    _savingTeam = true;
    notifyListeners();

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

    _savingTeam = false;
    notifyListeners(); // Notify about _savingTeam state change
    // Note: Team data UI update will be triggered by database listener in _listenToTeams()
    // when the database change event is received
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
        updates['${p.teamsPathRoot}/${updatedTeam.dbkey}/$key'] = changed[key][1];
      }
    });

    await _db.update(updates);
  }

  Future<void> addTeam(Team team) async {
    await _initialLoadCompleter.future;
    _savingTeam = true;
    notifyListeners();

    Team? foundTeam = teams.firstWhereOrNull(
      (existingTeam) =>
          existingTeam.dbkey.toLowerCase() == team.dbkey.toLowerCase(),
    );

    if (foundTeam == null) {
      _addNewTeam(team);
      log('Team: ${team.dbkey.toLowerCase()} added to the database');
    }

    _savingTeam = false;
    notifyListeners();
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
