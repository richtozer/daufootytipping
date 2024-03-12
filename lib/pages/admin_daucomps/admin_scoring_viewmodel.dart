import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

// define  constant for firestore database location
const scoresPathRoot = '/Scores';
const roundScoresRoot = 'round_scores';
const compScoresRoot = 'comp_scores';
const liveScoresRoot = 'live_scores';

class AllScoresViewModel extends ChangeNotifier {
  Map<String, List<RoundScores>> _allTipperRoundScores = {};
  Map<Tipper, CompScore> _allTipperCompScores = {};
  final List<Game> _gamesWithLiveScores = [];

  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _liveScoresStream;
  late StreamSubscription<DatabaseEvent> _allRoundScoresStream;
  late StreamSubscription<DatabaseEvent> _allCompScoresStream;

  final String currentDAUComp;

  final Completer<void> _initialLiveScoreLoadCompleter = Completer();
  Future<void> get initialLiveScoreLoadComplete =>
      _initialLiveScoreLoadCompleter.future;

  final Completer<void> _initialRoundLoadCompleter = Completer();
  Future<void> get initialRoundComplete => _initialRoundLoadCompleter.future;

  final Completer<void> _initialCompAllTipperLoadCompleter = Completer();
  Future<void> get initialRoundAllTipperComplete =>
      _initialCompAllTipperLoadCompleter.future;

  List<LeaderboardEntry> _leaderboard = [];
  List<LeaderboardEntry> get leaderboard => _leaderboard;

  List<RoundWinnerEntry> _roundWinners = [];
  List<RoundWinnerEntry> get roundWinners => _roundWinners;

  //constructor
  AllScoresViewModel(this.currentDAUComp) {
    log('***ScoresViewModel_constructor(ALL TIPPERS)***');
    _listenToScores();
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToScores() async {
    _allRoundScoresStream = _db
        .child('$scoresPathRoot/$currentDAUComp/$roundScoresRoot')
        .onValue
        .listen(_handleEventRoundScores, onError: (error) {
      log('Error listening to round scores: $error');
    });

    _allCompScoresStream = _db
        .child('$scoresPathRoot/$currentDAUComp/$compScoresRoot/')
        .onValue
        .listen(_handleEventCompScores, onError: (error) {
      log('Error listening to comp scores: $error');
    });

    _liveScoresStream = _db
        .child('$scoresPathRoot/$currentDAUComp/$liveScoresRoot')
        .onValue
        .listen(_handleEventLiveScores, onError: (error) {
      log('Error listening to live scores: $error');
    });
  }

  Future<void> _handleEventRoundScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        //deserialize the all tipper scores they are in Map<String,List<Map<String, Int>>> format
        //and need to be converted to Map<String, List<RoundScores>>
        var dbData = event.snapshot.value;
        if (dbData is! Map) {
          throw Exception('Invalid data type for all tipper round scores');
        }
        _allTipperRoundScores = dbData.map((key, value) {
          return MapEntry(
              key,
              (value as List)
                  .map(
                      (e) => RoundScores.fromJson(Map<String, dynamic>.from(e)))
                  .toList());
        });

        if (!_initialRoundLoadCompleter.isCompleted) {
          _initialRoundLoadCompleter.complete();
        }
      } else {
        log('sss in _handleEventRoundScores snapshot ${event.snapshot.ref.path}  does not exist');
      }

      updateLeaderboardForComp();
      updateRoundWinners();
    } catch (e) {
      log('Error listening to /Scores: $e');
      rethrow;
    }
  }

  Future<void> _handleEventCompScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        // returned data type is Map<Sting, Map<String, int>>
        // and needs to be converted to Map<Tipper, CompScore>
        _allTipperCompScores = Map<Tipper, CompScore>.fromEntries(
          await Future.wait((event.snapshot.value as Map<dynamic, dynamic>)
              .entries
              .map((e) async {
            Tipper tipper = await di<TippersViewModel>().findTipper(e.key);
            return MapEntry(
                tipper, CompScore.fromJson(Map<String, dynamic>.from(e.value)));
          })),
        );

        // _allTipperCompScores = CompScore.fromJson(Map<String, dynamic>.from(
        //     event.snapshot.value as Map<dynamic, dynamic>));

        if (!_initialCompAllTipperLoadCompleter.isCompleted) {
          _initialCompAllTipperLoadCompleter.complete();
        }

        notifyListeners();
      } else {
        log('sss in _handleEventCompScores snapshot ${event.snapshot.ref.path}  does not exist');
      }

      updateLeaderboardForComp();
      updateRoundWinners();
    } catch (e) {
      log('Error listening to /Scores: $e');
      rethrow;
    }
  }

  Future<void> _handleEventLiveScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        //deserialize the live scores - they are in this fomat: Map<String, Map<String , dynamic>>
        //and need to be converted to List<Game>
        var dbData = event.snapshot.value;
        if (dbData is! Map) {
          throw Exception('Invalid data type for live scores');
        }
        _gamesWithLiveScores.clear();
        var gamesViewModel = di<GamesViewModel>();

        for (var entry in dbData.entries) {
          var game = await gamesViewModel.findGame(entry.key);
          //create a temporary scoring object to hold the live scores
          var scoring =
              Scoring.fromJson(Map<String, dynamic>.from(entry.value));
          if (game!.scoring == null) {
            game.scoring = scoring;
          } else {
            game.scoring?.croudSourcedScores = scoring.croudSourcedScores;
          }

          _gamesWithLiveScores.add(game);

          notifyListeners();

          //cleanup any stale live scores
          staleLiveScoreCleanup();
        }

        if (!_initialLiveScoreLoadCompleter.isCompleted) {
          _initialLiveScoreLoadCompleter.complete();
        }
      }
    } catch (e) {
      log('Error listening to /Scores/[comp/live_scores]: $e');
      rethrow;
    }
  }

  writeLiveScoreToDb(Scoring scoring, Game game) async {
    // check if the game is already in the list of games with live scores
    // if it is, update the game with the new live score
    // if it is not, add the game to the list of games with live scores
    // then update the live scores in the database

    //yield to allow UI update and dismiss the keyboard
    await Future.delayed(const Duration(milliseconds: 100));

    if (_gamesWithLiveScores.contains(game)) {
      game.scoring = scoring;
    } else {
      _gamesWithLiveScores.add(game);
    }

    // convert _gamesWithLiveScores into a Map for the database update
    Map<String, Map<String, dynamic>> liveScores = {};
    for (var game in _gamesWithLiveScores) {
      liveScores[game.dbkey] = game.scoring!.toJson();

      _db
          .child(scoresPathRoot)
          .child(currentDAUComp)
          .child(liveScoresRoot)
          //.child(game.dbkey)
          .update(liveScores);
    }
  }

  writeScoresToDb(Map<String, Map<int, Map<String, int>>> roundScores,
      Map<String, Map<String, dynamic>> compScores, DAUComp dauComp) async {
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
  }

  Future<void> updateRoundWinners() async {
    if (!_initialCompAllTipperLoadCompleter.isCompleted) {
      await _initialCompAllTipperLoadCompleter.future;
    }

    // iterate through each round and calculate the winner for each round
    // create  a RoundWinnerEntry for each winner and add to List<RoundWinnerEntry> _roundWinners
    _allTipperRoundScores.entries.map((e) {
      String tipperID = e.key; // capture the tipperID here
      int maxScore = e.value.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflScore + roundScores.nrlScore));

      List<RoundScores> winners = e.value
          .where((element) => element.aflScore + element.nrlScore == maxScore)
          .toList();

      _roundWinners = winners
          .map((e) => RoundWinnerEntry(
              roundNumber: 1, //TODO replace with actual round number
              name: tipperID, //TODO replace with actual tipper name
              total: e.aflScore + e.nrlScore,
              nRL: e.nrlScore,
              aFL: e.aflScore,
              aflMargins: e.aflMarginTips,
              aflUPS: e.aflMarginUPS,
              nrlMargins: e.nrlMarginTips,
              nrlUPS: e.nrlMarginUPS))
          .toList();
    }).toList();
    notifyListeners();
  }

  Future<void> updateLeaderboardForComp() async {
    if (!_initialCompAllTipperLoadCompleter.isCompleted) {
      await _initialCompAllTipperLoadCompleter.future;
    }
    var leaderboardFutures = _allTipperRoundScores.entries.map((e) async {
      int totalScore = e.value.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflScore + roundScores.nrlScore));

      int nrlScore = e.value.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.nrlScore));

      int aflScore = e.value.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflScore));

      int aflMargins = e.value.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflMarginTips));

      int aflMarginUps = e.value.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflMarginUPS));

      int nrlMargins = e.value.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.nrlMarginTips));

      int nrlMarginUps = e.value.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.nrlMarginUPS));

      Tipper tipper = await di<TippersViewModel>().findTipper(e.key);

      return LeaderboardEntry(
        rank: 0, // replace with actual rank calculation - see below
        tipper: tipper,
        total: totalScore,
        nRL: nrlScore, // replace with actual nRL calculation
        aFL: aflScore, // replace with actual aFL calculation
        numRoundsWon: 0, // replace with actual numRoundsWon calculation
        aflMargins: aflMargins, // replace with actual aflMargins calculation
        aflUPS: aflMarginUps, // replace with actual aflUPS calculation
        nrlMargins: nrlMargins, // replace with actual nrlMargins calculation
        nrlUPS: nrlMarginUps, // replace with actual nrlUPS calculation
        profileURL: tipper.photoURL,
      );
    });

    var leaderboard = await Future.wait(leaderboardFutures);
    leaderboard.sort((a, b) => b.total.compareTo(a.total));
    int rank = 1;
    int skip = 1;
    for (int i = 0; i < leaderboard.length; i++) {
      if (i > 0 && leaderboard[i].total < leaderboard[i - 1].total) {
        rank += skip;
        skip = 1;
      } else if (i > 0 && leaderboard[i].total == leaderboard[i - 1].total) {
        skip++;
      }
      leaderboard[i].rank = rank;
    }

    _leaderboard = leaderboard.toList(); // Update the property

    notifyListeners();
    return;
  }

  Future<RoundScores> getTipperConsolidatedScoresForRound(
      DAURound round, Tipper tipper) async {
    if (!_initialRoundLoadCompleter.isCompleted) {
      await _initialRoundLoadCompleter.future;
    }

    return _allTipperRoundScores[tipper.dbkey]![round.dAUroundNumber - 1];
  }

  CompScore getTipperConsolidatedScoresForComp(Tipper tipper) {
    if (_allTipperCompScores.isEmpty) {
      return CompScore(
        aflCompScore: 0,
        aflCompMaxScore: 0,
        nrlCompScore: 0,
        nrlCompMaxScore: 0,
      );
    }
    return _allTipperCompScores[tipper]!;
  }

  void staleLiveScoreCleanup() {
    // iterate of _gamesWithLiveScores
    // if the gamestate is GameState.resultKnown then go ahead and delete the record from the db
    // at this location  _db.child(scoresPathRoot).child(currentDAUComp).child(liveScoresRoot).child(game.dbkey)

    for (var game in _gamesWithLiveScores) {
      if (game.gameState == GameState.resultKnown) {
        _db
            .child(scoresPathRoot)
            .child(currentDAUComp)
            .child(liveScoresRoot)
            .child(game.dbkey)
            .remove();
      }
    }
  }

  @override
  void dispose() {
    _allRoundScoresStream.cancel();
    _allCompScoresStream.cancel();
    _liveScoresStream.cancel();

    super.dispose();
  }
}
