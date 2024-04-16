import 'dart:async';
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

class ScoresViewModel extends ChangeNotifier {
  Map<Tipper, List<RoundScores>> _allTipperRoundScores = {};
  Map<Tipper, List<RoundScores>> get allTipperRoundScores =>
      _allTipperRoundScores;

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

  final Completer<void> _initialRoundLoadCompleted = Completer();
  Future<void> get initialRoundComplete => _initialRoundLoadCompleted.future;

  final Completer<void> _initialCompAllTipperLoadCompleter = Completer();
  Future<void> get initialRoundAllTipperComplete =>
      _initialCompAllTipperLoadCompleter.future;

  List<LeaderboardEntry> _leaderboard = [];
  List<LeaderboardEntry> get leaderboard => _leaderboard;

  Map<int, List<RoundWinnerEntry>> _roundWinners = {};
  Map<int, List<RoundWinnerEntry>> get roundWinners => _roundWinners;

  //constructor
  ScoresViewModel(this.currentDAUComp) {
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
        var dbData = event.snapshot.value;
        if (dbData is! Map) {
          throw Exception('Invalid data type for all tipper round scores');
        }

        List<MapEntry<Tipper, List<RoundScores>>> entries = (await Future.wait(
          dbData.entries.map((entry) async {
            Tipper? tipper = await di<TippersViewModel>().findTipper(entry.key);
            if (tipper != null) {
              List<RoundScores> scores = (entry.value as List)
                  .map(
                      (e) => RoundScores.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
              return MapEntry(tipper, scores);
            } else {
              // tipper does not exist - skip this record
              log('Tipper ${entry.key} does not exist in _handleEventRoundScores');
              return null;
            }
          }),
        ))
            .where((item) => item != null)
            .toList()
            .cast<MapEntry<Tipper, List<RoundScores>>>();

        // Convert List<MapEntry> to Map
        _allTipperRoundScores = Map.fromEntries(entries);
      } else {
        log('sss in _handleEventRoundScores snapshot ${event.snapshot.ref.path}  does not exist');
      }

      await updateLeaderboardForComp();
      updateRoundWinners();
    } catch (e) {
      log('Error listening to /Scores/round_scores: $e');
      rethrow;
    }

    if (!_initialRoundLoadCompleted.isCompleted) {
      _initialRoundLoadCompleted.complete();
    }
  }

  Future<void> _handleEventCompScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        // returned data type is Map<Sting, Map<String, int>>
        // and needs to be converted to Map<Tipper, CompScore>
        _allTipperCompScores = Map<Tipper, CompScore>.fromEntries(
          (await Future.wait(
            (event.snapshot.value as Map<dynamic, dynamic>)
                .entries
                .map((e) async {
              Tipper? tipper = await di<TippersViewModel>().findTipper(e.key);
              if (tipper != null) {
                return MapEntry(tipper,
                    CompScore.fromJson(Map<String, dynamic>.from(e.value)));
              } else {
                // tipper does not exist - skip this record
                log('Tipper ${e.key} does not exist in _handleEventCompScores');
                return null;
              }
            }),
          ))
              .where((item) => item != null)
              .toList()
              .cast<MapEntry<Tipper, CompScore>>(),
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

      await updateLeaderboardForComp();
      updateRoundWinners();
    } catch (e) {
      log('Error listening to /Scores/comp_scores: $e');
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
      log('Error listening to /Scores/live_scores]: $e');
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

    // iterate through _allTipperRoundScores
    // the data is in the format Map<String, List<RoundScores>>
    // for each round and calculate the winner for each round
    // create  a RoundWinnerEntry for each winner and add to List<RoundWinnerEntry> _roundWinners
    // then notifyListeners

    Map<int, List<RoundWinnerEntry>> roundWinners = {};
    Map<int, int> maxRoundScores = {};

    // loop through the top level map of tippers
    for (var tipper in _allTipperRoundScores.keys) {
      // set the max score for the round to 0
      // loop through the list of round scores for each tipper
      for (var i = 0; i < _allTipperRoundScores[tipper]!.length; i++) {
        // if maxRoundScores is null, initialise it
        if (maxRoundScores[i] == null) {
          maxRoundScores[i] = 0;
        }
        // get the round scores for the current tipper/round
        var roundScores = _allTipperRoundScores[tipper]![i];
        // if this tipper has the highest score, so far, for this round, update maxRoundScores
        if (roundScores.aflScore + roundScores.nrlScore > maxRoundScores[i]!) {
          maxRoundScores[i] = roundScores.aflScore + roundScores.nrlScore;
        }
      }
    }
    // now that we have identified the max score for each round, we can identify the winners
    // loop through the top level map of tippers
    //ignore rounds where the scoring is zero
    for (var tipper in _allTipperRoundScores.keys) {
      // loop through the list of round scores for each tipper
      for (var i = 0; i < _allTipperRoundScores[tipper]!.length; i++) {
        // get the round scores for the current tipper/round
        var roundScores = _allTipperRoundScores[tipper]![i];
        // if the tipper has the highest score for this round,
        //and this round has been scored, then add them to the roundWinners list
        if (roundScores.aflScore + roundScores.nrlScore == maxRoundScores[i]! &&
            roundScores.nrlMaxScore + roundScores.aflMaxScore > 0) {
          if (roundWinners[i] == null) {
            roundWinners[i] = [];
          }
          roundWinners[i]!.add((RoundWinnerEntry(
            roundNumber: i + 1,
            tipper: tipper,
            total: roundScores.aflScore + roundScores.nrlScore,
            nRL: roundScores.nrlScore,
            aFL: roundScores.aflScore,
            aflMargins: roundScores.aflMarginTips,
            aflUPS: roundScores.aflMarginUPS,
            nrlMargins: roundScores.nrlMarginTips,
            nrlUPS: roundScores.nrlMarginUPS,
          )));

          // also increment the maxroundswon counter in the comp leaderboard
          // first check _leaderboard is not empty
          if (_leaderboard.isNotEmpty) {
            // find the leaderboard entry for this tipper
            var leaderboardEntry =
                _leaderboard.firstWhere((element) => element.tipper == tipper);
            // increment the numRoundsWon counter
            leaderboardEntry.numRoundsWon++;
          }
        }
      }
    }

    _roundWinners = roundWinners;

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

      return LeaderboardEntry(
        rank: 0, // replace with actual rank calculation - see below
        tipper: e.key,
        total: totalScore,
        nRL: nrlScore,
        aFL: aflScore,
        numRoundsWon: 0, // replace with actual numRoundsWon calculation
        aflMargins: aflMargins,
        aflUPS: aflMarginUps,
        nrlMargins: nrlMargins,
        nrlUPS: nrlMarginUps,
      );
    });

    // Wait for all the futures to complete and then sort the leaderboard
    var leaderboard = await Future.wait(leaderboardFutures);
    leaderboard.sort((a, b) => b.total.compareTo(a.total));

    // calculate the rank based on total score
    int rank = 1;
    int skip = 1;
    for (int i = 0; i < leaderboard.length; i++) {
      if (i > 0 && leaderboard[i].total < leaderboard[i - 1].total) {
        rank += skip;
        skip = 1;
      } else if (i > 0 && leaderboard[i].total == leaderboard[i - 1].total) {
        skip++;
      }
      leaderboard[i].rank = rank; // update the rank
    }

    // Sort by rank and then by tipper name
    leaderboard.sort((a, b) {
      int rankComparison = a.rank.compareTo(b.rank);
      if (rankComparison == 0) {
        return a.tipper.name
            .toLowerCase()
            .compareTo(b.tipper.name.toLowerCase());
      } else {
        return rankComparison;
      }
    });

    _leaderboard = leaderboard.toList(); // Update the property

    notifyListeners();
    return;
  }

  void sortRoundWinnersByRoundNumber(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) =>
          ascending ? a.key.compareTo(b.key) : b.key.compareTo(a.key));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  void sortRoundWinnersByWinner(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) => ascending
          ? a.value[0].tipper.name
              .toLowerCase()
              .compareTo(b.value[0].tipper.name.toLowerCase())
          : b.value[0].tipper.name
              .toLowerCase()
              .compareTo(a.value[0].tipper.name.toLowerCase()));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  void sortRoundWinnersByTotal(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) => ascending
          ? a.value[0].total.compareTo(b.value[0].total)
          : b.value[0].total.compareTo(a.value[0].total));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  List<RoundScores> getTipperRoundScoresForComp(Tipper tipper) {
    if (!_initialRoundLoadCompleted.isCompleted) {
      return [];
    }

    // filter out rounds yet to be scored
    if (_allTipperRoundScores.containsKey(tipper)) {
      return _allTipperRoundScores[tipper]!.where((element) {
        return element.aflMaxScore + element.nrlMaxScore > 0;
      }).toList();
    } else {
      // Handle the case when _allTipperRoundScores[tipper] is null
      return [];
    }
  }

  Future<RoundScores> getTipperConsolidatedScoresForRound(
      DAURound round, Tipper tipper) async {
    if (!_initialRoundLoadCompleted.isCompleted) {
      await _initialRoundLoadCompleted.future;
    }

    // this should stop the null check error that appears in UI intermittently
    if (_allTipperRoundScores[tipper] == null) {
      return RoundScores(
        rank: 0,
        rankChange: 0,
        aflScore: 0,
        aflMaxScore: 0,
        nrlScore: 0,
        nrlMaxScore: 0,
        aflMarginTips: 0,
        aflMarginUPS: 0,
        nrlMarginTips: 0,
        nrlMarginUPS: 0,
      );
    }

    if (_allTipperRoundScores[tipper]!.length < round.dAUroundNumber) {
      return RoundScores(
        rank: 0,
        rankChange: 0,
        aflScore: 0,
        aflMaxScore: 0,
        nrlScore: 0,
        nrlMaxScore: 0,
        aflMarginTips: 0,
        aflMarginUPS: 0,
        nrlMarginTips: 0,
        nrlMarginUPS: 0,
      );
    }

    return _allTipperRoundScores[tipper]![round.dAUroundNumber - 1];
  }

  CompScore getTipperConsolidatedScoresForComp(Tipper tipper) {
    // return 0 scores until the data is loaded for this tipper

    if (_allTipperCompScores[tipper] == null) {
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
