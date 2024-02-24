import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/round_comp_scoring.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/leaderboard.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const scoresPathRoot = '/Scores';
const roundScoresRoot = 'round_scores';
const compScoresRoot = 'comp_scores';

class ScoresViewModel extends ChangeNotifier {
  List<RoundScores> _tipperRoundScores = [];
  late CompScore _tipperCompScores;

  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipperRoundScoresStream;
  late StreamSubscription<DatabaseEvent> _tipperCompScoresStream;

  final String currentDAUComp;
  Tipper? tipper;
  final Completer<void> _initialRoundLoadCompleter = Completer();
  Future<void> get initialRoundComplete => _initialRoundLoadCompleter.future;
  final Completer<void> _initialCompLoadCompleter = Completer();
  Future<void> get initialCompComplete => _initialCompLoadCompleter.future;

  //constructor
  ScoresViewModel(this.currentDAUComp) {
    log('***ScoresViewModel_constructor(ALL TIPPERS)***');
    _listenToScores();
  }

  // Second constructor
  ScoresViewModel.forTipper(this.currentDAUComp, this.tipper) {
    log('***ScoresViewModel_constructor(${tipper!.name})***');
    _listenToScores();
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToScores() async {
    if (tipper != null) {
      _tipperRoundScoresStream = _db
          .child(
              '$scoresPathRoot/$currentDAUComp/$roundScoresRoot/${tipper!.dbkey}')
          .onValue
          .listen(_handleEvent, onError: (error) {
        log('Error listening to round scores: $error');
      });

      _tipperCompScoresStream = _db
          .child(
              '$scoresPathRoot/$currentDAUComp/$compScoresRoot/${tipper!.dbkey}')
          .onValue
          .listen(_handleEvent, onError: (error) {
        log('Error listening to comp scores: $error');
      });
    } else {
      //TODO
/*       _scoresStream = _db
          .child('$scoresPathRoot/$currentDAUComp')
          .onValue
          .listen(_handleEvent, onError: (error) {
        log('Error listening to scores: $error');
      }); */
    }
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('***ScoresViewModel_handleEvent()***');
      if (event.snapshot.exists) {
        // deserialize the scores, they will be in one of 2 formats depending on the contructor used:
        // 1. Map<String, int> if no tipperID is provided
        // 2. List<Map<String, int>> if a tipperID is provided
        if (tipper != null) {
          //deserialize the scores - they are in this fomat: List<Map<String, int>>
          //and need to be converted to List<RoundScores>

          var dbData = event.snapshot.value;

          // check which stream has fired this event based on dbData datatype

          if (dbData is Map) {
            //deserialize the comp total scores - they are in this fomat: Map<String, int>
            //and need to be converted to CompScore
            _tipperCompScores = CompScore.fromJson(Map<String, dynamic>.from(
                event.snapshot.value as Map<dynamic, dynamic>));

            if (!_initialCompLoadCompleter.isCompleted) {
              _initialCompLoadCompleter.complete();
            }
          } else {
            if (dbData is! List) {
              throw Exception('Invalid data type for round scores');
            }
            //deserialize the scores - they are in this fomat: List<Map<String, int>>
            //and need to be converted to List<RoundScores>
            _tipperRoundScores = dbData
                .map((e) => RoundScores.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            if (!_initialRoundLoadCompleter.isCompleted) {
              _initialRoundLoadCompleter.complete();
            }
          }
        } else {
          //deserialize the all tipper scores they are in Map<List[Map<String, int]>> format
          //and need to be converted to Map<List<RoundScores>>
          _tipperCompScores = CompScore.fromJson(Map<String, dynamic>.from(
              event.snapshot.value as Map<dynamic, dynamic>));

          if (!_initialCompLoadCompleter.isCompleted) {
            _initialCompLoadCompleter.complete();
          }
        }
      }
    } catch (e) {
      log('Error listening to /Scores: $e');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  writeScoresToDb(Map<String, Map<int, Map<String, int>>> roundScores,
      Map<String, Map<String, dynamic>> compScores, DAUComp dauComp) async {
    try {
      // cancel stream while we are doing mass updates
      // TODO consider removing
      // _tipperRoundScoresStream.cancel();
      // _tipperCompScoresStream.cancel();

      _db
          .child(scoresPathRoot)
          .child(dauComp.dbkey!)
          .child(roundScoresRoot)
          .update(roundScores);

      _db
          .child(scoresPathRoot)
          .child(dauComp.dbkey!)
          .child(compScoresRoot)
          .update(compScores);
      //}
    } finally {
      // restart the streams
      // TODO consider removing
      //_listenToScores;
    }
  }

  Future<List<LeaderboardEntry>> getLeaderboardForComp() async {
    // if (!_initialCompLoadCompleter.isCompleted) {
    //   await _initialCompLoadCompleter.future;
    // }

    // dummy up fake leaderboard
    var leaderboard = <LeaderboardEntry>[];
    for (var i = 0; i < 10; i++) {
      leaderboard.add(LeaderboardEntry(
          rank: i + 1,
          name: 'Tipper $i',
          total: 100,
          nRL: 50,
          aFL: 50,
          numRoundsWon: 5,
          aflMargins: 10,
          aflUPS: 10,
          nrlMargins: 10,
          nrlUPS: 10));
    }

    return leaderboard;
  }

  Future<RoundScores> getTipperConsolidatedScoresForRound(
      DAURound round) async {
    if (!_initialRoundLoadCompleter.isCompleted) {
      await _initialRoundLoadCompleter.future;
    }

    return _tipperRoundScores[round.dAUroundNumber - 1];
  }

  Future<CompScore> getTipperConsolidatedScoresForComp() async {
    if (!_initialCompLoadCompleter.isCompleted) {
      await _initialCompLoadCompleter.future;
    }

    return _tipperCompScores;
  }

  @override
  void dispose() {
    _tipperRoundScoresStream.cancel(); // stop listening to stream
    _tipperCompScoresStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
