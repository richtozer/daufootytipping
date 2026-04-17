import 'dart:async';
import 'dart:developer';
import 'dart:io'; // Add this import for IOException, SocketException
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/services/scoring_update_queue.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/scoring_update_report.dart';
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
import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:synchronized/synchronized.dart';

// Define constants for Firestore database locations
const String statsFormatVersion = 'v1';
// Use shared root; keep versioned leaves local to file for clarity
const String statsPathRootLocal = p.statsPathRoot;
const String roundStatsRoot = 'round_stats_$statsFormatVersion';
const String liveScoresRoot = 'live_scores_$statsFormatVersion';
const String gameStatsRoot = 'game_stats_$statsFormatVersion';

class StatsViewModel extends ChangeNotifier {
  final Map<int, Map<Tipper, RoundStats>> _allTipperRoundStats = {};
  Map<int, Map<Tipper, RoundStats>> get allTipperRoundStats =>
      _allTipperRoundStats;

  final List<Game> _gamesWithLiveScores = [];

  /// Whether any current scores are based on crowd-sourced live scores
  /// rather than official fixture scores.
  bool get hasLiveScoresInUse => _gamesWithLiveScores.isNotEmpty;

  /// Games currently scored from crowd-sourced live data.
  List<Game> get gamesWithLiveScores =>
      List<Game>.unmodifiable(_gamesWithLiveScores);

  final DatabaseReference _db;
  late StreamSubscription<DatabaseEvent> _liveScoresStream;
  late StreamSubscription<DatabaseEvent> _allRoundScoresStream;
  bool _hasLiveScoresListener = false;
  bool _hasRoundScoresListener = false;

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
  int _roundWinnersSortColumnIndex = 0;
  bool _roundWinnersSortAscending = false;

  GamesViewModel? gamesViewModel;

  bool? _isSelectedTipperPaidUpMember;
  bool get isSelectedTipperPaidUpMember => _isSelectedTipperPaidUpMember!;

  TipsViewModel? allTipsViewModel;
  TipsViewModel? selectedTipperTipsViewModel;

  // Constructor
  StatsViewModel(
    this.selectedDAUComp,
    this.gamesViewModel, {
    DatabaseReference? database,
    bool autoInitialize = true,
  }) : _db = database ?? configuredDatabaseRef() {
    log('StatsViewModel(ALL TIPPERS) for comp: ${selectedDAUComp.dbkey}');
    if (autoInitialize) {
      _initialize();
    }
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
        .child('$statsPathRootLocal/${selectedDAUComp.dbkey}/$roundStatsRoot')
        .onValue
        .listen(
          _handleEventRoundScores,
          onError: (error) {
            log('StatsViewModel() Error listening to round scores: $error');
          },
        );
    _hasRoundScoresListener = true;

    _liveScoresStream = _db
        .child('$statsPathRootLocal/${selectedDAUComp.dbkey}/$liveScoresRoot')
        .onValue
        .listen(
          _handleEventLiveScores,
          onError: (error) {
            log('StatsViewModel() Error listening to live scores: $error');
          },
        );
    _hasLiveScoresListener = true;
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
                var roundStats = RoundStats.fromJson(
                  Map<String, dynamic>.from(
                    entry.value as Map<dynamic, dynamic>,
                  ),
                );
                if (tipper != null) {
                  roundScores[tipper] = roundStats;
                } else {
                  log(
                    'StatsViewModel() Tipper ${entry.key} not found in _handleEventRoundScores',
                  );
                }
              }),
            );
          }

          // Wait for all futures to complete
          await Future.wait(futures);

          _allTipperRoundStats[roundIndex] = roundScores;
        }

        log(
          'StatsViewModel._handleEventRoundScores() Loaded round scores for ${_allTipperRoundStats.length} rounds',
        );
      } else {
        log(
          'StatsViewModel._handleEventRoundScores() Snapshot ${event.snapshot.ref.path} does not exist in _handleEventRoundScores',
        );
      }

      if (!_initialRoundScoresLoadCompleted.isCompleted) {
        _initialRoundScoresLoadCompleted.complete();
      }

      // Update the leaderboard
      await _updateLeaderAndRoundAndRank();
    } catch (e, stackTrace) {
      log('Error listening to /$statsPathRootLocal/round_scores: $e');
      _allTipperRoundStats.clear(); // Rollback partial updates
      if (!_initialRoundScoresLoadCompleted.isCompleted) {
        _initialRoundScoresLoadCompleted.completeError(e, stackTrace);
      }
      rethrow; // Re-throw the error
    }
  }

  @visibleForTesting
  Future<void> handleRoundScoresEventForTest(DatabaseEvent event) {
    return _handleEventRoundScores(event);
  }

  Completer<void>? _updateLock;

  Future<void> _updateLeaderAndRoundAndRank() async {
    if (_updateLock != null) {
      log(
        'StatsViewModel()._updateLeaderAndRoundAndRank() Update already in progress, skipping',
      );
      return;
    }

    _updateLock = Completer<void>();

    try {
      await di<TippersViewModel>().isUserLinked;

      log(
        'StatsViewModel()._updateLeaderAndRoundAndRank() Updating leaderboard and round winners',
      );

      _isSelectedTipperPaidUpMember = di<TippersViewModel>().selectedTipper
          .paidForComp(selectedDAUComp);

      log(
        'StatsViewModel()._updateLeaderAndRoundAndRank() Tipper ${di<TippersViewModel>().selectedTipper.name} paid status is $_isSelectedTipperPaidUpMember',
      );

      // Essential stats first - for immediate UI display
      _updateEssentialStats();

      // Defer expensive calculations to background
      _updateDetailedStatsBackground();
    } catch (e) {
      log('Error: $e');
      rethrow;
    } finally {
      _updateLock?.complete();
      _updateLock = null;
    }
  }

  void _updateEssentialStats() {
    // Essential stats that must be available immediately
    _updateLeaderboardForComp();
    notifyListeners();
    log('StatsViewModel._updateEssentialStats() Essential stats updated');
  }

  void _updateDetailedStatsBackground() {
    // Defer expensive calculations to background using microtask
    Future.microtask(() async {
      try {
        log(
          'StatsViewModel._updateDetailedStatsBackground() Starting background stats',
        );
        _updateRoundWinners();
        _rankTippersPerRound();
        notifyListeners();
        log(
          'StatsViewModel._updateDetailedStatsBackground() Background stats completed',
        );
      } catch (e) {
        log('StatsViewModel._updateDetailedStatsBackground() Error: $e');
      }
    });
  }

  Future<void> _handleEventLiveScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        var dbData = event.snapshot.value as Map<dynamic, dynamic>;
        final gamesWithLiveScores = <Game>[];
        final staleLiveScoreGameDbKeys = <String>[];

        for (var entry in dbData.entries) {
          final gameDbKey = entry.key as String;
          final game = await gamesViewModel?.findGame(gameDbKey);
          if (game == null) {
            log(
              'StatsViewModel._handleEventLiveScores() Game $gameDbKey not found locally. Skipping live score entry.',
            );
            continue;
          }

          if (_hasOfficialFixtureScores(game)) {
            staleLiveScoreGameDbKeys.add(gameDbKey);
            log(
              'StatsViewModel._handleEventLiveScores() Ignoring stale live score for game $gameDbKey because official fixture scores exist.',
            );
            continue;
          }

          var scoring = Scoring.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          if (game.scoring == null) {
            game.scoring = Scoring(
              crowdSourcedScores: scoring.crowdSourcedScores,
            );
          } else {
            game.scoring?.crowdSourcedScores = scoring.crowdSourcedScores;
          }

          gamesWithLiveScores.add(game);

          log(
            'StatsViewModel._handleEventLiveScores() Loaded live score for game ${game.dbkey}',
          );
        }

        _gamesWithLiveScores
          ..clear()
          ..addAll(gamesWithLiveScores);

        notifyListeners();

        await _deleteLiveScoresByGameDbKeys(staleLiveScoreGameDbKeys);
      } else {
        // All live scores have been deleted (e.g. official scores arrived)
        if (_gamesWithLiveScores.isNotEmpty) {
          _gamesWithLiveScores.clear();
          notifyListeners();
        }
      }
    } catch (e) {
      log(
        'StatsViewModel._handleEventLiveScores() Error listening to /$statsPathRootLocal/live_scores: $e',
      );
      rethrow;
    } finally {
      if (!_initialLiveScoreLoadCompleter.isCompleted) {
        _initialLiveScoreLoadCompleter.complete();
      }
    }
  }

  //  These are the various triggers that can cause an update of the stats for a comp.
  // +--------------------------------------+-------------------------------+-------------------------+-----------------------------------------------------------------------------------+
  // | Trigger                              | Rounds re-scored               | Tippers re-scored        | Description                                                                       |
  // +--------------------------------------+-------------------------------+-------------------------+-----------------------------------------------------------------------------------+
  // | Admin clicks 're-score' in UI         | All                           | All                     | Full re-score. Updates all rounds for all tippers.                                |
  // | User places a tip                    | Only the round that tip is for| Tipper who placed tip   | Partial re-score. Updates margin counts for that user and that round.             |
  // | Fixture download has new scores      | Only the round with changes   | All                     | Partial re-score. Scoring updates for all tippers for the current round.          |
  // | User enters a live score             | Only the round with changes   | All                     | Partial re-score. Scoring updates for all tippers for the current round.          |
  // +--------------------------------------+-------------------------------+-------------------------+-----------------------------------------------------------------------------------+

  Future<String>? _updateStatsInProgress;

  Future<ScoringUpdateReport> updateStatsWithReport(
    DAUComp daucompToUpdate,
    DAURound? onlyUpdateThisRound,
    Tipper? onlyUpdateThisTipper,
  ) async {
    await _rebuildScoringViewsForReport();
    final beforeSnapshot = _captureScoringSnapshot();
    final resultMessage = await updateStats(
      daucompToUpdate,
      onlyUpdateThisRound,
      onlyUpdateThisTipper,
    );
    await _rebuildScoringViewsForReport();
    notifyListeners();
    final afterSnapshot = _captureScoringSnapshot();

    return _buildScoringUpdateReport(
      beforeSnapshot,
      afterSnapshot,
      resultMessage,
    );
  }

  Future<String> updateStats(
    DAUComp daucompToUpdate,
    DAURound? onlyUpdateThisRound,
    Tipper? onlyUpdateThisTipper,
  ) {
    if (_updateStatsInProgress != null) {
      log('StatsViewModel.updateStats() Update already in progress, skipping');
      _logEventScoringInitiated(
        'scoring_skipped',
        daucompToUpdate,
        onlyUpdateThisRound,
        onlyUpdateThisTipper,
      );
      return Future.value('Skipped: Another stats update already in progress.');
    }

    final completer = Completer<String>();
    _updateStatsInProgress = completer.future;

    (() async {
      log(
        'StatsViewModel.updateStats() called for comp: ${daucompToUpdate.name}',
      );
      var stopwatch = Stopwatch()..start();

      try {
        if (!_initialRoundScoresLoadCompleted.isCompleted) {
          try {
            await _initialRoundScoresLoadCompleted.future;
          } catch (e) {
            log(
              'StatsViewModel.updateStats() Error waiting for initial round load: $e',
            );
            _allTipperRoundStats.clear(); // reset
          }
        }

        _isUpdateScoringRunning = true;
        notifyListeners();

        _logEventScoringInitiated(
          'scoring_initiated',
          daucompToUpdate,
          onlyUpdateThisRound,
          onlyUpdateThisTipper,
        );

        /// make sure we have all tippers
        await di<TippersViewModel>().initialLoadComplete;

        // Check if we have existing round stats before allowing partial updates
        if ((onlyUpdateThisRound != null || onlyUpdateThisTipper != null) &&
            _allTipperRoundStats.isEmpty) {
          String skipReason =
              'Round stats database is empty - partial updates not allowed';
          log('StatsViewModel.updateStats() $skipReason');
          _logEventScoringInitiated(
            'scoring_skipped_empty_database',
            daucompToUpdate,
            onlyUpdateThisRound,
            onlyUpdateThisTipper,
          );

          _isUpdateScoringRunning = false;
          notifyListeners();
          _updateStatsInProgress = null;
          completer.complete(skipReason);
          return;
        }

        // Set the tippers to update
        List<Tipper> tippersToUpdate = onlyUpdateThisTipper != null
            ? [onlyUpdateThisTipper]
            : List.from(di<TippersViewModel>().tippers);

        log(
          'StatsViewModel.updateStats() Updating stats for ${tippersToUpdate.length} tippers',
        );

        // Prep tips
        if (onlyUpdateThisTipper == null) {
          allTipsViewModel ??= TipsViewModel(
            di<TippersViewModel>(),
            daucompToUpdate,
            gamesViewModel!,
          );

          List<Tipper> tippersToRemove = [];
          await Future.wait(
            tippersToUpdate.map((tipper) async {
              bool hasSubmitted = await allTipsViewModel!.hasSubmittedTips(
                tipper,
              );
              if (!hasSubmitted) {
                tippersToRemove.add(tipper);
                log('Tipper ${tipper.name} did not submit tips. Removing.');
              }
            }),
          );

          tippersToUpdate.removeWhere(
            (tipper) => tippersToRemove.contains(tipper),
          );
        } else {
          selectedTipperTipsViewModel ??=
              di<DAUCompsViewModel>().selectedTipperTipsViewModel;

          await selectedTipperTipsViewModel!.initialLoadCompleted;
        }

        var dauRoundsEdited = _getRoundsToUpdate(
          onlyUpdateThisRound,
          daucompToUpdate,
        );

        for (DAURound dauRound in dauRoundsEdited) {
          if (onlyUpdateThisTipper == null) {
            await _calculateRoundStats(
              tippersToUpdate,
              dauRound,
              allTipsViewModel!,
            );
          } else {
            await _calculateRoundStatsForTipper(
              onlyUpdateThisTipper,
              dauRound,
              selectedTipperTipsViewModel!,
            );
          }
        }

        await _writeScopedRoundScoresToDb(
          dauRoundsEdited,
          tippersToUpdate,
          daucompToUpdate,
        );

        String res =
            'Completed updates for ${tippersToUpdate.length} tippers and ${dauRoundsEdited.length} rounds.';
        log('StatsViewModel.updateStats() $res');

        await _deleteStaleLiveScores();

        completer.complete(res);
      } catch (e) {
        log('StatsViewModel.updateStats() Error: $e');
        completer.completeError(e);
      } finally {
        _logEventScoringInitiated(
          'scoring_completed',
          daucompToUpdate,
          onlyUpdateThisRound,
          onlyUpdateThisTipper,
        );
        _isUpdateScoringRunning = false;
        notifyListeners();
        _updateStatsInProgress = null;
        stopwatch.stop();
        log('StatsViewModel.updateStats() completed in ${stopwatch.elapsed}');
      }
    })();

    return _updateStatsInProgress!;
  }

  void _logEventScoringInitiated(
    String msg,
    DAUComp daucompToUpdate,
    DAURound? onlyUpdateThisRound,
    Tipper? onlyUpdateThisTipper,
  ) {
    try {
      // write a firebase analytic event that scoring is underway
      FirebaseAnalytics.instance.logEvent(
        name: msg,
        parameters: {
          'comp': daucompToUpdate.name,
          'round': onlyUpdateThisRound?.dAUroundNumber ?? 'all',
          'tipper': onlyUpdateThisTipper?.name ?? 'all',
          'withTransaction': 'true',
        },
      );
    } catch (e) {
      log(
        '_logEventScoringInitiated() Error writing log event that scoring has initiated: $e',
      );
      return;
    }
  }

  Future<void> _rebuildScoringViewsForReport() async {
    await di<TippersViewModel>().isUserLinked;

    _isSelectedTipperPaidUpMember = di<TippersViewModel>().selectedTipper
        .paidForComp(selectedDAUComp);

    _updateLeaderboardForComp();
    _updateRoundWinners();
    _rankTippersPerRound();
  }

  ScoringStateSnapshot _captureScoringSnapshot() {
    final roundEntries = <String, ScoringRoundSnapshot>{};
    for (final roundEntry in _allTipperRoundStats.entries) {
      for (final tipperEntry in roundEntry.value.entries) {
        final tipper = tipperEntry.key;
        final roundStats = tipperEntry.value;
        final snapshot = ScoringRoundSnapshot(
          tipperDbKey: tipper.dbkey,
          tipperName: tipper.name,
          roundNumber: roundStats.roundNumber == 0
              ? roundEntry.key + 1
              : roundStats.roundNumber,
          total: roundStats.aflScore + roundStats.nrlScore,
          nrl: roundStats.nrlScore,
          afl: roundStats.aflScore,
          rank: roundStats.rank,
        );
        roundEntries[snapshot.key] = snapshot;
      }
    }

    final leaderboardEntries = <String, ScoringLeaderboardSnapshot>{};
    for (final entry in _compLeaderboard) {
      final snapshot = ScoringLeaderboardSnapshot(
        tipperDbKey: entry.tipper.dbkey,
        tipperName: entry.tipper.name,
        rank: entry.rank,
        total: entry.total,
        nrl: entry.nRL,
        afl: entry.aFL,
        roundsWon: entry.numRoundsWon,
        margins: entry.aflMargins + entry.nrlMargins,
        ups: entry.aflUPS + entry.nrlUPS,
      );
      leaderboardEntries[snapshot.key] = snapshot;
    }

    return ScoringStateSnapshot(
      roundEntries: roundEntries,
      leaderboardEntries: leaderboardEntries,
    );
  }

  ScoringUpdateReport _buildScoringUpdateReport(
    ScoringStateSnapshot beforeSnapshot,
    ScoringStateSnapshot afterSnapshot,
    String resultMessage,
  ) {
    final leaderboardKeys = <String>{
      ...beforeSnapshot.leaderboardEntries.keys,
      ...afterSnapshot.leaderboardEntries.keys,
    };
    final leaderboardChanges = leaderboardKeys
        .map((key) {
          final before = beforeSnapshot.leaderboardEntries[key];
          final after = afterSnapshot.leaderboardEntries[key];
          final change = ScoringLeaderboardChange(
            tipperDbKey: after?.tipperDbKey ?? before?.tipperDbKey,
            tipperName: after?.tipperName ?? before?.tipperName ?? 'Unknown',
            beforeRank: before?.rank ?? 0,
            afterRank: after?.rank ?? 0,
            beforeTotal: before?.total ?? 0,
            afterTotal: after?.total ?? 0,
            beforeNrl: before?.nrl ?? 0,
            afterNrl: after?.nrl ?? 0,
            beforeAfl: before?.afl ?? 0,
            afterAfl: after?.afl ?? 0,
            beforeRoundsWon: before?.roundsWon ?? 0,
            afterRoundsWon: after?.roundsWon ?? 0,
            beforeMargins: before?.margins ?? 0,
            afterMargins: after?.margins ?? 0,
            beforeUps: before?.ups ?? 0,
            afterUps: after?.ups ?? 0,
          );
          return change.hasChange ? change : null;
        })
        .whereType<ScoringLeaderboardChange>()
        .toList()
      ..sort((a, b) {
        final rankDeltaCompare =
            b.rankDelta.abs().compareTo(a.rankDelta.abs());
        if (rankDeltaCompare != 0) return rankDeltaCompare;
        final totalDeltaCompare =
            b.totalDelta.abs().compareTo(a.totalDelta.abs());
        if (totalDeltaCompare != 0) return totalDeltaCompare;
        return a.tipperName.toLowerCase().compareTo(b.tipperName.toLowerCase());
      });

    final roundKeys = <String>{
      ...beforeSnapshot.roundEntries.keys,
      ...afterSnapshot.roundEntries.keys,
    };
    final roundChanges = roundKeys
        .map((key) {
          final before = beforeSnapshot.roundEntries[key];
          final after = afterSnapshot.roundEntries[key];
          final change = ScoringRoundChange(
            tipperDbKey: after?.tipperDbKey ?? before?.tipperDbKey,
            tipperName: after?.tipperName ?? before?.tipperName ?? 'Unknown',
            roundNumber: after?.roundNumber ?? before?.roundNumber ?? 0,
            beforeTotal: before?.total ?? 0,
            afterTotal: after?.total ?? 0,
            beforeNrl: before?.nrl ?? 0,
            afterNrl: after?.nrl ?? 0,
            beforeAfl: before?.afl ?? 0,
            afterAfl: after?.afl ?? 0,
            beforeRank: before?.rank ?? 0,
            afterRank: after?.rank ?? 0,
          );
          return change.hasChange ? change : null;
        })
        .whereType<ScoringRoundChange>()
        .toList()
      ..sort((a, b) {
        final roundCompare = a.roundNumber.compareTo(b.roundNumber);
        if (roundCompare != 0) return roundCompare;
        final totalDeltaCompare =
            b.totalDelta.abs().compareTo(a.totalDelta.abs());
        if (totalDeltaCompare != 0) return totalDeltaCompare;
        return a.tipperName.toLowerCase().compareTo(b.tipperName.toLowerCase());
      });

    return ScoringUpdateReport(
      resultMessage: resultMessage,
      leaderboardChanges: leaderboardChanges,
      roundChanges: roundChanges,
    );
  }

  @visibleForTesting
  Future<ScoringStateSnapshot> captureScoringSnapshotForTest() async {
    await _rebuildScoringViewsForReport();
    return _captureScoringSnapshot();
  }

  @visibleForTesting
  ScoringUpdateReport buildScoringUpdateReportForTest(
    ScoringStateSnapshot beforeSnapshot,
    ScoringStateSnapshot afterSnapshot,
    String resultMessage,
  ) {
    return _buildScoringUpdateReport(
      beforeSnapshot,
      afterSnapshot,
      resultMessage,
    );
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
    // Fast path: if we already have a cached in-memory result and aren't
    // forcing an update, return immediately without any DB read or
    // notifyListeners() call. This avoids triggering rebuilds of every
    // Consumer<StatsViewModel?> when cards re-appear during scrolling.
    final GameStatsEntry? cached = gamesStatsEntry[game];
    if (cached != null && cached.averageScore != null && !forceUpdate) {
      return;
    }

    // Check the database for an existing entry
    final GameStatsEntry dbEntry = await _getGameStatsEntry(game);
    final GameStatsEntry? previousEntry = gamesStatsEntry[game];
    gamesStatsEntry[game] = dbEntry;

    // If the DB had a valid entry and we're not forcing, notify only if the
    // value actually changed (avoids redundant rebuilds).
    if (dbEntry.averageScore != null && !forceUpdate) {
      if (previousEntry != dbEntry) {
        notifyListeners();
      }
      return;
    }

    // Otherwise prep tips model to load all tips to do the calculation -
    // note this is an expensive operation.
    allTipsViewModel ??= TipsViewModel(
      di<TippersViewModel>(),
      selectedDAUComp,
      gamesViewModel!,
    );

    // Await for the tips model to load
    await allTipsViewModel!.initialLoadCompleted;

    // Init or update the game stats entry
    await _updateGameResultPercentageTipped(
      game,
      allTipsViewModel!,
      selectedDAUComp,
    );

    notifyListeners();
  }

  Future<void> _updateGameResultPercentageTipped(
    Game gameToCalculateFor,
    TipsViewModel allTipsViewModel,
    DAUComp daucompToUpdate,
  ) async {
    gamesStatsEntry[gameToCalculateFor] = await allTipsViewModel
        .percentageOfTippersTipped(gameToCalculateFor);

    await _updateGameStatsIfChanged(
      gameToCalculateFor,
      gamesStatsEntry[gameToCalculateFor]!,
      daucompToUpdate,
    );
  }

  Future<void> _updateGameStatsIfChanged(
    Game game,
    GameStatsEntry gameStatsEntry,
    DAUComp daucompToUpdate,
  ) async {
    assert(_isSelectedTipperPaidUpMember != null);

    String subKey = _isSelectedTipperPaidUpMember! ? 'paid' : 'free';

    log('Updating game stats for game: ${game.dbkey}');
    log('Calculated gameStatsEntry: ${gameStatsEntry.toJson()}');
    log('Existing game.gameStats: ${game.gameStats?.toJson()}');

    // Use a transaction to ensure atomic updates
    final gameStatsRef = _db
        .child(statsPathRootLocal)
        .child(daucompToUpdate.dbkey!)
        .child(gameStatsRoot)
        .child(subKey)
        .child(game.dbkey);

    await gameStatsRef
        .runTransaction((currentData) {
          if (currentData != null) {
            // Merge the new data with the existing data if needed
            final existingStats = GameStatsEntry.fromJson(
              Map<String, dynamic>.from(currentData as Map),
            );
            if (existingStats == gameStatsEntry) {
              log('No changes detected in game stats for game: ${game.dbkey}');
              return Transaction.abort(); // Abort the transaction if no changes
            }
          }

          log('Writing updated game stats for game: ${game.dbkey}');
          return Transaction.success(gameStatsEntry.toJson());
        })
        .then((result) {
          if (result.committed) {
            log(
              'Game stats successfully written to DB for game: ${game.dbkey}',
            );
          } else {
            log(
              'Transaction aborted: No changes made to game stats for game: ${game.dbkey}',
            );
          }
        })
        .catchError((error) {
          log('Error during transaction for game stats: $error');
        });
  }

  Future<GameStatsEntry> _getGameStatsEntry(Game game) async {
    await di<TippersViewModel>().isUserLinked;

    _isSelectedTipperPaidUpMember = di<TippersViewModel>().selectedTipper
        .paidForComp(selectedDAUComp);

    String subKey = _isSelectedTipperPaidUpMember! ? 'paid' : 'free';
    var snapshot = await _db
        .child(statsPathRootLocal)
        .child(selectedDAUComp.dbkey!)
        .child(gameStatsRoot)
        .child(subKey)
        .child(game.dbkey)
        .get();

    if (snapshot.exists) {
      return GameStatsEntry.fromJson(
        Map<String, dynamic>.from(snapshot.value as Map),
      );
    } else {
      return GameStatsEntry();
    }
  }

  /// Writes only the recalculated rounds and tippers to the database.
  ///
  /// Unlike the previous _writeAllRoundScoresToDb which wrote all rounds and
  /// all tippers on every update, this method only writes the specific
  /// rounds/tippers that were recalculated. Inside the transaction, it merges
  /// at the tipper level within each round, preserving other tippers' data
  /// even on transaction retry.
  Future<void> _writeScopedRoundScoresToDb(
    List<DAURound> roundsUpdated,
    List<Tipper> tippersUpdated,
    DAUComp dauComp,
  ) async {
    log(
      'StatsViewModel._writeScopedRoundScoresToDb() Writing scores for '
      '${roundsUpdated.length} rounds, ${tippersUpdated.length} tippers',
    );

    // Build a map of only the rounds/tippers that were recalculated
    final Set<int> roundIndices = {
      for (final round in roundsUpdated) round.dAUroundNumber - 1,
    };
    final Set<String> tipperDbKeys = {
      for (final tipper in tippersUpdated)
        if (tipper.dbkey != null) tipper.dbkey!,
    };

    // Pre-compute the tipper-level data to write for each round
    Map<String, Map<String, dynamic>> scopedUpdates = {};
    for (var roundIndex in roundIndices) {
      final roundData = _allTipperRoundStats[roundIndex];
      if (roundData == null) continue;

      Map<String, dynamic> tipperUpdates = {};
      for (var entry in roundData.entries) {
        if (tipperDbKeys.contains(entry.key.dbkey)) {
          tipperUpdates[entry.key.dbkey!] = entry.value.toJson();
        }
      }
      if (tipperUpdates.isNotEmpty) {
        scopedUpdates[roundIndex.toString()] = tipperUpdates;
      }
    }

    if (scopedUpdates.isEmpty) {
      log('StatsViewModel._writeScopedRoundScoresToDb() No updates to write');
      return;
    }

    int retryCount = 0;
    const int maxRetries = 3;
    const Duration initialDelay = Duration(seconds: 2);

    while (true) {
      try {
        await _db
            .child(statsPathRootLocal)
            .child(dauComp.dbkey!)
            .child(roundStatsRoot)
            .runTransaction((currentData) {
              // Firebase RTDB returns sequential numeric keys (0, 1, 2...)
              // as a List, not a Map. Convert either shape to a uniform
              // Map<String, dynamic> keyed by round index string so we can
              // merge safely without losing untouched rounds.
              final Map<String, dynamic> existingData;
              if (currentData is Map) {
                existingData = Map<String, dynamic>.from(currentData);
              } else if (currentData is List) {
                existingData = <String, dynamic>{};
                for (var i = 0; i < currentData.length; i++) {
                  if (currentData[i] != null) {
                    existingData[i.toString()] = currentData[i];
                  }
                }
              } else {
                existingData = <String, dynamic>{};
              }

              // Merge at the tipper level within each round
              for (var roundEntry in scopedUpdates.entries) {
                final roundKey = roundEntry.key;
                final tipperData = roundEntry.value;

                // Get or create the round map from existing server data,
                // handling both Map and List shapes from RTDB
                final existingRoundRaw = existingData[roundKey];
                final Map<String, dynamic> existingRound;
                if (existingRoundRaw is Map) {
                  existingRound = Map<String, dynamic>.from(existingRoundRaw);
                } else {
                  existingRound = <String, dynamic>{};
                }

                // Merge only the tippers we recalculated
                for (var tipperEntry in tipperData.entries) {
                  existingRound[tipperEntry.key] = tipperEntry.value;
                }

                existingData[roundKey] = existingRound;
              }

              return Transaction.success(existingData);
            });
        break;
      } on SocketException catch (e) {
        log('Network error (SocketException) while writing round scores: $e');
        if (retryCount < maxRetries) {
          retryCount++;
          final delay = initialDelay * retryCount;
          log(
            'Retrying in ${delay.inSeconds} seconds... (attempt $retryCount/$maxRetries)',
          );
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
          log(
            'Retrying in ${delay.inSeconds} seconds... (attempt $retryCount/$maxRetries)',
          );
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
          roundWinners[roundNumber]!.add(
            RoundWinnerEntry(
              roundNumber: roundScores.roundNumber,
              tipper: tipper,
              total: totalScore,
              nRL: roundScores.nrlScore,
              aFL: roundScores.aflScore,
              aflMargins: roundScores.aflMarginTips,
              aflUPS: roundScores.aflMarginUPS,
              nrlMargins: roundScores.nrlMarginTips,
              nrlUPS: roundScores.nrlMarginUPS,
            ),
          );

          if (_compLeaderboard.isNotEmpty) {
            var leaderboardEntry = _compLeaderboard.firstWhere(
              (element) => element.tipper == tipper,
            );
            leaderboardEntry.numRoundsWon++;
          }
        }
      }
    }

    _roundWinners = roundWinners;
    _applyRoundWinnersSort();
  }

  Map<Tipper, int> _calculateCumulativeRankUpToRound(int upToRoundNumber) {
    Map<Tipper, int> cumulativeScores = {};

    // Calculate cumulative scores up to the specified round
    for (var roundEntry in _allTipperRoundStats.entries) {
      int roundIndex = roundEntry.key;

      // Only include rounds up to the specified round number
      if (roundIndex + 1 > upToRoundNumber) {
        continue;
      }

      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      for (var tipperEntry in tipperStats.entries) {
        Tipper tipper = tipperEntry.key;
        RoundStats roundScores = tipperEntry.value;

        // Only include tippers who's paid status matches that of the authenticated tipper
        if (_isSelectedTipperPaidUpMember !=
            tipper.paidForComp(selectedDAUComp)) {
          continue;
        }

        cumulativeScores[tipper] =
            (cumulativeScores[tipper] ?? 0) +
            roundScores.aflScore +
            roundScores.nrlScore;
      }
    }

    // Convert to list and sort by cumulative score
    var scoreEntries = cumulativeScores.entries.toList();
    scoreEntries.sort((a, b) => b.value.compareTo(a.value));

    // Assign ranks
    Map<Tipper, int> ranks = {};
    int rank = 1;
    int skip = 1;
    for (int i = 0; i < scoreEntries.length; i++) {
      if (i > 0 && scoreEntries[i].value < scoreEntries[i - 1].value) {
        rank += skip;
        skip = 1;
      } else if (i > 0 && scoreEntries[i].value == scoreEntries[i - 1].value) {
        skip++;
      }
      ranks[scoreEntries[i].key] = rank;
    }

    return ranks;
  }

  void _updateLeaderboardForComp() {
    // Create a map to accumulate scores for each tipper
    Map<Tipper, LeaderboardEntry> leaderboardMap = {};

    // Get the most recent completed round
    int latestCompletedRound = selectedDAUComp.latestsCompletedRoundNumber();

    // Calculate previous round ranks if there are any completed rounds
    Map<Tipper, int> previousRoundRanks = {};
    if (latestCompletedRound > 1) {
      previousRoundRanks = _calculateCumulativeRankUpToRound(
        latestCompletedRound - 1,
      );
    }

    // Calculate the leaderboard for the current comp
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
            previousRank: previousRoundRanks[tipper],
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

      // Calculate rank change
      if (leaderboard[i].previousRank != null) {
        leaderboard[i].rankChange = leaderboard[i].previousRank! - rank;
      }
    }

    // Sort by rank and then by tipper name
    leaderboard.sort((a, b) {
      int rankComparison = a.rank.compareTo(b.rank);
      if (rankComparison == 0) {
        return (a.tipper.name.toLowerCase()).compareTo(
          b.tipper.name.toLowerCase(),
        );
      } else {
        return rankComparison;
      }
    });

    _compLeaderboard = leaderboard;
  }

  void sortRoundWinnersByRoundNumber(bool ascending) {
    _roundWinnersSortColumnIndex = 0;
    _roundWinnersSortAscending = ascending;
    _applyRoundWinnersSort();
  }

  void sortRoundWinnersByWinner(bool ascending) {
    _roundWinnersSortColumnIndex = 1;
    _roundWinnersSortAscending = ascending;
    _applyRoundWinnersSort();
  }

  void sortRoundWinnersByTotal(bool ascending) {
    _roundWinnersSortColumnIndex = 2;
    _roundWinnersSortAscending = ascending;
    _applyRoundWinnersSort();
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

  Future<void> _addMultipleLiveScores(
    Game game,
    List<CrowdSourcedScore> crowdSourcedScores,
  ) async {
    if (crowdSourcedScores.isEmpty) return;

    final oldScoring = game.scoring;

    final newScoring = oldScoring == null
        ? Scoring(
            crowdSourcedScores: List<CrowdSourcedScore>.from(
              crowdSourcedScores,
            ),
          )
        : oldScoring.copyWith(
            crowdSourcedScores: oldScoring.crowdSourcedScores == null
                ? List<CrowdSourcedScore>.from(crowdSourcedScores)
                : [
                    ...oldScoring.crowdSourcedScores!,
                    ...crowdSourcedScores,
                  ],
          );

    game.scoring = newScoring;

    // Clean up old scores for each team that was updated
    for (final scoreTeam in {ScoringTeam.home, ScoringTeam.away}) {
      if (crowdSourcedScores.any((score) => score.scoreTeam == scoreTeam)) {
        if (game.scoring?.crowdSourcedScores != null &&
            game.scoring!.crowdSourcedScores!
                    .where((element) => element.scoreTeam == scoreTeam)
                    .length >
                3) {
          game.scoring!.crowdSourcedScores!.removeWhere(
            (element) =>
                element.scoreTeam == scoreTeam &&
                element.submittedTimeUTC ==
                    game.scoring!.crowdSourcedScores!
                        .where((element) => element.scoreTeam == scoreTeam)
                        .reduce(
                          (value, element) =>
                              value.submittedTimeUTC.isBefore(
                                element.submittedTimeUTC,
                              )
                              ? value
                              : element,
                        )
                        .submittedTimeUTC,
          );
        }
      }
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
      // Process BOTH scores in single atomic operation
      List<CrowdSourcedScore> scoresToAdd = [];

      if (homeScore != originalHomeScore) {
        scoresToAdd.add(
          CrowdSourcedScore(
            DateTime.now().toUtc(),
            ScoringTeam.home,
            tip.tipper.dbkey!,
            int.tryParse(homeScore)!,
            false,
          ),
        );
      }

      if (awayScore != originalAwayScore) {
        scoresToAdd.add(
          CrowdSourcedScore(
            DateTime.now().toUtc(),
            ScoringTeam.away,
            tip.tipper.dbkey!,
            int.tryParse(awayScore)!,
            false,
          ),
        );
      }

      // Add all scores atomically
      await _addMultipleLiveScores(tip.game, scoresToAdd);

      // Use the scoring update queue
      unawaited(
        ScoringUpdateQueue()
            .queueScoringUpdate(
              dauComp: selectedDAUComp,
              round: tip.game.getDAURound(selectedDAUComp),
              tipper: null, // Score all tippers for the round
              priority: 2, // Round-wide update
            )
            .then((result) {
              log('Scoring update queued for round, result: $result');
              getGamesStatsEntry(tip.game, true);
            })
            .catchError((error) {
              log('Error queueing scoring update: $error');
            }),
      );
    });
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
          .child(statsPathRootLocal)
          .child(selectedDAUComp.dbkey!)
          .child(liveScoresRoot)
          .update(liveScores);
      log(
        'StatsViewModel._writeLiveScoreToDb() Wrote live score to DB for game ${game.dbkey}',
      );
    }
  }

  /// Deletes crowd-sourced live scores for games that have official fixture
  /// scores. Uses explicit fixture score checks rather than gameState, which
  /// bundles a 2-hour time delay that is irrelevant to cleanup safety.
  /// Crowd-sourced scores are only removed once official scores are present,
  /// ensuring getGameResultCalculated() never loses its score source.
  Future<void> _deleteStaleLiveScores() async {
    final gamesToDelete = <String>[];
    final gamesVM = gamesViewModel;
    if (gamesVM == null) return;
    for (var game in _gamesWithLiveScores) {
      // Look up the current game from GamesViewModel to get the latest
      // fixture scores — the Game objects in _gamesWithLiveScores are
      // snapshots from when the live scores listener fired and won't
      // have fixture scores that arrived later.
      final currentGame = await gamesVM.findGame(game.dbkey);
      if (_hasOfficialFixtureScores(currentGame)) {
        gamesToDelete.add(game.dbkey);
      }
    }

    await _deleteLiveScoresByGameDbKeys(gamesToDelete);
  }

  bool _hasOfficialFixtureScores(Game? game) {
    return game?.scoring != null &&
        game!.scoring!.homeTeamScore != null &&
        game.scoring!.awayTeamScore != null;
  }

  Future<void> _deleteLiveScoresByGameDbKeys(
    Iterable<String> gameDbKeys,
  ) async {
    final keysToDelete = gameDbKeys.toSet().toList(growable: false);
    if (keysToDelete.isEmpty) {
      return;
    }

    final hadLiveScoresListener = _hasLiveScoresListener;
    if (hadLiveScoresListener) {
      await _liveScoresStream.cancel();
      _hasLiveScoresListener = false;
    }

    for (final gameDbKey in keysToDelete) {
      _gamesWithLiveScores.removeWhere((game) => game.dbkey == gameDbKey);

      await _db
          .child(statsPathRootLocal)
          .child(selectedDAUComp.dbkey!)
          .child(liveScoresRoot)
          .child(gameDbKey)
          .remove();
      log(
        'StatsViewModel._deleteLiveScoresByGameDbKeys() Deleted live scores for game $gameDbKey',
      );
    }

    if (!hadLiveScoresListener) {
      return;
    }

    _liveScoresStream = _db
        .child('$statsPathRootLocal/${selectedDAUComp.dbkey}/$liveScoresRoot')
        .onValue
        .listen(
          _handleEventLiveScores,
          onError: (error) {
            log(
              'StatsViewModel._deleteStaleLiveScores() Error listening to live scores: $error',
            );
          },
        );
    _hasLiveScoresListener = true;
  }

  List<DAURound> _getRoundsToUpdate(
    DAURound? onlyUpdateThisRound,
    DAUComp daucompToUpdate,
  ) {
    // grab all rounds where the round state is allGamesEnded
    List<DAURound> roundsToUpdate = daucompToUpdate.daurounds;
    if (onlyUpdateThisRound != null) {
      roundsToUpdate = [onlyUpdateThisRound];
    }
    log(
      'StatsViewModel._getRoundsToUpdate() Updating stats for ${roundsToUpdate.length} rounds.',
    );
    return roundsToUpdate;
  }

  Future<void> _calculateRoundStatsForTipper(
    Tipper tipperToScore,
    DAURound dauRound,
    TipsViewModel allTipsViewModel,
  ) async {
    // wait until we are initialized
    await _initialRoundScoresLoadCompleted.future;

    // initialize any round of tipper Maps as needed
    if (_allTipperRoundStats[dauRound.dAUroundNumber - 1] == null) {
      _allTipperRoundStats[dauRound.dAUroundNumber - 1] = {};
    }

    //reset all stats for the tipper
    _allTipperRoundStats[dauRound.dAUroundNumber -
        1]![tipperToScore] = RoundStats(
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
      rankChange: 0,
    );

    assert(
      _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore] != null,
    );

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

      int marginTip = (tip.tip == GameResult.a || tip.tip == GameResult.e)
          ? 1
          : 0;

      if (tip.game.league == League.afl) {
        _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]!
                .aflMarginTips +=
            marginTip;
      } else {
        _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]!
                .nrlMarginTips +=
            marginTip;
      }

      if (tip.game.gameState != GameState.notStarted &&
          tip.game.gameState != GameState.startingSoon) {
        int score = tip.getTipScoreCalculated();
        int maxScore = tip.getMaxScoreCalculated();

        if (game.league == League.afl) {
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
                  ?.aflScore +=
              score;
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
                  ?.aflMaxScore +=
              maxScore;
        } else {
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
                  ?.nrlScore +=
              score;
          _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
                  ?.nrlMaxScore +=
              maxScore;
        }

        int marginUPS = 0;
        if (tip.game.scoring != null) {
          marginUPS =
              (tip.game.scoring!.getGameResultCalculated(game.league) ==
                          GameResult.a &&
                      tip.tip == GameResult.a) ||
                  (tip.game.scoring!.getGameResultCalculated(game.league) ==
                          GameResult.e &&
                      tip.tip == GameResult.e)
              ? 1
              : 0;

          if (tip.game.league == League.afl) {
            _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
                    ?.aflMarginUPS +=
                marginUPS;
          } else {
            _allTipperRoundStats[dauRound.dAUroundNumber - 1]![tipperToScore]
                    ?.nrlMarginUPS +=
                marginUPS;
          }
        }
      }
    }
  }

  Future<void> _calculateRoundStats(
    List<Tipper> tippers,
    DAURound dauRound,
    TipsViewModel allTipsViewModel,
  ) async {
    List<Future<void>> futures = [];
    int processedTippers = 0;

    for (var tipper in tippers) {
      // Yield control every 10 tippers to prevent UI blocking
      if (processedTippers % 10 == 0) {
        await Future.microtask(() {});
      }

      futures.add(
        _calculateRoundStatsForTipper(tipper, dauRound, allTipsViewModel),
      );
      processedTippers++;
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
        roundScores.add(
          MapEntry(
            tipper,
            _allTipperRoundStats[roundIndex]![tipper]!.aflScore +
                _allTipperRoundStats[roundIndex]![tipper]!.nrlScore,
          ),
        );
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
    if (di.isRegistered<TippersViewModel>()) {
      di<TippersViewModel>().removeListener(_updateLeaderAndRoundAndRank);
    }
    if (_hasRoundScoresListener) {
      _allRoundScoresStream.cancel();
      _hasRoundScoresListener = false;
    }
    if (_hasLiveScoresListener) {
      _liveScoresStream.cancel();
      _hasLiveScoresListener = false;
    }
    _allTipperRoundStats.clear();
    super.dispose();
  }

  @visibleForTesting
  Future<void> handleLiveScoresEventForTest(DatabaseEvent event) {
    return _handleEventLiveScores(event);
  }

  void sortRoundWinnersByNRL(bool ascending) {
    _roundWinnersSortColumnIndex = 3;
    _roundWinnersSortAscending = ascending;
    _applyRoundWinnersSort();
  }

  void sortRoundWinnersByAFL(bool ascending) {
    _roundWinnersSortColumnIndex = 4;
    _roundWinnersSortAscending = ascending;
    _applyRoundWinnersSort();
  }

  void sortRoundWinnersByMargins(bool ascending) {
    _roundWinnersSortColumnIndex = 5;
    _roundWinnersSortAscending = ascending;
    _applyRoundWinnersSort();
  }

  void sortRoundWinnersByUPS(bool ascending) {
    _roundWinnersSortColumnIndex = 6;
    _roundWinnersSortAscending = ascending;
    _applyRoundWinnersSort();
  }

  void _applyRoundWinnersSort() {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort(_compareRoundWinnerEntries);

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  int _compareRoundWinnerEntries(
    MapEntry<int, List<RoundWinnerEntry>> a,
    MapEntry<int, List<RoundWinnerEntry>> b,
  ) {
    final direction = _roundWinnersSortAscending ? 1 : -1;

    switch (_roundWinnersSortColumnIndex) {
      case 0:
        return direction * a.key.compareTo(b.key);
      case 1:
        return direction *
            a.value[0].tipper.name.toLowerCase().compareTo(
              b.value[0].tipper.name.toLowerCase(),
            );
      case 2:
        return direction * a.value[0].total.compareTo(b.value[0].total);
      case 3:
        return direction * a.value[0].nRL.compareTo(b.value[0].nRL);
      case 4:
        return direction * a.value[0].aFL.compareTo(b.value[0].aFL);
      case 5:
        return direction *
            (a.value[0].aflMargins + a.value[0].nrlMargins).compareTo(
              b.value[0].aflMargins + b.value[0].nrlMargins,
            );
      case 6:
        return direction *
            (a.value[0].aflUPS + a.value[0].nrlUPS).compareTo(
              b.value[0].aflUPS + b.value[0].nrlUPS,
            );
      default:
        return direction * a.key.compareTo(b.key);
    }
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
        rankChange: 0,
      );
    }

    if (_allTipperRoundStats[dauRound.dAUroundNumber - 1] != null &&
        _allTipperRoundStats[dauRound.dAUroundNumber - 1]![selectedTipper] !=
            null) {
      return _allTipperRoundStats[dauRound.dAUroundNumber -
          1]![selectedTipper]!;
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
        rankChange: 0,
      );
    }
  }
}
