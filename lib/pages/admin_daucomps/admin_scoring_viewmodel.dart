import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/consolidatedscores.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const scoresPathRoot = '/Scores';

class AllScoresViewModel extends ChangeNotifier {
  Map<String, int> _scores = {};
  Map<String, Map<String, int>> _allScores = {};
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _scoresStream;

  final String currentDAUComp;
  Tipper? tipper;
  final Completer<void> _initialLoadCompleter = Completer();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  //constructor
  AllScoresViewModel(this.currentDAUComp) {
    _listenToScores();
  }

  // Second constructor
  AllScoresViewModel.forTipper(this.currentDAUComp, this.tipper) {
    _listenToScores();
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToScores() async {
    if (tipper != null) {
      _scoresStream = _db
          .child('$scoresPathRoot/$currentDAUComp/${tipper!.name}')
          .onValue
          .listen(_handleEvent, onError: (error) {
        log('Error listening to scores: $error');
      });
    } else {
      _scoresStream = _db
          .child('$scoresPathRoot/$currentDAUComp')
          .onValue
          .listen(_handleEvent, onError: (error) {
        log('Error listening to scores: $error');
      });
    }
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      log('***AllScoresViewModel_handleEvent()***');
      if (event.snapshot.exists) {
        final dbData =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        // deserialize the scores, they will be in one of 2 formats depending on the contructor used:
        // 1. Map<String, int> if no tipperID is provided
        // 2. Map<String, Map<String, int>> if a tipperID is provided
        if (tipper != null) {
          // _TypeError (type '_Map<String, dynamic>' is not a subtype of type 'Map<String, int>' in type cast)
          //_scores = dbData as Map<String, int>; //

          _scores = dbData.map((key, value) {
            return MapEntry(key, int.tryParse(value.toString()) ?? 0);
          });
        } else {
          var tipperScores = dbData.map((key, value) => MapEntry(key, value));
          _allScores = tipperScores.map((key, value) =>
              MapEntry(key, Map<String, int>.from(value.cast<String, int>())));
        }
      }
    } catch (e) {
      log('Error listening to AllScores: $e');
      rethrow;
    } finally {
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
    }
  }

  writeConsolidatedScoresToDb(
      Map<String, Map<String, int>> consolidatedScores, DAUComp dauComp) async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }

    try {
      // cancel stream while we are doing mass updates
      _scoresStream.cancel();

      _db
          .child(scoresPathRoot)
          .child(dauComp.dbkey!)
          .update(consolidatedScores);
      //}
    } finally {
      // restart the stream
      _listenToScores;
    }
  }

  Future<ConsolidatedScores> getConsolidatedScoresForRound(
      DAURound round) async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }
    if (_scores.isEmpty) {
      return ConsolidatedScores(
        aflScore: 0,
        aflMaxScore: 0,
        aflMarginTips: 0,
        aflMarginUPS: 0,
        nrlScore: 0,
        nrlMaxScore: 0,
        nrlMarginTips: 0,
        nrlMarginUPS: 0,
        rank: 0,
      );
    }
    return ConsolidatedScores(
      aflScore: _scores['${round.dAUroundNumber}_afl_score'] != null
          ? _scores['${round.dAUroundNumber}_afl_score']!
          : 0,
      aflMaxScore: _scores['${round.dAUroundNumber}_afl_maxScore'] != null
          ? _scores['${round.dAUroundNumber}_afl_maxScore']!
          : 0,
      aflMarginTips: _scores['${round.dAUroundNumber}_afl_marginTips'] != null
          ? _scores['${round.dAUroundNumber}_afl_marginTips']!
          : 0,
      aflMarginUPS: _scores['${round.dAUroundNumber}_afl_marginUPS'] != null
          ? _scores['${round.dAUroundNumber}_afl_marginUPS']!
          : 0,
      nrlScore: _scores['${round.dAUroundNumber}_nrl_score'] != null
          ? _scores['${round.dAUroundNumber}_nrl_score']!
          : 0,
      nrlMaxScore: _scores['${round.dAUroundNumber}_nrl_maxScore'] != null
          ? _scores['${round.dAUroundNumber}_nrl_maxScore']!
          : 0,
      nrlMarginTips: _scores['${round.dAUroundNumber}_nrl_marginTips'] != null
          ? _scores['${round.dAUroundNumber}_nrl_marginTips']!
          : 0,
      nrlMarginUPS: _scores['${round.dAUroundNumber}_nrl_marginUPS'] != null
          ? _scores['${round.dAUroundNumber}_nrl_marginUPS']!
          : 0,
      rank: _scores['${round.dAUroundNumber}_total_score_rank'] != null
          ? _scores['${round.dAUroundNumber}_total_score_rank']!
          : 0,
    );
  }

  Future<ConsolidatedCompScores> getConsolidatedScoresForComp() async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }
    if (_scores.isEmpty) {
      return ConsolidatedCompScores(
        aflCompScore: 0,
        aflCompMaxScore: 0,
        nrlCompScore: 0,
        nrlCompMaxScore: 0,
      );
    }
    return ConsolidatedCompScores(
      aflCompScore:
          _scores['total_afl_score'] != null ? _scores['total_afl_score']! : 0,
      aflCompMaxScore: _scores['total_afl_maxScore'] != null
          ? _scores['total_afl_maxScore']!
          : 0,
      nrlCompScore:
          _scores['total_nrl_score'] != null ? _scores['total_nrl_score']! : 0,
      nrlCompMaxScore: _scores['total_nrl_maxScore'] != null
          ? _scores['total_nrl_maxScore']!
          : 0,
    );
  }

  @override
  void dispose() {
    _scoresStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
