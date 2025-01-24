import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

// Define constants for Firestore database location
const statsPathRoot = '/Stats';
const roundStatsRoot = 'round_stats';
const liveScoresRoot = 'live_scores';

class StatsViewModel extends ChangeNotifier {
  final Map<int, Map<Tipper, RoundStats>> _allTipperRoundStats = {};
  Map<int, Map<Tipper, RoundStats>> get allTipperRoundStats =>
      _allTipperRoundStats;

  final List<Game> _gamesWithLiveScores = [];

  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _liveScoresStream;
  late StreamSubscription<DatabaseEvent> _allRoundScoresStream;

  final DAUComp selectedDAUComp;

  bool _isCalculating = false;
  bool get isCalculating => _isCalculating;
  bool _isUpdatingLeaderAndRoundAndRank = false;

  final Completer<void> _initialLiveScoreLoadCompleter = Completer();
  Future<void> get initialLiveScoreLoadComplete =>
      _initialLiveScoreLoadCompleter.future;

  final Completer<void> _initialRoundLoadCompleted = Completer();
  Future<void> get initialRoundComplete => _initialRoundLoadCompleted.future;

  List<LeaderboardEntry> _leaderboard = [];
  List<LeaderboardEntry> get leaderboard => _leaderboard;

  Map<int, List<RoundWinnerEntry>> _roundWinners = {};
  Map<int, List<RoundWinnerEntry>> get roundWinners => _roundWinners;

  bool _isScoringPaidComp = false;

  // Constructor
  StatsViewModel(this.selectedDAUComp) {
    log('StatsViewModel(ALL TIPPERS) for comp: ${selectedDAUComp.dbkey}');
    _listenToScores();

    // segregate tippers based on if they are paid members for the active comp
    // if the authenticated tipper is not a paid tipper, then score them with
    // all other non-paid tippers
    // otherwise score them will all other paid members
    if (di<TippersViewModel>().authenticatedTipper != null) {
      _isScoringPaidComp = di<TippersViewModel>()
          .authenticatedTipper!
          .paidForComp(selectedDAUComp);
    }
  }

  void _listenToScores() async {
    _allRoundScoresStream = _db
        .child('$statsPathRoot/${selectedDAUComp.dbkey}/$roundStatsRoot')
        .onValue
        .listen(_handleEventRoundScores, onError: (error) {
      log('Error listening to round scores: $error');
    });

    _liveScoresStream = _db
        .child('$statsPathRoot/${selectedDAUComp.dbkey}/$liveScoresRoot')
        .onValue
        .listen(_handleEventLiveScores, onError: (error) {
      log('Error listening to live scores: $error');
    });
  }

  Future<void> _handleEventRoundScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        var dbData = event.snapshot.value as List<Object?>;
        // Deserialize the round scores into _allTipperRoundStats
        for (var roundIndex = 0; roundIndex < dbData.length; roundIndex++) {
          var roundScoresJson = dbData[roundIndex] as Map<dynamic, dynamic>;
          Map<Tipper, RoundStats> roundScores = {};
          for (var entry in roundScoresJson.entries) {
            var tipper = await di<TippersViewModel>().findTipper(entry.key);
            var roundStats = RoundStats.fromJson(Map<String, dynamic>.from(
                entry.value as Map<dynamic, dynamic>));
            if (tipper != null) {
              roundScores[tipper] = roundStats;
            } else {
              log('Tipper ${entry.key} not found in _handleEventRoundScores');
            }
          }
          _allTipperRoundStats[roundIndex] = roundScores;
        }
      } else {
        log('Snapshot ${event.snapshot.ref.path} does not exist in _handleEventRoundScores');
      }

      if (!_initialRoundLoadCompleted.isCompleted) {
        _initialRoundLoadCompleted.complete();
      }

      //check if updateScoring is in progress, if so, skip the following steps
      if (_isCalculating) {
        return;
      }

      // update the leaderboard
      await updateLeaderAndRoundAndRank();
    } catch (e) {
      log('Error listening to /Stats/round_scores: $e');
      rethrow;
    } finally {}
  }

  Future<void> updateLeaderAndRoundAndRank() async {
    try {
      if (_isUpdatingLeaderAndRoundAndRank) {
        return;
      } else {
        log('StatsViewModel: _handleEventRoundScores() - Calculating not in progress, updating leaderboard and round winners');
        _isUpdatingLeaderAndRoundAndRank = true;
      }

      // update the leaderboard
      _updateLeaderboardForComp();
      // Update the round winners
      _updateRoundWinners();
      // rank the tippers
      await _rankTippers();

      notifyListeners();
    } catch (e) {
      log('Error updating leaderboard and round winners: $e');
      rethrow;
    } finally {
      _isUpdatingLeaderAndRoundAndRank = false;
    }
  }

  Future<void> _handleEventLiveScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        var dbData = event.snapshot.value as Map<dynamic, dynamic>;

        _gamesWithLiveScores.clear();
        var gamesViewModel = di<DAUCompsViewModel>().gamesViewModel;

        for (var entry in dbData.entries) {
          var game = await gamesViewModel!.findGame(entry.key);
          var scoring =
              Scoring.fromJson(Map<String, dynamic>.from(entry.value));
          if (game!.scoring == null) {
            game.scoring = scoring;
          } else {
            game.scoring?.croudSourcedScores = scoring.croudSourcedScores;
          }

          _gamesWithLiveScores.add(game);

          log('Loaded live score for game ${game.dbkey}');
        }

        notifyListeners();
      }
    } catch (e) {
      log('Error listening to /Stats/live_scores: $e');
      rethrow;
    } finally {
      if (!_initialLiveScoreLoadCompleter.isCompleted) {
        _initialLiveScoreLoadCompleter.complete();
      }
    }
  }

  Future<String> updateStats(DAUComp daucompToUpdate,
      DAURound? onlyUpdateThisRound, Tipper? onlyUpdateThisTipper) async {
    log('updateScoring() called for comp: ${daucompToUpdate.name}');
    var stopwatch = Stopwatch()..start();
    try {
      if (_isCalculating) {
        return 'Calcuating already in progress';
      }

      if (!_initialRoundLoadCompleted.isCompleted) {
        await _initialRoundLoadCompleted.future;
      }

      _isCalculating = true;

      // write a firebase analytic event that scoring is underway
      FirebaseAnalytics.instance
          .logEvent(name: 'scoring_initiated', parameters: {
        'comp': daucompToUpdate.name,
        'round': onlyUpdateThisRound?.dAUroundNumber ?? 'all',
        'tipper': onlyUpdateThisTipper?.name ?? 'all',
      });

      TipsViewModel allTipsViewModel = TipsViewModel(di<TippersViewModel>(),
          daucompToUpdate, di<DAUCompsViewModel>().gamesViewModel!);

      // set the initial list of tippers to update
      List<Tipper> tippersToUpdate = [];
      if (onlyUpdateThisTipper != null) {
        tippersToUpdate = [onlyUpdateThisTipper];
        log('Only updating stats for tipper ${onlyUpdateThisTipper.name}');
      } else {
        List<Tipper> allTippers = await di<TippersViewModel>().getAllTippers();
        // preserve the oriignal list of tippers, take a copy
        tippersToUpdate = List.from(allTippers);
        log('Updating stats for all ${tippersToUpdate.length} tippers');
      }

      // remove any tippers who did not place any tips this comp
      List<Tipper> tippersToRemove = [];
      for (Tipper tipper in tippersToUpdate) {
        bool hasSubmitted = await allTipsViewModel.hasSubmittedTips(tipper);
        if (!hasSubmitted) {
          tippersToRemove.add(tipper);
        }
      }
      tippersToUpdate.removeWhere((tipper) => tippersToRemove.contains(tipper));

      var dauRoundsEdited =
          _getRoundsToUpdate(onlyUpdateThisRound, daucompToUpdate);

      Map<int, Map<Tipper, RoundStats>> allRoundStats = {};

      for (DAURound dauRound in dauRoundsEdited) {
        allRoundStats[dauRound.dAUroundNumber - 1] = await _calculateRoundStats(
            tippersToUpdate, dauRound, allTipsViewModel);
      }

      if (onlyUpdateThisRound == null) {
        // Write the entire list of round scores back to the database in one transaction
        await _writeAllRoundScoresToDb(allRoundStats, daucompToUpdate);
      } else {
        // Only update the specific round (index) in the database
        await _writeSpecificRoundScoresToDb(allRoundStats, daucompToUpdate,
            onlyUpdateThisRound.dAUroundNumber - 1);
      }

      String res =
          'Completed scoring updates for ${tippersToUpdate.length} tippers and ${dauRoundsEdited.length} rounds.';
      log(res);

      _deleteStaleLiveScores();

      return res;
    } catch (e) {
      log('Error updating scoring: $e');
      rethrow;
    } finally {
      stopwatch.stop();
      log('updateScoring executed in ${stopwatch.elapsed}');
      _isCalculating = false;
      notifyListeners();
    }
  }

  Future<void> _writeAllRoundScoresToDb(
      Map<int, Map<Tipper, RoundStats>> updatedTipperRoundStats,
      DAUComp dauComp) async {
    log('Writing all round scores to DB for ${updatedTipperRoundStats.length} rounds');

    // convert updatedTipperRoundStats to a Map<String, dynamic> for writing to the database
    Map<String, dynamic> updatedTipperRoundStatsJson = {};
    for (var roundIndex in updatedTipperRoundStats.keys) {
      updatedTipperRoundStatsJson[roundIndex.toString()] = {};
      for (var tipper in updatedTipperRoundStats[roundIndex]!.keys) {
        updatedTipperRoundStatsJson[roundIndex.toString()][tipper.dbkey!] =
            updatedTipperRoundStats[roundIndex]![tipper]!.toJson();
      }
    }

    await _db
        .child(statsPathRoot)
        .child(dauComp.dbkey!)
        .child(roundStatsRoot)
        .set(updatedTipperRoundStatsJson);
  }

  Future<void> _writeSpecificRoundScoresToDb(
      Map<int, Map<Tipper, RoundStats>> updatedTipperRoundStats,
      DAUComp dauComp,
      int roundIndex) async {
    log('Writing specific stats for round $roundIndex');

    // convert updatedTipperRoundStats to a Map<String, dynamic> for writing to the database
    Map<String, dynamic> updatedTipperRoundStatsJson = {};
    for (var tipper in updatedTipperRoundStats[roundIndex]!.keys) {
      updatedTipperRoundStatsJson[tipper.dbkey!] =
          updatedTipperRoundStats[roundIndex]![tipper]!.toJson();
    }

    await _db
        .child(statsPathRoot)
        .child(dauComp.dbkey!)
        .child(roundStatsRoot)
        .child(roundIndex.toString())
        .set(updatedTipperRoundStatsJson);
  }

  // method to update margin counts. Params are the tip to update
  Future<String> updateMarginsAsResultOfTip(
      Tip tip, Tip? originalTip, DAURound dauRound) async {
    log('updateMargins() called for tip: ${tip.tipper.name}');

    try {
      if (!_initialRoundLoadCompleted.isCompleted) {
        await _initialRoundLoadCompleted.future;
      }

      if (_isCalculating) {
        return 'Stats calculation already in progress';
      }

      // if this is the first time this tipper has tipped in this comp
      // then we need to initialize their stats for this round so we can update the margin counts
      if (!_allTipperRoundStats.containsKey(dauRound.dAUroundNumber - 1)) {
        // do a mini stats calculation for the tipper and round in question
        log('Initializing stats for tipper ${tip.tipper.name} in round ${dauRound.dAUroundNumber}');
        String res = await updateStats(selectedDAUComp, dauRound, tip.tipper);
        if (res.contains('Error')) {
          return res;
        }
      }

      assert(_allTipperRoundStats.containsKey(dauRound.dAUroundNumber - 1));

      // find the current round stats record for this tipper
      RoundStats? roundScores;
      var roundStats = _allTipperRoundStats[dauRound.dAUroundNumber - 1];
      if (roundStats != null) {
        roundScores = roundStats[tip.tipper];
      }
      // take note of the current afl and nrl margin counts
      int originalAFLMarginCount = roundScores?.aflMarginTips ?? 0;
      int originalNRLMarginCount = roundScores?.nrlMarginTips ?? 0;

      // if originalTip is null and the tip is a margin tip, then we are incrementing the current margin count
      // if originalTip is null and the tip is a not margin tip, then do nothing
      // if originalTip is not null, then if the change is from a margin tip to a not margin tip, we decrement the margin count
      // if originalTip is not null, then if the change is from a not margin tip to a margin tip, we increment the margin count

      if (originalTip == null) {
        if (tip.tip == GameResult.a || tip.tip == GameResult.e) {
          tip.game.league == League.afl
              ? originalAFLMarginCount++
              : originalNRLMarginCount++;
        }
      } else {
        if ((originalTip.tip == GameResult.a ||
                originalTip.tip == GameResult.e) &&
            (tip.tip != GameResult.a && tip.tip != GameResult.e)) {
          originalTip.game.league == League.afl
              ? originalAFLMarginCount--
              : originalNRLMarginCount--;
        } else if ((originalTip.tip != GameResult.a &&
                originalTip.tip != GameResult.e) &&
            (tip.tip == GameResult.a || tip.tip == GameResult.e)) {
          tip.game.league == League.afl
              ? originalAFLMarginCount++
              : originalNRLMarginCount++;
        }
      }

      // update the database with the new margin counts
      await _db
          .child(statsPathRoot)
          .child(selectedDAUComp.dbkey!)
          .child(roundStatsRoot)
          .child((dauRound.dAUroundNumber - 1).toString())
          .child(tip.tipper.dbkey!)
          .update({
        'afl_marginTips': originalAFLMarginCount,
        'nrl_marginTips': originalNRLMarginCount,
      });

      String res =
          'Completed updating margins for tipper ${tip.tipper.name} in round ${dauRound.dAUroundNumber}. AFL margins: $originalAFLMarginCount, NRL margins: $originalNRLMarginCount';
      log(res);

      return res;
    } catch (e) {
      log('Error updating margins: $e');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  void _updateRoundWinners() {
    Map<int, List<RoundWinnerEntry>> roundWinners = {};
    Map<int, int> maxRoundScores = {};

    // Iterate over each round
    for (var roundEntry in _allTipperRoundStats.entries) {
      int roundNumber = roundEntry.key;
      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      // Find the maximum score for the round
      for (var tipperEntry in tipperStats.entries) {
        // only include tippers who's paid status matches that of the authenticated tipper
        if (_isScoringPaidComp !=
            tipperEntry.key.paidForComp(selectedDAUComp)) {
          continue;
        }

        RoundStats roundScores = tipperEntry.value;
        int totalScore = roundScores.aflScore + roundScores.nrlScore;

        if (maxRoundScores[roundNumber] == null ||
            totalScore > maxRoundScores[roundNumber]!) {
          maxRoundScores[roundNumber] = totalScore;
        }
      }
    }

    // Identify the round winners
    for (var roundEntry in _allTipperRoundStats.entries) {
      int roundNumber = roundEntry.key;
      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      for (var tipperEntry in tipperStats.entries) {
        Tipper tipper = tipperEntry.key;

        // only include tippers who's paid status matches that of the authenticated tipper
        if (_isScoringPaidComp != tipper.paidForComp(selectedDAUComp)) {
          continue;
        }
        RoundStats roundScores = tipperEntry.value;
        int totalScore = roundScores.aflScore + roundScores.nrlScore;

        if (totalScore == maxRoundScores[roundNumber]! &&
            (roundScores.nrlMaxScore + roundScores.aflMaxScore > 0)) {
          roundWinners[roundNumber] ??= [];
          roundWinners[roundNumber]!.add(RoundWinnerEntry(
            roundNumber: roundScores.roundNumber,
            tipper: tipper,
            total: totalScore,
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

  void _updateLeaderboardForComp() {
    // Create a map to accumulate scores for each tipper
    Map<Tipper, LeaderboardEntry> leaderboardMap = {};

    // Iterate over each round
    for (var roundEntry in _allTipperRoundStats.entries) {
      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      // Iterate over each tipper's stats for the round
      for (var tipperEntry in tipperStats.entries) {
        Tipper tipper = tipperEntry.key;
        RoundStats roundScores = tipperEntry.value;

        // only include tippers who's paid status matches that of the authenticated tipper
        if (_isScoringPaidComp != tipper.paidForComp(selectedDAUComp)) {
          continue;
        }

        // Initialize leaderboard entry if not already present
        if (!leaderboardMap.containsKey(tipper)) {
          leaderboardMap[tipper] = LeaderboardEntry(
            rank: 0, // to be replaced later with actual rank calculation
            tipper: tipper,
            total: 0,
            nRL: 0,
            aFL: 0,
            numRoundsWon:
                0, // to be replaced later with actual numRoundsWon calculation
            aflMargins: 0,
            aflUPS: 0,
            nrlMargins: 0,
            nrlUPS: 0,
          );
        }

        // Update leaderboard entry with round scores
        leaderboardMap[tipper]!.total +=
            roundScores.aflScore + roundScores.nrlScore;
        leaderboardMap[tipper]!.nRL += roundScores.nrlScore;
        leaderboardMap[tipper]!.aFL += roundScores.aflScore;
        leaderboardMap[tipper]!.aflMargins += roundScores.aflMarginTips;
        leaderboardMap[tipper]!.aflUPS += roundScores.aflMarginUPS;
        leaderboardMap[tipper]!.nrlMargins += roundScores.nrlMarginTips;
        leaderboardMap[tipper]!.nrlUPS += roundScores.nrlMarginUPS;
      }
    }

    // Convert the map to a list and sort by total score
    var leaderboard = leaderboardMap.values.toList();
    leaderboard.sort((a, b) => b.total.compareTo(a.total));

    // Assign ranks
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

    // Sort by rank and then by tipper name
    leaderboard.sort((a, b) {
      int rankComparison = a.rank.compareTo(b.rank);
      if (rankComparison == 0) {
        return (a.tipper.name?.toLowerCase() ?? '')
            .compareTo(b.tipper.name?.toLowerCase() ?? '');
      } else {
        return rankComparison;
      }
    });

    _leaderboard = leaderboard;

    notifyListeners();
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
          ? (a.value[0].tipper.name ?? '')
              .toLowerCase()
              .compareTo(b.value[0].tipper.name?.toLowerCase() ?? '')
          : (b.value[0].tipper.name ?? '')
              .toLowerCase()
              .compareTo(a.value[0].tipper.name?.toLowerCase() ?? ''));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  void sortRoundWinnersByTotal(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) => ascending
          ? a.value[0].total.compareTo(b.value[0].total)
          : b.value[0].total.compareTo(a.value[0].total));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  List<RoundStats> getTipperRoundScoresForComp(Tipper tipper) {
    if (!_initialRoundLoadCompleted.isCompleted) {
      return [];
    }

    List<RoundStats> tipperRoundScores = [];
    for (var round in _allTipperRoundStats.entries) {
      if (round.value.containsKey(tipper)) {
        tipperRoundScores.add(round.value[tipper]!);
      }
    }

    return tipperRoundScores;
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

    di<StatsViewModel>()._writeLiveScoreToDb(game);
  }

  Future<void> _writeLiveScoreToDb(Game game) async {
    if (!_gamesWithLiveScores.contains(game)) {
      _gamesWithLiveScores.add(game);
    }

    Map<String, Map<String, dynamic>> liveScores = {};
    // Create a copy of the list for safe iteration
    var gamesCopy = List<Game>.from(_gamesWithLiveScores);
    for (var game in gamesCopy) {
      liveScores[game.dbkey] = game.scoring!.toJson();

      await _db
          .child(statsPathRoot)
          .child(selectedDAUComp.dbkey!)
          .child(liveScoresRoot)
          .update(liveScores);
      log('Wrote live score to DB for game ${game.dbkey}');
    }
  }

  // method to delete any live scores for games that have a gamestate of startedResultKnown
  Future<void> _deleteStaleLiveScores() async {
    List<Game> gamesToDelete = [];
    for (var game in _gamesWithLiveScores) {
      if (game.gameState == GameState.startedResultKnown) {
        gamesToDelete.add(game);
      }
    }

    // if there are any games to delete turn off the listener
    if (gamesToDelete.isNotEmpty) {
      _liveScoresStream.cancel();
    }

    for (var game in gamesToDelete) {
      _gamesWithLiveScores.remove(game);

      await _db
          .child(statsPathRoot)
          .child(selectedDAUComp.dbkey!)
          .child(liveScoresRoot)
          .child(game.dbkey)
          .remove();
      log('Deleted live scores for game ${game.dbkey}');
    }

    // if we turned the lisnter off, turn it back on
    if (gamesToDelete.isNotEmpty) {
      _liveScoresStream = _db
          .child('$statsPathRoot/${selectedDAUComp.dbkey}/$liveScoresRoot')
          .onValue
          .listen(_handleEventLiveScores, onError: (error) {
        log('Error listening to live scores: $error');
      });
    }
  }

  List<DAURound> _getRoundsToUpdate(
      DAURound? onlyUpdateThisRound, DAUComp daucompToUpdate) {
    // grab all rounds where the round state is allGamesEnded
    List<DAURound> roundsToUpdate = daucompToUpdate.daurounds;
    if (onlyUpdateThisRound != null) {
      roundsToUpdate = [onlyUpdateThisRound];
    }
    log('Rounds to update: ${roundsToUpdate.length}');
    return roundsToUpdate;
  }

  Future<RoundStats> _calculateRoundStatsForTipper(Tipper tipperToScore,
      DAURound dauRound, TipsViewModel allTipsViewModel) async {
    RoundStats proposedRoundScores = RoundStats(
      roundNumber: dauRound.dAUroundNumber,
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

    for (var game in dauRound.games) {
      Tip? tip = await allTipsViewModel.findTip(game, tipperToScore);

      if (tip == null) {
        continue;
      }

      // count margin tips regardless of round state

      int marginTip =
          (tip.tip == GameResult.a || tip.tip == GameResult.e) ? 1 : 0;

      if (tip.game.league == League.afl) {
        proposedRoundScores.aflMarginTips += marginTip;
      } else {
        proposedRoundScores.nrlMarginTips += marginTip;
      }

      if (tip.game.gameState != GameState.notStarted &&
          tip.game.gameState != GameState.startingSoon) {
        int score = tip.getTipScoreCalculated();
        int maxScore = tip.getMaxScoreCalculated();

        if (game.league == League.afl) {
          proposedRoundScores.aflScore += score;
          proposedRoundScores.aflMaxScore += maxScore;
        } else {
          proposedRoundScores.nrlScore += score;
          proposedRoundScores.nrlMaxScore += maxScore;
        }

        int marginUPS = 0;
        if (tip.game.scoring != null) {
          marginUPS = (tip.game.scoring!.getGameResultCalculated(game.league) ==
                          GameResult.a &&
                      tip.tip == GameResult.a) ||
                  (tip.game.scoring!.getGameResultCalculated(game.league) ==
                          GameResult.e &&
                      tip.tip == GameResult.e)
              ? 1
              : 0;

          if (tip.game.league == League.afl) {
            proposedRoundScores.aflMarginUPS += marginUPS;
          } else {
            proposedRoundScores.nrlMarginUPS += marginUPS;
          }
        }
      }
    }

    return proposedRoundScores;
  }

  Future<Map<Tipper, RoundStats>> _calculateRoundStats(List<Tipper> tippers,
      DAURound dauRound, TipsViewModel allTipsViewModel) async {
    Map<Tipper, RoundStats> roundScores = {};

    for (var tipper in tippers) {
      RoundStats proposedRoundScores = await _calculateRoundStatsForTipper(
          tipper, dauRound, allTipsViewModel);

      roundScores[tipper] = proposedRoundScores;
    }

    return roundScores;
  }

  Future<void> _rankTippers() async {
    if (_allTipperRoundStats.isEmpty) {
      return;
    }

    // get a list of all tippers
    List<Tipper> tippers = await di<TippersViewModel>().getAllTippers();

    // log how many tippers we are ranking
    log('Ranking ${tippers.length} tippers for comp: ${selectedDAUComp.dbkey}');

    for (var roundIndex = 0;
        roundIndex < selectedDAUComp.daurounds.length;
        roundIndex++) {
      List<MapEntry<Tipper, int>> roundScores = [];

      for (var tipper in tippers) {
        if (_isScoringPaidComp != tipper.paidForComp(selectedDAUComp)) {
          continue;
        }
        if (_allTipperRoundStats[roundIndex] == null ||
            _allTipperRoundStats[roundIndex]![tipper] == null) {
          //log('No scores for tipper ${tipper.name} in round ${roundIndex + 1}');
          continue;
        }
        roundScores.add(MapEntry(
            tipper,
            _allTipperRoundStats[roundIndex]![tipper]!.aflScore +
                _allTipperRoundStats[roundIndex]![tipper]!.nrlScore));
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
        _allTipperRoundStats[roundIndex]![entry.key]!.rank = rank;

        if (roundIndex > 0) {
          if (_allTipperRoundStats[roundIndex - 1] == null ||
              _allTipperRoundStats[roundIndex - 1]![entry.key] == null) {
            //log('No scores for tipper ${entry.key.name} in round $roundIndex');
            continue;
          }
          int? lastRank =
              _allTipperRoundStats[roundIndex - 1]![entry.key]!.rank;
          int? changeInRank = lastRank - rank;
          _allTipperRoundStats[roundIndex]![entry.key]!.rankChange =
              changeInRank;
        }
        lastScore = entry.value;
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _allRoundScoresStream.cancel();
    _liveScoresStream.cancel();
    super.dispose();
  }
}
