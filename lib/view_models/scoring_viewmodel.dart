import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

// Define constants for Firestore database location
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

  final DAUComp currentDAUComp;

  bool _isScoring = false;
  bool get isScoring => _isScoring;

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

  // Constructor
  ScoresViewModel(this.currentDAUComp) {
    log('***ScoresViewModel_constructor(ALL TIPPERS)*** for comp: ${currentDAUComp.dbkey}');
    _listenToScores();
  }

  void update() {
    notifyListeners(); // Notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToScores() async {
    _allRoundScoresStream = _db
        .child('$scoresPathRoot/${currentDAUComp.dbkey}/$roundScoresRoot')
        .onValue
        .listen(_handleEventRoundScores, onError: (error) {
      log('Error listening to round scores: $error');
    });

    _allCompScoresStream = _db
        .child('$scoresPathRoot/${currentDAUComp.dbkey}/$compScoresRoot/')
        .onValue
        .listen(_handleEventCompScores, onError: (error) {
      log('Error listening to comp scores: $error');
    });

    _liveScoresStream = _db
        .child('$scoresPathRoot/${currentDAUComp.dbkey}/$liveScoresRoot')
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
              log('Tipper ${entry.key} does not exist in _handleEventRoundScores');
              return null;
            }
          }),
        ))
            .where((item) => item != null)
            .toList()
            .cast<MapEntry<Tipper, List<RoundScores>>>();

        _allTipperRoundScores = Map.fromEntries(entries);
      } else {
        log('Snapshot ${event.snapshot.ref.path} does not exist in _handleEventRoundScores');
      }

      if (!_initialRoundLoadCompleted.isCompleted) {
        _initialRoundLoadCompleted.complete();
      }

      // update the leaderboard
      updateLeaderboardForComp();
      // Update the round winners
      updateRoundWinners();

      notifyListeners();
    } catch (e) {
      log('Error listening to /Scores/round_scores: $e');

      if (!_initialRoundLoadCompleted.isCompleted) {
        _initialRoundLoadCompleted.complete();
      }
      rethrow;
    }
  }

  Future<void> _handleEventCompScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
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
                log('Tipper ${e.key} does not exist in _handleEventCompScores');
                return null;
              }
            }),
          ))
              .where((item) => item != null)
              .toList()
              .cast<MapEntry<Tipper, CompScore>>(),
        );
      } else {
        log('Snapshot ${event.snapshot.ref.path} does not exist in _handleEventCompScores');
      }

      if (!_initialCompAllTipperLoadCompleter.isCompleted) {
        _initialCompAllTipperLoadCompleter.complete();
      }

      notifyListeners();
    } catch (e) {
      log('Error listening to /Scores/comp_scores: $e');
      if (!_initialCompAllTipperLoadCompleter.isCompleted) {
        _initialCompAllTipperLoadCompleter.complete();
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _handleEventLiveScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        var dbData = event.snapshot.value;
        if (dbData is! Map) {
          throw Exception('Invalid data type for live scores');
        }
        _gamesWithLiveScores.clear();
        var gamesViewModel = di<GamesViewModel>();

        for (var entry in dbData.entries) {
          var game = await gamesViewModel.findGame(entry.key);
          var scoring =
              Scoring.fromJson(Map<String, dynamic>.from(entry.value));
          if (game!.scoring == null) {
            game.scoring = scoring;
          } else {
            game.scoring?.croudSourcedScores = scoring.croudSourcedScores;
          }

          _gamesWithLiveScores.add(game);

          // update the leaderboard
          updateLeaderboardForComp();
          // Update the round winners
          updateRoundWinners();

          notifyListeners();
        }
      }
    } catch (e) {
      log('Error listening to /Scores/live_scores: $e');
      rethrow;
    } finally {
      if (!_initialLiveScoreLoadCompleter.isCompleted) {
        _initialLiveScoreLoadCompleter.complete();
      }
    }
  }

  Future<String> updateScoring(DAUComp daucompToUpdate,
      Tipper? onlyUpdateThisTipper, DAURound? onlyUpdateThisRound) async {
    var stopwatch = Stopwatch()..start();
    try {
      if (_isScoring) {
        return 'Scoring already in progress';
      }

      _isScoring = true;
      notifyListeners();

      if (!_initialCompAllTipperLoadCompleter.isCompleted) {
        await _initialCompAllTipperLoadCompleter.future;
      }
      if (!_initialRoundLoadCompleted.isCompleted) {
        await _initialRoundLoadCompleted.future;
      }

      TippersViewModel tippersViewModel = di<TippersViewModel>();
      TipsViewModel allTipsViewModel = di<TipsViewModel>();
      Map<String, Map<String, dynamic>> scoringTipperCompTotals = {};
      Map<String, List<RoundScores>> scoringTipperRoundTotals = {};

      List<Tipper> tippersToUpdate = await _getTippersToUpdate(
          onlyUpdateThisTipper, tippersViewModel, daucompToUpdate);

      // when a tipper is no longer active in the comp then remove their scores from the database
      await _removeScoresInactiveTippers(tippersToUpdate, daucompToUpdate);

      for (Tipper tipperToScore in tippersToUpdate) {
        _initializeScoringMaps(
            scoringTipperCompTotals, scoringTipperRoundTotals, tipperToScore);
        var dauRoundsEdited = _getRoundsToUpdate(null,
            daucompToUpdate); //TODO only updating a single round does not display correctly in stats - round winners. hard code null for now

        List<Future> futures = [];
        for (DAURound dauRound in dauRoundsEdited) {
          futures.add(_calculateRoundScores(
              scoringTipperCompTotals,
              scoringTipperRoundTotals,
              tipperToScore,
              dauRound,
              allTipsViewModel));
        }

        await Future.wait(futures);
      }

      _rankTippers(scoringTipperRoundTotals, tippersToUpdate, daucompToUpdate);

      // Track changes for each tipper
      Map<Tipper, List<RoundScores>> changedTippers = {};

      for (var tipper in tippersToUpdate) {
        final List<RoundScores>? oldScores = _allTipperRoundScores[tipper];
        final newScores = scoringTipperRoundTotals[tipper.dbkey!];

        // Check if any scores have changed
        if (oldScores != null && newScores != null) {
          bool hasChanges = false;
          for (int i = 0; i < newScores.length; i++) {
            if (oldScores[i] != newScores[i]) {
              hasChanges = true;
              break;
            }
          }
          if (hasChanges) {
            changedTippers[tipper] = newScores;
          }
        } else {
          // Handle the case where oldScores or newScores is null
          if (oldScores != null || newScores != null) {
            changedTippers[tipper] = newScores!;
          }
        }
      }

      // // Update the leaderboard
      // updateLeaderboardForComp();

      // // Update the round winners
      // updateRoundWinners();

      // Only write changed scores to the database
      if (changedTippers.isNotEmpty) {
        await _writeScoresToDb(
            changedTippers, scoringTipperCompTotals, daucompToUpdate);
      }

      String res =
          'Completed scoring updates for ${tippersToUpdate.length} tippers and ${daucompToUpdate.daurounds.length} rounds.';
      log(res);

      _isScoring = false;
      notifyListeners();

      stopwatch.stop();
      log('updateScoring executed in ${stopwatch.elapsed}');
      log('onlyUpdateThisRound is null?: ${onlyUpdateThisRound == null}');

      return res;
    } catch (e) {
      _isScoring = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _removeScoresInactiveTippers(
      List<Tipper> tippersToUpdate, DAUComp daucompToUpdate) async {
    // when a tipper is no longer active in the comp then remove their scores from the database
    List<Tipper> tippersToRemove = [];
    for (var tipper in _allTipperRoundScores.keys) {
      if (!tippersToUpdate.contains(tipper)) {
        tippersToRemove.add(tipper);
      }
    }

    // iterate through tippersToRemove and remove their scores from the database
    for (var tipper in tippersToRemove) {
      await _db
          .child(scoresPathRoot)
          .child(daucompToUpdate.dbkey!)
          .child(roundScoresRoot)
          .child(tipper.dbkey!)
          .remove();
    }

    //also remove their comp scores
    for (var tipper in tippersToRemove) {
      await _db
          .child(scoresPathRoot)
          .child(daucompToUpdate.dbkey!)
          .child(compScoresRoot)
          .child(tipper.dbkey!)
          .remove();
    }
  }

  Future<void> _writeScoresToDb(
      Map<Tipper, List<RoundScores>> changedTipperRoundScores,
      Map<String, Map<String, dynamic>> compScores,
      DAUComp dauComp) async {
    // Update _allTipperRoundScores with the latest scores
    _allTipperRoundScores = {
      ..._allTipperRoundScores,
      ...changedTipperRoundScores,
    };

    // Write the changed scores to the database
    final roundScores = changedTipperRoundScores
        .map((key, value) => MapEntry(key.dbkey!, value));

    // turn off the listener to avoid a feedback loop
    _allRoundScoresStream.cancel();

    for (var roundScore in roundScores.entries) {
      await _db
          .child(scoresPathRoot)
          .child(dauComp.dbkey!)
          .child(roundScoresRoot)
          .child(roundScore.key)
          .set((roundScore.value).map((e) => e.toJson()).toList());
    }

    // turn the listener back on
    _allRoundScoresStream = _db
        .child('$scoresPathRoot/${currentDAUComp.dbkey}/$roundScoresRoot')
        .onValue
        .listen(_handleEventRoundScores, onError: (error) {
      log('Error listening to round scores: $error');
    });

    await _db
        .child(scoresPathRoot)
        .child(dauComp.dbkey!)
        .child(compScoresRoot)
        .set(compScores);
  }

  void updateRoundWinners() {
    Map<int, List<RoundWinnerEntry>> roundWinners = {};
    Map<int, int> maxRoundScores = {};

    for (var tipper in _allTipperRoundScores.keys) {
      for (var i = 0; i < _allTipperRoundScores[tipper]!.length; i++) {
        if (maxRoundScores[i] == null) {
          maxRoundScores[i] = 0;
        }
        var roundScores = _allTipperRoundScores[tipper]![i];
        if (roundScores.aflScore + roundScores.nrlScore > maxRoundScores[i]!) {
          maxRoundScores[i] = roundScores.aflScore + roundScores.nrlScore;
        }
      }
    }

    for (var tipper in _allTipperRoundScores.keys) {
      for (var i = 0; i < _allTipperRoundScores[tipper]!.length; i++) {
        var roundScores = _allTipperRoundScores[tipper]![i];
        if (roundScores.aflScore + roundScores.nrlScore == maxRoundScores[i]! &&
            roundScores.nrlMaxScore + roundScores.aflMaxScore > 0) {
          roundWinners[i] ??= [];
          roundWinners[i]!.add(RoundWinnerEntry(
            roundNumber: i + 1,
            tipper: tipper,
            total: roundScores.aflScore + roundScores.nrlScore,
            nRL: roundScores.nrlScore,
            aFL: roundScores.aflScore,
            aflMargins: roundScores.aflMarginTips,
            aflUPS: roundScores.aflMarginUPS,
            nrlMargins: roundScores.nrlMarginTips,
            nrlUPS: roundScores.nrlMarginUPS,
          ));

          if (_leaderboard.isNotEmpty) {
            var leaderboardEntry =
                _leaderboard.firstWhere((element) => element.tipper == tipper);
            leaderboardEntry.numRoundsWon++;
          }
        }
      }
    }

    _roundWinners = roundWinners;
    notifyListeners();
  }

  void updateLeaderboardForComp() {
    var leaderboard = _allTipperRoundScores.entries.map((e) {
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
    }).toList();

    //var leaderboard = await Future.wait(leaderboardFutures);
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

    _leaderboard = leaderboard.toList();

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

    if (_allTipperRoundScores.containsKey(tipper)) {
      // return the scores for each round, exclude rounds that have not been played yet
      // use getHighestRoundNumberWithAllGamesPlayed to determine the last round with all games played
      // then use that as an index to only return first n rounds in List<RoundScores>
      int latestRoundNumber = di<DAUCompsViewModel>()
          .selectedDAUComp!
          .getHighestRoundNumberWithAllGamesPlayed();

      return _allTipperRoundScores[tipper]!.sublist(0, latestRoundNumber);

      //return _allTipperRoundScores[tipper]!;
    } else {
      return [];
    }
  }

  Future<RoundScores?> getTipperConsolidatedScoresForRound(
      DAURound round, Tipper tipper) async {
    if (!_initialRoundLoadCompleted.isCompleted) {
      await _initialRoundLoadCompleted.future;
    }

    if (_allTipperRoundScores[tipper] == null) {
      return RoundScores(
        roundNumber: round.dAUroundNumber,
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
        roundNumber: round.dAUroundNumber,
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

  void addLiveScore(Game game, CrowdSourcedScore croudSourcedScore) {
    final oldScoring = game.scoring;

    final newScoring = oldScoring?.copyWith(
        croudSourcedScores: oldScoring.croudSourcedScores == null
            ? [croudSourcedScore]
            : [...oldScoring.croudSourcedScores!, croudSourcedScore]);

    game.scoring = newScoring;

    if (game.scoring?.croudSourcedScores != null &&
        game.scoring!.croudSourcedScores!
                .where((element) =>
                    element.scoreTeam == croudSourcedScore.scoreTeam)
                .length >
            3) {
      game.scoring!.croudSourcedScores!.removeWhere((element) =>
          element.scoreTeam == croudSourcedScore.scoreTeam &&
          element.submittedTimeUTC ==
              game.scoring!.croudSourcedScores!
                  .where((element) =>
                      element.scoreTeam == croudSourcedScore.scoreTeam)
                  .reduce((value, element) =>
                      value.submittedTimeUTC.isBefore(element.submittedTimeUTC)
                          ? value
                          : element)
                  .submittedTimeUTC);
    }

    di<ScoresViewModel>()._writeLiveScoreToDb(game);

    notifyListeners();
  }

  Future<void> _writeLiveScoreToDb(Game game) async {
    await Future.delayed(const Duration(milliseconds: 100));

    if (_gamesWithLiveScores.contains(game)) {
      game.scoring = game.scoring;
    } else {
      _gamesWithLiveScores.add(game);
    }

    Map<String, Map<String, dynamic>> liveScores = {};
    for (var game in _gamesWithLiveScores) {
      liveScores[game.dbkey] = game.scoring!.toJson();

      await _db
          .child(scoresPathRoot)
          .child(currentDAUComp.dbkey!)
          .child(liveScoresRoot)
          .update(liveScores);
    }
  }

  Future<List<Tipper>> _getTippersToUpdate(Tipper? updateThisTipper,
      TippersViewModel tippersViewModel, DAUComp daucompToUpdate) async {
    if (updateThisTipper != null) {
      return [updateThisTipper];
    } else {
      return await tippersViewModel.getActiveTippers(daucompToUpdate);
    }
  }

  void _initializeScoringMaps(
      Map<String, Map<String, dynamic>> scoringTipperCompTotals,
      Map<String, List<RoundScores>> scoringTipperRoundTotals,
      Tipper tipperToScore) {
    // make sure the List into the map is initialized to a set length
    scoringTipperRoundTotals[tipperToScore.dbkey!] = List.filled(
        currentDAUComp.daurounds.length,
        RoundScores(
          roundNumber: 0,
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
        ));

    scoringTipperCompTotals[tipperToScore.dbkey!] = {
      'total_nrl_score': 0,
      'total_nrl_maxScore': 0,
      'total_afl_score': 0,
      'total_afl_maxScore': 0
    };
  }

  List<DAURound> _getRoundsToUpdate(
      DAURound? onlyUpdateThisRound, DAUComp daucompToUpdate) {
    var dauRoundsEdited = daucompToUpdate.daurounds;
    if (onlyUpdateThisRound != null) {
      dauRoundsEdited = [onlyUpdateThisRound];
    }
    return dauRoundsEdited;
  }

  Future<void> _calculateRoundScores(
      Map<String, Map<String, dynamic>> scoringTipperCompTotals,
      Map<String, List<RoundScores>> scoringTipperRoundTotals,
      Tipper tipperToScore,
      DAURound dauRound,
      TipsViewModel allTipsViewModel) async {
    int roundIndex = dauRound.dAUroundNumber - 1;

    if (roundIndex >= scoringTipperRoundTotals[tipperToScore.dbkey]!.length) {
      scoringTipperRoundTotals[tipperToScore.dbkey]!.length = roundIndex + 1;
    }

    scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex] = RoundScores(
      roundNumber: dauRound.dAUroundNumber,
      aflScore: 0,
      aflMaxScore: 0,
      aflMarginTips: 0,
      aflMarginUPS: 0,
      nrlScore: 0,
      nrlMaxScore: 0,
      nrlMarginTips: 0,
      nrlMarginUPS: 0,
      rank: 0,
      rankChange: 0,
    );

    for (var game in dauRound.games) {
      TipGame? tipGame = await allTipsViewModel.findTip(game, tipperToScore);

      if (tipGame == null) {
        continue;
      }

      if (tipGame.game.gameState != GameState.notStarted ||
          tipGame.game.gameState != GameState.startingSoon) {
        int marginTip =
            (tipGame.tip == GameResult.a || tipGame.tip == GameResult.e)
                ? 1
                : 0;

        tipGame.game.league == League.afl
            ? scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]
                .aflMarginTips += marginTip
            : scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]
                .nrlMarginTips += marginTip;

        int score = tipGame.getTipScoreCalculated();
        int maxScore = tipGame.getMaxScoreCalculated();

        if (game.league == League.afl) {
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex].aflScore +=
              score;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]
              .aflMaxScore += maxScore;
        } else {
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex].nrlScore +=
              score;
          scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]
              .nrlMaxScore += maxScore;
        }

        // add this game score to the comp score based on league
        if (game.league == League.afl) {
          scoringTipperCompTotals[tipperToScore.dbkey]!['total_afl_score'] =
              scoringTipperCompTotals[tipperToScore.dbkey]![
                      'total_afl_score']! +
                  score;
          scoringTipperCompTotals[tipperToScore.dbkey]!['total_afl_maxScore'] =
              scoringTipperCompTotals[tipperToScore.dbkey]![
                      'total_afl_maxScore']! +
                  maxScore;
        } else {
          scoringTipperCompTotals[tipperToScore.dbkey]!['total_nrl_score'] =
              scoringTipperCompTotals[tipperToScore.dbkey]![
                      'total_nrl_score']! +
                  score;
          scoringTipperCompTotals[tipperToScore.dbkey]!['total_nrl_maxScore'] =
              scoringTipperCompTotals[tipperToScore.dbkey]![
                      'total_nrl_maxScore']! +
                  maxScore;
        }

        int marginUPS = 0;
        if (tipGame.game.scoring != null) {
          marginUPS = (tipGame.game.scoring!
                              .getGameResultCalculated(game.league) ==
                          GameResult.a &&
                      tipGame.tip == GameResult.a) ||
                  (tipGame.game.scoring!.getGameResultCalculated(game.league) ==
                          GameResult.e &&
                      tipGame.tip == GameResult.e)
              ? 1
              : 0;

          tipGame.game.league == League.afl
              ? scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]
                  .aflMarginUPS += marginUPS
              : scoringTipperRoundTotals[tipperToScore.dbkey]![roundIndex]
                  .nrlMarginUPS += marginUPS;
        }
      }
    }
  }

  void _rankTippers(Map<String, List<RoundScores>> scoringTipperRoundTotals,
      List<Tipper> tippers, DAUComp daucompToUpdate) {
    for (var roundIndex = 0;
        roundIndex < daucompToUpdate.daurounds.length;
        roundIndex++) {
      List<MapEntry<String, int>> roundScores = [];
      for (var tipper in tippers) {
        roundScores.add(MapEntry(
            tipper.dbkey!,
            scoringTipperRoundTotals[tipper.dbkey]![roundIndex].aflScore +
                scoringTipperRoundTotals[tipper.dbkey]![roundIndex].nrlScore));
      }

      roundScores.sort((a, b) => b.value.compareTo(a.value));

      int rank = 1;
      int? lastScore;
      int sameRankCount = 0;

      for (var entry in roundScores) {
        if (lastScore != null && entry.value != lastScore) {
          rank += sameRankCount + 1;
          sameRankCount = 0;
        } else if (lastScore != null && entry.value == lastScore) {
          sameRankCount++;
        }
        scoringTipperRoundTotals[entry.key]![roundIndex].rank = rank;

        if (roundIndex > 0) {
          int? lastRank =
              scoringTipperRoundTotals[entry.key]![roundIndex - 1].rank;
          int? changeInRank = lastRank - rank;
          scoringTipperRoundTotals[entry.key]![roundIndex].rankChange =
              changeInRank;
        }
        lastScore = entry.value;
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
