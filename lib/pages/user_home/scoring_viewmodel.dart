import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/location_latlong.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

const scoringPathRoot = '/DAUCompsScoring';

class ScoringViewModel extends ChangeNotifier {
  // Properties
  List<Game> _scoring = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _scoringStream;

  String currentDAUComp;

  Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  // Constructor
  ScoringViewModel(this.currentDAUComp) {
    _listenToScoring();
  }

  // Database listeners
  void _listenToScoring() {
    _scoringStream =
        _db.child('$scoringPathRoot/$currentDAUComp').onValue.listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('***ScoringViewModel_handleEvent()***');
      if (event.snapshot.exists) {
        final allScoring =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        // Deserialize the scoring
        List<Game> scoringList =
            await Future.wait(allScoring.entries.map((entry) async {
          String key = entry.key; // Retrieve the Firebase key
          String league = key.split('-').first;
          dynamic scoringAsJSON = entry.value;

          //we need to deserialize the locationlatlng before we can deserialize the scoring
          LatLng? locationLatLng;
          if (scoringAsJSON['locationLatLng'] != null) {
            locationLatLng = LatLng.fromJson(
                Map<String, dynamic>.from(scoringAsJSON['locationLatLng']));
          }
          //we need to find and deserialize the home and away teams first before we can deserialize the scoring
          Team? homeTeam = await _teamsViewModel
              .findTeam('$league-${scoringAsJSON['HomeTeam']}');
          Team? awayTeam = await _teamsViewModel
              .findTeam('$league-${scoringAsJSON['AwayTeam']}');

          Scoring? scoring = Scoring(
              homeTeamScore: scoringAsJSON['HomeTeamScore'],
              awayTeamScore: scoringAsJSON['AwayTeamScore']);

          if (homeTeam != null && awayTeam != null) {
            log('Game: $key about to be deserialized');
            Game scoring = Game.fromFixtureJson(key,
                Map<String, dynamic>.from(scoringAsJSON), homeTeam, awayTeam);
            scoring.locationLatLong = locationLatLng;
            scoring.scoring = scoring;
            return scoring;
          } else {
            // homeTeam or awayTeam should not be null
            throw Exception(
                'Error in ScoringViewModel_handleEvent: homeTeam or awayTeam is null');
          }
        }).toList());

        //_scoring = scoringList.where((scoring) => scoring != null).cast<Game>().toList();
        _scoring = scoringList;
        _scoring.sort();
      } else {
        log('No scoring found for DAUComp $currentDAUComp');
      }
    } catch (e) {
      log('Error in ScoringViewModel_handleEvent: $e');
      rethrow;
    } finally {
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
    }
  }

  final Map<String, dynamic> updates = {};

  Future<void> updateGameAttribute(String scoringDbKey, String attributeName,
      dynamic attributeValue, String league) async {
    await _initialLoadCompleter.future;

    //make sure the related team records exist
    if (attributeName == 'HomeTeam' || attributeName == 'AwayTeam') {
      Team team = Team(
          dbkey: '$league-$attributeValue',
          name: attributeValue,
          league: League.values.firstWhere((e) => e.name == league));
      //make sure the related team records exist
      _teamsViewModel.addTeam(team);
    }

    //find the scoring in the local list. it it's there, compare the attribute value and update if different
    Game? scoringToUpdate = await findGame(scoringDbKey);
    if (scoringToUpdate != null) {
      dynamic oldValue = scoringToUpdate.toFixtureJson()[attributeName];
      if (attributeValue != oldValue) {
        log('Game: $scoringDbKey needs update for attribute $attributeName: $attributeValue');
        updates['$scoringPathRoot/$currentDAUComp/$scoringDbKey/$attributeName'] =
            attributeValue;
      } else {
        log('Game: $scoringDbKey already has $attributeName: $attributeValue');
      }
    } else {
      log('Game: $scoringDbKey not found in local list. adding full scoring record');
      // add new record to updates Map
      updates['$scoringPathRoot/$currentDAUComp/$scoringDbKey/$attributeName'] =
          attributeValue;
    }
  }

  Future<void> saveBatchOfGameAttributes() async {
    try {
      await initialLoadComplete;
      await _db.update(updates);
    } finally {
      _savingGame = false;
      notifyListeners();
    }
  }

  Future<Game?> findGame(String scoringDbKey) async {
    if (!_initialLoadCompleter.isCompleted) {
      log('Waiting for Game load to complete findGame()');
    }
    await _initialLoadCompleter.future;
    return _scoring
        .firstWhereOrNull((scoring) => scoring.dbkey == scoringDbKey);
  }

  @override
  void dispose() {
    _scoringStream.cancel(); // stop listening to stream

    // create a new Completer if the old one was completed:
    if (_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter = Completer<void>();
    }

    super.dispose();
  }
}
