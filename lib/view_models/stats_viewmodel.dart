import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/scoring_gamestats.dart';
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
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

// Define constants for Firestore database locations
const statsPathRoot = '/Stats';
const roundStatsRoot = 'round_stats';
const liveScoresRoot = 'live_scores';
const gameStatsRoot = 'game_stats';

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

  GamesViewModel? gamesViewModel;

  bool _isSelectedTipperPaidUpMember = false;

  // Constructor
  StatsViewModel(this.selectedDAUComp, this.gamesViewModel) {
    log('StatsViewModel(ALL TIPPERS) for comp: ${selectedDAUComp.dbkey}');
    _listenToScores();

    // segregate tippers based on if they are paid members for the active comp
    // if the selected tipper is not a paid tipper, then score them with
    // all other non-paid tippers
    // otherwise score them will all other paid members
    assert(di<TippersViewModel>().selectedTipper != null);

    _isSelectedTipperPaidUpMember =
        di<TippersViewModel>().selectedTipper!.paidForComp(selectedDAUComp);
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
        log('StatsViewModel._handleEventRoundScores() Loaded round scores for ${_allTipperRoundStats.length} rounds');
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
        log('StatsViewModel.updateLeaderAndRoundAndRank() Calculating not in progress, updating leaderboard and round winners');
        _isUpdatingLeaderAndRoundAndRank = true;
      }

      // update the leaderboard
      _updateLeaderboardForComp();
      // Update the round winners
      _updateRoundWinners();
      // rank the tippers
      await _rankTippersPerRound();

      notifyListeners();
    } catch (e) {
      log('StatsViewModel.updateLeaderAndRoundAndRank() Error updating leaderboard and round winners: $e');
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

          log('StatsViewModel._handleEventLiveScores() Loaded live score for game ${game.dbkey}');
        }

        notifyListeners();
      }
    } catch (e) {
      log('StatsViewModel._handleEventLiveScores() Error listening to /Stats/live_scores: $e');
      rethrow;
    } finally {
      if (!_initialLiveScoreLoadCompleter.isCompleted) {
        _initialLiveScoreLoadCompleter.complete();
      }
    }
  }

  Future<String> updateStats(DAUComp daucompToUpdate,
      DAURound? onlyUpdateThisRound, Tipper? onlyUpdateThisTipper) async {
    log('StatsViewModel.updateStats() called for comp: ${daucompToUpdate.name}');
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

      // grab all tips
      TipsViewModel allTipsViewModel = TipsViewModel(
          di<TippersViewModel>(), daucompToUpdate, gamesViewModel!);

      // set the initial list of tippers to update
      List<Tipper> tippersToUpdate = [];
      if (onlyUpdateThisTipper != null) {
        tippersToUpdate = [onlyUpdateThisTipper];
        log('StatsViewModel.updateStats() Only updating stats for tipper ${onlyUpdateThisTipper.name}');
      } else {
        List<Tipper> allTippers = await di<TippersViewModel>().getAllTippers();
        // preserve the oriignal list of tippers, take a copy
        tippersToUpdate = List.from(allTippers);
        log('StatsViewModel.updateStats() Updating stats for all ${tippersToUpdate.length} tippers');
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

        // percentage tipped stats are expensive to calculate, so only do it for the specific round
        //await _writeGameResultPercentageTipped(
        //    dauRoundsEdited, allTipsViewModel, daucompToUpdate);
      }

      String res =
          'Completed scoring updates for ${tippersToUpdate.length} tippers and ${dauRoundsEdited.length} rounds.';
      log('StatsViewModel.updateStats() $res');

      _deleteStaleLiveScores();

      return res;
    } catch (e) {
      log('StatsViewModel.updateStats() Error updating scoring: $e');
      rethrow;
    } finally {
      stopwatch.stop();
      log('StatsViewModel.updateStats() executed in ${stopwatch.elapsed}');
      _isCalculating = false;
      notifyListeners();
    }
  }

  Future<void> _writeGameResultPercentageTipped(List<DAURound> dauRoundsEdited,
      TipsViewModel allTipsViewModel, DAUComp daucompToUpdate) async {
    // write percent each gameresult was tipped for each game
    for (DAURound dauRound in dauRoundsEdited) {
      // Loop through each game in the round
      List<Game> gamesForRound =
          await gamesViewModel!.getGamesForRound(dauRound);
      for (Game game in gamesForRound) {
        GameStatsEntry gameStatsEntry = GameStatsEntry();
        // Loop through the gameresult enum
        for (GameResult gameResult in GameResult.values) {
          double percentTipped = await allTipsViewModel
              .percentageOfTippersTipped(gameResult, game);

          // switch based on enum, update the correct field in the GameStatsEntry
          switch (gameResult) {
            case GameResult.a:
              gameStatsEntry.percentageTippedHomeMargin = percentTipped;
              break;
            case GameResult.b:
              gameStatsEntry.percentageTippedHome = percentTipped;
              break;
            case GameResult.c:
              gameStatsEntry.percentageTippedDraw = percentTipped;
              break;
            case GameResult.d:
              gameStatsEntry.percentageTippedAway = percentTipped;
              break;
            case GameResult.e:
              gameStatsEntry.percentageTippedAwayMargin = percentTipped;
              break;
            default:
              break;
          }
        }
        // save the results to /Stats/{comp}/game_stats/{game key}
        // only update if something has changed
        String subKey = _isSelectedTipperPaidUpMember ? 'paid' : 'free';
        if (gameStatsEntry != game.gameStats) {
          await _db
              .child(statsPathRoot)
              .child(daucompToUpdate.dbkey!)
              .child(gameStatsRoot)
              .child(subKey)
              .child(game.dbkey)
              .set(gameStatsEntry.toJson());
          log('StatsViewModel._writeGameResultPercentageTipped() Wrote game stats for game $subKey/${game.dbkey}');
        } else {
          log('StatsViewModel._writeGameResultPercentageTipped() No change in game stats for game $subKey/${game.dbkey}');
        }
      }
    }
  }

  Future<void> _writeAllRoundScoresToDb(
      Map<int, Map<Tipper, RoundStats>> updatedTipperRoundStats,
      DAUComp dauComp) async {
    log('StatsViewModel._writeAllRoundScoresToDb() Writing all round scores to DB for ${updatedTipperRoundStats.length} rounds');

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
    log('StatsViewModel._writeSpecificRoundScoresToDb() round ${roundIndex + 1}');

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

  void _updateRoundWinners() {
    Map<int, List<RoundWinnerEntry>> roundWinners = {};
    Map<int, int> maxRoundScores = {};

    // Iterate over each round
    for (var roundEntry in _allTipperRoundStats.entries) {
      int roundNumber = roundEntry.key;

      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      // Find the maximum score for the round
      for (var tipperEntry in tipperStats.entries) {
        // only include stats from tippers who's paid status matches that of the selected tipper
        // for example if the authenticated tipper is a paid member, only include other paid members for stats
        if (_isSelectedTipperPaidUpMember !=
            tipperEntry.key.paidForComp(selectedDAUComp)) {
          // dont include, skip to the next tipper
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
      // skip rounds in stats data that exceed the max round number - these are likely finals rounds
      if (roundNumber + 1 >
          (di<DAUCompsViewModel>().selectedDAUComp?.daurounds.length ?? 0)) {
        continue;
      }
      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      for (var tipperEntry in tipperStats.entries) {
        Tipper tipper = tipperEntry.key;

        // only include tippers who's paid status matches that of the selected tipper
        if (_isSelectedTipperPaidUpMember !=
            tipper.paidForComp(selectedDAUComp)) {
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
      int roundIndex = roundEntry.key;

      // skip rounds in stats data that exceed the max round number - these are likely finals rounds
      if (roundIndex + 1 >
          (di<DAUCompsViewModel>().selectedDAUComp?.daurounds.length ?? 0)) {
        continue;
      }
      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      // Iterate over each tipper's stats for the round
      for (var tipperEntry in tipperStats.entries) {
        Tipper tipper = tipperEntry.key;
        RoundStats roundScores = tipperEntry.value;

        // only include tippers who's paid status matches that of the authenticated tipper
        if (_isSelectedTipperPaidUpMember !=
            tipper.paidForComp(selectedDAUComp)) {
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
      int roundNumber = round.key;

      // skip rounds in stats data that exceed the max round number - these are likely finals rounds
      if (roundNumber + 1 >
          (di<DAUCompsViewModel>().selectedDAUComp?.daurounds.length ?? 0)) {
        continue;
      }
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
      log('StatsViewModel._writeLiveScoreToDb() Wrote live score to DB for game ${game.dbkey}');
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
      log('StatsViewModel._deleteStaleLiveScores() Deleted live scores for game ${game.dbkey}');
    }

    // if we turned the lisnter off, turn it back on
    if (gamesToDelete.isNotEmpty) {
      _liveScoresStream = _db
          .child('$statsPathRoot/${selectedDAUComp.dbkey}/$liveScoresRoot')
          .onValue
          .listen(_handleEventLiveScores, onError: (error) {
        log('StatsViewModel._deleteStaleLiveScores() Error listening to live scores: $error');
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
    log('StatsViewModel._getRoundsToUpdate() Updating stats for ${roundsToUpdate.length} rounds.');
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

  Future<void> _rankTippersPerRound() async {
    if (_allTipperRoundStats.isEmpty) {
      return;
    }

    // get a list of all tippers
    List<Tipper> tippers = await di<TippersViewModel>().getAllTippers();

    // Iterate over each round in stats
    for (var roundEntry in _allTipperRoundStats.entries) {
      int roundIndex = roundEntry.key;

      // skip rounds in stats data that exceed the max round number - these are likely finals rounds
      if (roundIndex + 1 >
          (di<DAUCompsViewModel>().selectedDAUComp?.daurounds.length ?? 0)) {
        continue;
      }

      List<MapEntry<Tipper, int>> roundScores = [];

      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      // Iterate over each tipper's stats for the round
      for (var tipperEntry in tipperStats.entries) {
        Tipper tipper = tipperEntry.key;

        if (_isSelectedTipperPaidUpMember !=
            tipper.paidForComp(selectedDAUComp)) {
          continue;
        }
        if (_allTipperRoundStats[roundIndex] == null ||
            _allTipperRoundStats[roundIndex]![tipper] == null) {
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
