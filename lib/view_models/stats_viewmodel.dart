import 'dart:async';
import 'dart:developer';
import 'dart:io'; // Add this import for IOException, SocketException
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
import 'package:synchronized/synchronized.dart';

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

  bool _isUpdateScoringRunning = false;
  bool get isUpdateScoringRunning => _isUpdateScoringRunning;

  final Completer<void> _initialLiveScoreLoadCompleter = Completer();
  Future<void> get initialLiveScoreLoadComplete =>
      _initialLiveScoreLoadCompleter.future;

  final Completer<void> _initialRoundScoresLoadCompleted = Completer();
  Future<void> get initialRoundScoresComplete =>
      _initialRoundScoresLoadCompleted.future;

  List<LeaderboardEntry> _compLeaderboard = [];
  List<LeaderboardEntry> get compLeaderboard => _compLeaderboard;

  Map<int, List<RoundWinnerEntry>> _roundWinners = {};
  Map<int, List<RoundWinnerEntry>> get roundWinners => _roundWinners;

  GamesViewModel? gamesViewModel;

  bool? _isSelectedTipperPaidUpMember;
  bool get isSelectedTipperPaidUpMember => _isSelectedTipperPaidUpMember!;

  TipsViewModel? allTipsViewModel;
  TipsViewModel? selectedTipperTipsViewModel;

  // Constructor
  StatsViewModel(this.selectedDAUComp, this.gamesViewModel) {
    log('StatsViewModel(ALL TIPPERS) for comp: ${selectedDAUComp.dbkey}');
    _initialize();
  }

  void _initialize() async {
    // make sure the tippers viewmodel is initialized
    await di<TippersViewModel>().initialLoadComplete;

    // add a listener for the tipper viewmodel, do a re-calculation of the leaderboards
    // if the tippers change

    di<TippersViewModel>().addListener(_updateLeaderAndRoundAndRank);

    _listenToScores();
  }

  Future<void> _listenToScores() async {
    _allRoundScoresStream = _db
        .child('$statsPathRoot/${selectedDAUComp.dbkey}/$roundStatsRoot')
        .onValue
        .listen(_handleEventRoundScores, onError: (error) {
      log('StatsViewModel() Error listening to round scores: $error');
    });

    _liveScoresStream = _db
        .child('$statsPathRoot/${selectedDAUComp.dbkey}/$liveScoresRoot')
        .onValue
        .listen(_handleEventLiveScores, onError: (error) {
      log('StatsViewModel() Error listening to live scores: $error');
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

          // Collect all futures
          List<Future<void>> futures = [];
          for (var entry in roundScoresJson.entries) {
            futures.add(
                di<TippersViewModel>().findTipper(entry.key).then((tipper) {
              var roundStats = RoundStats.fromJson(Map<String, dynamic>.from(
                  entry.value as Map<dynamic, dynamic>));
              if (tipper != null) {
                roundScores[tipper] = roundStats;
              } else {
                log('StatsViewModel() Tipper ${entry.key} not found in _handleEventRoundScores');
              }
            }));
          }

          // Wait for all futures to complete
          await Future.wait(futures);

          _allTipperRoundStats[roundIndex] = roundScores;
        }

        log('StatsViewModel._handleEventRoundScores() Loaded round scores for ${_allTipperRoundStats.length} rounds');
      } else {
        log('StatsViewModel._handleEventRoundScores() Snapshot ${event.snapshot.ref.path} does not exist in _handleEventRoundScores');
      }

      if (!_initialRoundScoresLoadCompleted.isCompleted) {
        _initialRoundScoresLoadCompleted.complete();
      }

      // Update the leaderboard
      await _updateLeaderAndRoundAndRank();
    } catch (e, stackTrace) {
      log('Error listening to /$statsPathRoot/round_scores: $e');
      _allTipperRoundStats.clear(); // Rollback partial updates
      if (!_initialRoundScoresLoadCompleted.isCompleted) {
        _initialRoundScoresLoadCompleted.completeError(e, stackTrace);
      }
      rethrow; // Re-throw the error
    }
  }

  Completer<void>? _updateLock;

  Future<void> _updateLeaderAndRoundAndRank() async {
    if (_updateLock != null) {
      log('StatsViewModel()._updateLeaderAndRoundAndRank() Update already in progress, skipping');
      return;
    }

    _updateLock = Completer<void>();

    try {
      await di<TippersViewModel>().isUserLinked;

      log('StatsViewModel()._updateLeaderAndRoundAndRank() Updating leaderboard and round winners');

      _isSelectedTipperPaidUpMember =
          di<TippersViewModel>().selectedTipper.paidForComp(selectedDAUComp);

      log('StatsViewModel()._updateLeaderAndRoundAndRank() Tipper ${di<TippersViewModel>().selectedTipper.name} paid status is $_isSelectedTipperPaidUpMember');

      _updateLeaderboardForComp();
      _updateRoundWinners();
      _rankTippersPerRound();

      notifyListeners();
    } catch (e) {
      log('Error: $e');
      rethrow;
    } finally {
      _updateLock?.complete();
      _updateLock = null;
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
      log('StatsViewModel._handleEventLiveScores() Error listening to /$statsPathRoot/live_scores: $e');
      rethrow;
    } finally {
      if (!_initialLiveScoreLoadCompleter.isCompleted) {
        _initialLiveScoreLoadCompleter.complete();
      }
    }
  }

//  These are the various triggers that can cause an update of the stats for a comp.
// +--------------------------------------+-------------------------------+-------------------------+-----------------------------------------------------------------------------------+
// | Trigger                              | Rounds Rescored               | Tippers Rescored        | Description                                                                       |
// +--------------------------------------+-------------------------------+-------------------------+-----------------------------------------------------------------------------------+
// | Admin clicks [Rescore] in UI         | All                           | All                     | Full rescore. Updates all rounds for all tippers.                                |
// | User places a tip                    | Only the round that tip is for| Tipper who placed tip   | Partial rescore. Updates margin counts for that user and that round.             |
// | Fixture download has new scores      | Only the round with changes   | All                     | Partial rescore. Scoring updates for all tippers for the current round.          |
// | User enters a live score             | Only the round with changes   | All                     | Partial rescore. Scoring updates for all tippers for the current round.          |
// +--------------------------------------+-------------------------------+-------------------------+-----------------------------------------------------------------------------------+

  Future<String>? _updateStatsInProgress;

  Future<String> updateStats(
    DAUComp daucompToUpdate,
    DAURound? onlyUpdateThisRound,
    Tipper? onlyUpdateThisTipper,
  ) {
    if (_updateStatsInProgress != null) {
      log('StatsViewModel.updateStats() Update already in progress, skipping');
      _logEventScoringInitiated('scoring_skipped', daucompToUpdate,
          onlyUpdateThisRound, onlyUpdateThisTipper);
      return Future.value('Skipped: Another stats update already in progress.');
    }

    final completer = Completer<String>();
    _updateStatsInProgress = completer.future;

    (() async {
      log('StatsViewModel.updateStats() called for comp: ${daucompToUpdate.name}');
      var stopwatch = Stopwatch()..start();

      try {
        if (!_initialRoundScoresLoadCompleted.isCompleted) {
          try {
            await _initialRoundScoresLoadCompleted.future;
          } catch (e) {
            log('StatsViewModel.updateStats() Error waiting for initial round load: $e');
            _allTipperRoundStats.clear(); // reset
          }
        }

        _isUpdateScoringRunning = true;

        _logEventScoringInitiated('scoring_initiated', daucompToUpdate,
            onlyUpdateThisRound, onlyUpdateThisTipper);

        /// make sure we have all tippers
        await di<TippersViewModel>().initialLoadComplete;

        // Set the tippers to update
        List<Tipper> tippersToUpdate = onlyUpdateThisTipper != null
            ? [onlyUpdateThisTipper]
            : List.from(di<TippersViewModel>().tippers);

        log('StatsViewModel.updateStats() Updating stats for ${tippersToUpdate.length} tippers');

        // Prep tips
        if (onlyUpdateThisTipper == null) {
          allTipsViewModel ??= TipsViewModel(
              di<TippersViewModel>(), daucompToUpdate, gamesViewModel!);

          List<Tipper> tippersToRemove = [];
          await Future.wait(tippersToUpdate.map((tipper) async {
            bool hasSubmitted =
                await allTipsViewModel!.hasSubmittedTips(tipper);
            if (!hasSubmitted) {
              tippersToRemove.add(tipper);
              log('Tipper ${tipper.name} did not submit tips. Removing.');
            }
          }));

          tippersToUpdate
              .removeWhere((tipper) => tippersToRemove.contains(tipper));
        } else {
          selectedTipperTipsViewModel ??=
              di<DAUCompsViewModel>().selectedTipperTipsViewModel;

          await selectedTipperTipsViewModel!.initialLoadCompleted;
        }

        var dauRoundsEdited =
            _getRoundsToUpdate(onlyUpdateThisRound, daucompToUpdate);

        for (DAURound dauRound in dauRoundsEdited) {
          if (onlyUpdateThisTipper == null) {
            await _calculateRoundStats(
                tippersToUpdate, dauRound, allTipsViewModel!);
          } else {
            await _calculateRoundStatsForTipper(
                onlyUpdateThisTipper, dauRound, selectedTipperTipsViewModel!);
          }
        }

        await _writeAllRoundScoresToDb(_allTipperRoundStats, daucompToUpdate);

        String res =
            'Completed updates for ${tippersToUpdate.length} tippers and ${dauRoundsEdited.length} rounds.';
        log('StatsViewModel.updateStats() $res');

        await _deleteStaleLiveScores();

        completer.complete(res);
      } catch (e) {
        log('StatsViewModel.updateStats() Error: $e');
        completer.completeError(e);
      } finally {
        _logEventScoringInitiated('scoring_completed', daucompToUpdate,
            onlyUpdateThisRound, onlyUpdateThisTipper);
        _isUpdateScoringRunning = false;
        _updateStatsInProgress = null;
        stopwatch.stop();
        log('StatsViewModel.updateStats() completed in ${stopwatch.elapsed}');
      }
    })();

    return _updateStatsInProgress!;
  }

  void _logEventScoringInitiated(String msg, DAUComp daucompToUpdate,
      DAURound? onlyUpdateThisRound, Tipper? onlyUpdateThisTipper) {
    try {
      // write a firebase analytic event that scoring is underway
      FirebaseAnalytics.instance.logEvent(name: msg, parameters: {
        'comp': daucompToUpdate.name,
        'round': onlyUpdateThisRound?.dAUroundNumber ?? 'all',
        'tipper': onlyUpdateThisTipper?.name ?? 'all',
        'withTransaction': 'true',
      });
    } catch (e) {
      log('_logEventScoringInitiated() Error writing log event that scoring has initiated: $e');
      return;
    }
  }

  Map<Tipper, RoundStats> getRoundLeaderBoard(int roundNumber) {
    if (_allTipperRoundStats.isEmpty) {
      return {};
    }

    // only include tippers who's paid status matches that of the authenticated tipper
    Map<Tipper, RoundStats> roundLeaderboard = {};
    assert(roundNumber != -1);
    for (var tipperEntry in _allTipperRoundStats[roundNumber - 1]!.entries) {
      if (_isSelectedTipperPaidUpMember !=
          tipperEntry.key.paidForComp(selectedDAUComp)) {
        continue;
      }
      roundLeaderboard[tipperEntry.key] = tipperEntry.value;
    }

    return roundLeaderboard;
  }

  final Map<Game, GameStatsEntry> gamesStatsEntry = {};

  void getGamesStatsEntry(Game game, bool forceUpdate) async {
    //log('StatsViewModel.getGamesStatsEntry() START for game ${game.dbkey} - gamesStatsEntry: ${gamesStatsEntry[game]}');
    // get any existing games stats entry from db first
    gamesStatsEntry[game] = await _getGameStatsEntry(game);

    // if its not null and not forcing update then return what we have
    if (gamesStatsEntry[game]?.averageScore != null && !forceUpdate) {
      notifyListeners();
      //log('StatsViewModel.getGamesStatsEntry() END (use cache) for game ${game.dbkey} - gamesStatsEntry: ${gamesStatsEntry[game]}');
      return;
    }

    // otherwise prep tips model to load all tips to do the calculation - note this is an expensive operation
    allTipsViewModel ??=
        TipsViewModel(di<TippersViewModel>(), selectedDAUComp, gamesViewModel!);

    // await for the tips model to load
    await allTipsViewModel!.initialLoadCompleted;

    // initialise or update the game stats entry
    await _updateGameResultPercentageTipped(
        game, allTipsViewModel!, selectedDAUComp);

    notifyListeners();
    //log('StatsViewModel.getGamesStatsEntry() END for game ${game.dbkey} - gamesStatsEntry: ${gamesStatsEntry[game]}');
  }

  Future<void> _updateGameResultPercentageTipped(Game gameToCalculateFor,
      TipsViewModel allTipsViewModel, DAUComp daucompToUpdate) async {
    gamesStatsEntry[gameToCalculateFor] =
        await allTipsViewModel.percentageOfTippersTipped(gameToCalculateFor);

    await _updateGameStatsIfChanged(gameToCalculateFor,
        gamesStatsEntry[gameToCalculateFor]!, daucompToUpdate);
  }

  Future<void> _updateGameStatsIfChanged(
      Game game, GameStatsEntry gameStatsEntry, DAUComp daucompToUpdate) async {
    assert(_isSelectedTipperPaidUpMember != null);

    String subKey = _isSelectedTipperPaidUpMember! ? 'paid' : 'free';

    log('Updating game stats for game: ${game.dbkey}');
    log('Calculated gameStatsEntry: ${gameStatsEntry.toJson()}');
    log('Existing game.gameStats: ${game.gameStats?.toJson()}');

    // Use a transaction to ensure atomic updates
    final gameStatsRef = _db
        .child(statsPathRoot)
        .child(daucompToUpdate.dbkey!)
        .child(gameStatsRoot)
        .child(subKey)
        .child(game.dbkey);

    await gameStatsRef.runTransaction((currentData) {
      if (currentData != null) {
        // Merge the new data with the existing data if needed
        final existingStats = GameStatsEntry.fromJson(
            Map<String, dynamic>.from(currentData as Map));
        if (existingStats == gameStatsEntry) {
          log('No changes detected in game stats for game: ${game.dbkey}');
          return Transaction.abort(); // Abort the transaction if no changes
        }
      }

      log('Writing updated game stats for game: ${game.dbkey}');
      return Transaction.success(gameStatsEntry.toJson());
    }).then((result) {
      if (result.committed) {
        log('Game stats successfully written to DB for game: ${game.dbkey}');
      } else {
        log('Transaction aborted: No changes made to game stats for game: ${game.dbkey}');
      }
    }).catchError((error) {
      log('Error during transaction for game stats: $error');
    });
  }

  Future<GameStatsEntry> _getGameStatsEntry(Game game) async {
    await di<TippersViewModel>().isUserLinked;

    _isSelectedTipperPaidUpMember =
        di<TippersViewModel>().selectedTipper.paidForComp(selectedDAUComp);

    String subKey = _isSelectedTipperPaidUpMember! ? 'paid' : 'free';
    var snapshot = await _db
        .child(statsPathRoot)
        .child(selectedDAUComp.dbkey!)
        .child(gameStatsRoot)
        .child(subKey)
        .child(game.dbkey)
        .get();

    if (snapshot.exists) {
      return GameStatsEntry.fromJson(
          Map<String, dynamic>.from(snapshot.value as Map));
    } else {
      return GameStatsEntry();
    }
  }

  // In _writeAllRoundScoresToDb, wrap the database operation in try-catch and handle network errors
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

    int retryCount = 0;
    const int maxRetries = 3;
    const Duration initialDelay = Duration(seconds: 2);

    while (true) {
      try {
        await _db
            .child(statsPathRoot)
            .child(dauComp.dbkey!)
            .child(roundStatsRoot)
            .runTransaction((currentData) {
          // Merge the new data with the existing data
          if (currentData != null) {
            final existingData = currentData is Map
                ? Map<String, dynamic>.from(currentData)
                : <String, dynamic>{};
            updatedTipperRoundStatsJson.forEach((key, value) {
              existingData[key] = value;
            });
            return Transaction.success(existingData); // Return the merged data
          } else {
            return Transaction.success(
                updatedTipperRoundStatsJson); // Return the new data
          }
        });
        break; // Success, exit the loop
      } on SocketException catch (e) {
        log('Network error (SocketException) while writing round scores: $e');
        if (retryCount < maxRetries) {
          retryCount++;
          final delay = initialDelay * retryCount;
          log('Retrying in ${delay.inSeconds} seconds... (attempt $retryCount/$maxRetries)');
          await Future.delayed(delay);
          continue;
        } else {
          rethrow;
        }
      } on IOException catch (e) {
        log('Network error (IOException) while writing round scores: $e');
        if (retryCount < maxRetries) {
          retryCount++;
          final delay = initialDelay * retryCount;
          log('Retrying in ${delay.inSeconds} seconds... (attempt $retryCount/$maxRetries)');
          await Future.delayed(delay);
          continue;
        } else {
          rethrow;
        }
      } catch (e) {
        log('Unexpected error while writing round scores: $e');
        rethrow;
      }
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

          if (_compLeaderboard.isNotEmpty) {
            var leaderboardEntry = _compLeaderboard
                .firstWhere((element) => element.tipper == tipper);
            leaderboardEntry.numRoundsWon++;
          }
        }
      }
    }

    _roundWinners = roundWinners;
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
        return (a.tipper.name.toLowerCase())
            .compareTo(b.tipper.name.toLowerCase());
      } else {
        return rankComparison;
      }
    });

    _compLeaderboard = leaderboard;
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
          ? (a.value[0].tipper.name)
              .toLowerCase()
              .compareTo(b.value[0].tipper.name.toLowerCase())
          : (b.value[0].tipper.name)
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

  List<RoundStats> getTipperRoundScoresForComp(Tipper tipper) {
    if (!_initialRoundScoresLoadCompleted.isCompleted) {
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

  Future<void> _addLiveScore(
      Game game, CrowdSourcedScore croudSourcedScore) async {
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

    await di<StatsViewModel>()._writeLiveScoreToDb(game);
  }

  final Lock _submitLock = Lock();

  Future<void> submitLiveScores({
    required Tip tip,
    required String homeScore,
    required String awayScore,
    required String originalHomeScore,
    required String originalAwayScore,
    required DAUComp selectedDAUComp,
  }) async {
    await _submitLock.synchronized(() async {
      // Update home score if changed
      if (homeScore != originalHomeScore) {
        await _liveScoreUpdated(
            homeScore, ScoringTeam.home, selectedDAUComp, tip);
        if (awayScore == '0') {
          await _liveScoreUpdated(
              awayScore, ScoringTeam.away, selectedDAUComp, tip);
        }
      }
      // Update away score if changed
      if (awayScore != originalAwayScore) {
        await _liveScoreUpdated(
            awayScore, ScoringTeam.away, selectedDAUComp, tip);
        if (homeScore == '0') {
          await _liveScoreUpdated(
              homeScore, ScoringTeam.home, selectedDAUComp, tip);
        }
      }

      unawaited(
        updateStats(
          selectedDAUComp,
          tip.game.getDAURound(selectedDAUComp),
          null,
        ).then((_) {
          getGamesStatsEntry(tip.game, true);
        }),
      );
    });
  }

  // You may need to update _liveScoreUpdated to accept the Tip as a parameter.
  Future<void> _liveScoreUpdated(dynamic score, ScoringTeam scoreTeam,
      DAUComp selectedDAUComp, Tip tip) async {
    CrowdSourcedScore croudSourcedScore = CrowdSourcedScore(
        DateTime.now().toUtc(),
        scoreTeam,
        tip.tipper.dbkey!,
        int.tryParse(score)!,
        false);

    await _addLiveScore(tip.game, croudSourcedScore);
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

  Future<void> _calculateRoundStatsForTipper(Tipper tipperToScore,
      DAURound dauRound, TipsViewModel allTipsViewModel) async {
    // wait until we are initialized
    await _initialRoundScoresLoadCompleted.future;

    // initialize any round of tipper Maps as needed
    if (_allTipperRoundStats[dauRound.dAUroundNumber - 1] == null) {
      _allTipperRoundStats[dauRound.dAUroundNumber - 1] = {};
    }

    //reset all stats for the tipper
    _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore] =
        RoundStats(
            roundNumber: dauRound.dAUroundNumber,
            aflScore: 0,
            nrlScore: 0,
            aflMaxScore: 0,
            nrlMaxScore: 0,
            aflMarginTips: 0,
            nrlMarginTips: 0,
            aflMarginUPS: 0,
            nrlMarginUPS: 0,
            aflTipsOutstanding: 0,
            nrlTipsOutstanding: 0,
            rank: 0,
            rankChange: 0);

    assert(_allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore] !=
        null);

    for (var game in dauRound.games) {
      Tip? tip = await allTipsViewModel.findTip(game, tipperToScore);

      if (tip == null) {
        // keep track of tips outstanding
        if (game.league == League.afl) {
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]!
              .aflTipsOutstanding++;
        } else {
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]!
              .nrlTipsOutstanding++;
        }
        continue;
      }

      // count margin tips regardless of round state

      int marginTip =
          (tip.tip == GameResult.a || tip.tip == GameResult.e) ? 1 : 0;

      if (tip.game.league == League.afl) {
        _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]!
            .aflMarginTips += marginTip;
      } else {
        _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]!
            .nrlMarginTips += marginTip;
      }

      if (tip.game.gameState != GameState.notStarted &&
          tip.game.gameState != GameState.startingSoon) {
        int score = tip.getTipScoreCalculated();
        int maxScore = tip.getMaxScoreCalculated();

        if (game.league == League.afl) {
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
              ?.aflScore += score;
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
              ?.aflMaxScore += maxScore;
        } else {
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
              ?.nrlScore += score;
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
              ?.nrlMaxScore += maxScore;
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
            _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
                ?.aflMarginUPS += marginUPS;
          } else {
            _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
                ?.nrlMarginUPS += marginUPS;
          }
        }
      }
    }
  }

  Future<void> _calculateRoundStats(List<Tipper> tippers, DAURound dauRound,
      TipsViewModel allTipsViewModel) async {
    List<Future<void>> futures = [];
    for (var tipper in tippers) {
      futures.add(
          _calculateRoundStatsForTipper(tipper, dauRound, allTipsViewModel));
    }
    await Future.wait(futures);
  }

  void _rankTippersPerRound() {
    if (_allTipperRoundStats.isEmpty) {
      return;
    }

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
  }

  @override
  void dispose() {
    _allRoundScoresStream.cancel();
    _liveScoresStream.cancel();
    super.dispose();
  }

  void sortRoundWinnersByNRL(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) => ascending
          ? a.value[0].nRL.compareTo(b.value[0].nRL)
          : b.value[0].nRL.compareTo(a.value[0].nRL));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  void sortRoundWinnersByAFL(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) => ascending
          ? a.value[0].aFL.compareTo(b.value[0].aFL)
          : b.value[0].aFL.compareTo(a.value[0].aFL));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  RoundStats getScoringRoundStats(DAURound dauRound, Tipper selectedTipper) {
    if (_allTipperRoundStats.isEmpty) {
      return RoundStats(
          roundNumber: 0,
          aflScore: 0,
          nrlScore: 0,
          aflMaxScore: 0,
          nrlMaxScore: 0,
          aflMarginTips: 0,
          nrlMarginTips: 0,
          aflMarginUPS: 0,
          nrlMarginUPS: 0,
          aflTipsOutstanding: 0,
          nrlTipsOutstanding: 0,
          rank: 0,
          rankChange: 0);
    }

    if (_allTipperRoundStats[dauRound.dAUroundNumber - 1] != null &&
        _allTipperRoundStats[dauRound.dAUroundNumber - 1]![selectedTipper] !=
            null) {
      return _allTipperRoundStats[dauRound.dAUroundNumber - 1]![
          selectedTipper]!;
    } else {
      return RoundStats(
          roundNumber: dauRound.dAUroundNumber,
          aflScore: 0,
          nrlScore: 0,
          aflMaxScore: 0,
          nrlMaxScore: 0,
          aflMarginTips: 0,
          nrlMarginTips: 0,
          aflMarginUPS: 0,
          nrlMarginUPS: 0,
          aflTipsOutstanding: 0,
          nrlTipsOutstanding: 0,
          rank: 0,
          rankChange: 0);
    }
  }
}
