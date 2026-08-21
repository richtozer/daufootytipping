import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/crashlytics_error_classifier.dart';
import 'package:flutter/foundation.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:synchronized/synchronized.dart';

// Use shared root; keep versioned leaves local to file for clarity
const String statsPathRootLocal = p.statsPathRoot;

class StatsViewModel extends ChangeNotifier {
  final Map<int, Map<String, RoundStats>> _roundStatsByTipperDbKey = {};
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
  final List<Duration> _gameStatsRetryDelays;
  late StreamSubscription<DatabaseEvent> _liveScoresStream;
  late StreamSubscription<DatabaseEvent> _allRoundPointsStream;
  late StreamSubscription<DatabaseEvent> _gameStatsStream;
  bool _hasLiveScoresListener = false;
  bool _hasRoundPointsListener = false;
  bool _hasGameStatsListener = false;

  final DAUComp selectedDAUComp;

  String get _roundStatsReadRoot => p.roundStatsBackendRoot;
  String get _liveScoresReadRoot => p.liveScoresBackendRoot;
  String get _gameStatsReadRoot => p.gameStatsBackendRoot;

  final Completer<void> _initialLiveScoreLoadCompleter = Completer();
  Future<void> get initialLiveScoreLoadComplete =>
      _initialLiveScoreLoadCompleter.future;

  final Completer<void> _initialRoundPointsLoadCompleted = Completer();
  Future<void> get initialRoundPointsComplete =>
      _initialRoundPointsLoadCompleted.future;

  List<LeaderboardEntry> _compLeaderboard = [];
  List<LeaderboardEntry> get compLeaderboard => _compLeaderboard;

  Map<int, List<RoundWinnerEntry>> _roundWinners = {};
  Map<int, List<RoundWinnerEntry>> get roundWinners => _roundWinners;
  int _roundWinnersSortColumnIndex = 0;
  bool _roundWinnersSortAscending = false;

  GamesViewModel? gamesViewModel;

  bool? _isSelectedTipperPaidUpMember;
  bool get isSelectedTipperPaidUpMember => _isSelectedTipperPaidUpMember!;

  // Constructor
  StatsViewModel(
    this.selectedDAUComp,
    this.gamesViewModel, {
    DatabaseReference? database,
    bool autoInitialize = true,
    List<Duration> gameStatsRetryDelays = const [
      Duration(milliseconds: 250),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  }) : _db = database ?? configuredDatabaseRef(),
       _gameStatsRetryDelays = gameStatsRetryDelays {
    log('StatsViewModel(ALL TIPPERS) for comp: ${selectedDAUComp.dbkey}');
    log(
      'StatsViewModel scoring reads: backend=true '
      'round=$_roundStatsReadRoot game=$_gameStatsReadRoot '
      'live=$_liveScoresReadRoot',
    );
    if (autoInitialize) {
      _initialize();
    }
  }

  void _initialize() async {
    // make sure the tippers viewmodel is initialized
    await di<TippersViewModel>().initialLoadComplete;

    // add a listener for the tipper viewmodel, do a re-calculation of the leaderboards
    // if the tippers change

    di<TippersViewModel>().addListener(_handleTippersUpdated);

    _listenToScores();
  }

  Future<void> _listenToScores() async {
    _allRoundPointsStream = _db
        .child(
          '$statsPathRootLocal/${selectedDAUComp.dbkey}/$_roundStatsReadRoot',
        )
        .onValue
        .listen(
          _handleEventRoundPoints,
          onError: (error) {
            log('StatsViewModel() Error listening to round points: $error');
          },
        );
    _hasRoundPointsListener = true;

    _liveScoresStream = _db
        .child(
          '$statsPathRootLocal/${selectedDAUComp.dbkey}/$_liveScoresReadRoot',
        )
        .onValue
        .listen(
          _handleEventLiveScores,
          onError: (error) {
            log('StatsViewModel() Error listening to live scores: $error');
          },
        );
    _hasLiveScoresListener = true;

    await _listenToGameStats();
  }

  Future<void> _listenToGameStats() async {
    if (_hasGameStatsListener) {
      return;
    }

    await di<TippersViewModel>().isUserLinked;
    _isSelectedTipperPaidUpMember = di<TippersViewModel>().selectedTipper
        .paidForComp(selectedDAUComp);

    final subKey = _isSelectedTipperPaidUpMember! ? 'paid' : 'free';
    _gameStatsStream = _db
        .child(statsPathRootLocal)
        .child(selectedDAUComp.dbkey!)
        .child(_gameStatsReadRoot)
        .child(subKey)
        .onValue
        .listen(
          _handleEventGameStats,
          onError: (error) {
            log('StatsViewModel() Error listening to game stats: $error');
          },
        );
    _hasGameStatsListener = true;
  }

  Future<void> _handleEventRoundPoints(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        final dbData = _roundStatsRowsFromSnapshot(event.snapshot.value);
        // Retain rows by database key so they survive tipper snapshot ordering.
        for (final row in dbData.entries) {
          final roundIndex = row.key;
          final roundPointsJson = row.value;
          final roundPoints = <String, RoundStats>{};

          for (final entry in roundPointsJson.entries) {
            roundPoints[entry.key.toString()] = RoundStats.fromJson(
              Map<String, dynamic>.from(
                entry.value as Map<dynamic, dynamic>,
              ),
              fallbackRoundNumber: roundIndex + 1,
            );
          }

          _roundStatsByTipperDbKey[roundIndex] = roundPoints;
        }
        _relinkRoundStatsToCurrentTippers();

        log(
          'StatsViewModel._handleEventRoundPoints() Loaded round points for ${_allTipperRoundStats.length} rounds',
        );
      } else {
        log(
          'StatsViewModel._handleEventRoundPoints() Snapshot ${event.snapshot.ref.path} does not exist in _handleEventRoundPoints',
        );
      }

      if (!_initialRoundPointsLoadCompleted.isCompleted) {
        _initialRoundPointsLoadCompleted.complete();
      }

      // Update the leaderboard
      await _updateLeaderAndRoundAndRank();
    } catch (e, stackTrace) {
      log('Error listening to /$statsPathRootLocal/$_roundStatsReadRoot: $e');
      _roundStatsByTipperDbKey.clear();
      _allTipperRoundStats.clear(); // Rollback partial updates
      if (!_initialRoundPointsLoadCompleted.isCompleted) {
        _initialRoundPointsLoadCompleted.completeError(e, stackTrace);
      }
      rethrow; // Re-throw the error
    }
  }

  Map<int, Map<dynamic, dynamic>> _roundStatsRowsFromSnapshot(Object? value) {
    if (value is List) {
      final rows = <int, Map<dynamic, dynamic>>{};
      for (var index = 0; index < value.length; index++) {
        final row = value[index];
        if (row is Map) {
          final roundIndex = index - 1;
          if (roundIndex >= 0) {
            rows[roundIndex] = Map<dynamic, dynamic>.from(row);
          }
        }
      }
      return rows;
    }

    if (value is Map) {
      final rows = <int, Map<dynamic, dynamic>>{};
      for (final entry in value.entries) {
        final rawRoundKey = entry.key;
        final roundNumber = rawRoundKey is int
            ? rawRoundKey
            : int.tryParse(rawRoundKey.toString());
        final row = entry.value;
        if (roundNumber == null || row is! Map) {
          continue;
        }
        final roundIndex = roundNumber - 1;
        if (roundIndex >= 0) {
          rows[roundIndex] = Map<dynamic, dynamic>.from(row);
        }
      }
      return rows;
    }

    return <int, Map<dynamic, dynamic>>{};
  }

  @visibleForTesting
  Future<void> handleRoundPointsEventForTest(DatabaseEvent event) {
    return _handleEventRoundPoints(event);
  }

  Completer<void>? _updateLock;

  void _handleTippersUpdated() {
    _relinkRoundStatsToCurrentTippers();
    unawaited(_updateLeaderAndRoundAndRank());
  }

  void _relinkRoundStatsToCurrentTippers() {
    final currentTippersByDbKey = <String, Tipper>{
      for (final tipper in di<TippersViewModel>().tippers)
        if (tipper.dbkey != null) tipper.dbkey!: tipper,
    };
    final relinkedStats = <int, Map<Tipper, RoundStats>>{};

    for (final roundEntry in _roundStatsByTipperDbKey.entries) {
      final roundStats = <Tipper, RoundStats>{};
      for (final tipperEntry in roundEntry.value.entries) {
        final currentTipper = currentTippersByDbKey[tipperEntry.key];
        if (currentTipper != null) {
          roundStats[currentTipper] = tipperEntry.value;
        }
      }
      relinkedStats[roundEntry.key] = roundStats;
    }

    _allTipperRoundStats
      ..clear()
      ..addAll(relinkedStats);
  }

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
        bool liveScoresChanged = false;

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

          final liveScoreEntry = Map<String, dynamic>.from(entry.value as Map);
          final currentLiveScore = liveScoreEntry['current'] is Map
              ? Map<String, dynamic>.from(liveScoreEntry['current'] as Map)
              : liveScoreEntry;
          var scoring = Scoring.fromJson(currentLiveScore);
          if (game.scoring == null) {
            game.scoring = Scoring(
              crowdSourcedScores: scoring.crowdSourcedScores,
            );
          } else {
            game.scoring?.crowdSourcedScores = scoring.crowdSourcedScores;
          }
          liveScoresChanged = true;

          gamesWithLiveScores.add(game);

          log(
            'StatsViewModel._handleEventLiveScores() Loaded live score for game ${game.dbkey}',
          );
        }

        _gamesWithLiveScores
          ..clear()
          ..addAll(gamesWithLiveScores);

        if (liveScoresChanged) {
          gamesViewModel?.liveScoresUpdated();
        }
        notifyListeners();

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

  Future<void> _handleEventGameStats(DatabaseEvent event) async {
    try {
      if (!event.snapshot.exists) {
        return;
      }

      final value = event.snapshot.value;
      if (value is! Map) {
        return;
      }

      bool changed = false;
      for (final entry in value.entries) {
        final gameDbKey = entry.key as String;
        final game = await gamesViewModel?.findGame(gameDbKey);
        if (game == null) {
          log(
            'StatsViewModel._handleEventGameStats() Game $gameDbKey not found locally. Skipping game stats entry.',
          );
          continue;
        }

        final gameStatsEntry = GameStatsEntry.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        final previousEntry = gamesStatsEntry[game.dbkey];
        gamesStatsEntry[game.dbkey] = gameStatsEntry;
        if (previousEntry != gameStatsEntry) {
          changed = true;
        }
      }

      if (changed) {
        notifyListeners();
      }
    } catch (e) {
      log(
        'StatsViewModel._handleEventGameStats() Error listening to /$statsPathRootLocal/game_stats: $e',
      );
      rethrow;
    }
  }

  @visibleForTesting
  Future<void> handleGameStatsEventForTest(DatabaseEvent event) {
    return _handleEventGameStats(event);
  }

  bool get isUpdateScoringRunning => false;
  String? get scoringProgressMessage => null;
  double? get scoringProgressValue => null;

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

  final Map<String, GameStatsEntry> gamesStatsEntry = {};

  GameStatsEntry? gameStatsEntryFor(Game game) {
    return gamesStatsEntry[game.dbkey];
  }

  void getGamesStatsEntry(Game game, bool forceUpdate) async {
    // Fast path avoids rebuilding every card when it reappears during scroll.
    final GameStatsEntry? cached = gameStatsEntryFor(game);
    if (cached != null && !forceUpdate) {
      return;
    }

    GameStatsEntry? dbEntry;
    for (var attempt = 0;; attempt++) {
      try {
        dbEntry = await _getGameStatsEntry(game);
        break;
      } catch (error, stackTrace) {
        if (!CrashlyticsErrorClassifier.isTransientRealtimeDatabaseDisconnect(
          error,
        )) {
          rethrow;
        }

        if (attempt >= _gameStatsRetryDelays.length) {
          log(
            'Transient Realtime Database disconnect while reading game stats for game: ${game.dbkey}; retries exhausted.',
            error: error,
            stackTrace: stackTrace,
          );
          return;
        }

        final retryDelay = _gameStatsRetryDelays[attempt];
        log(
          'Transient Realtime Database disconnect while reading game stats for game: ${game.dbkey}; retrying in ${retryDelay.inMilliseconds}ms.',
          error: error,
          stackTrace: stackTrace,
        );
        await Future<void>.delayed(retryDelay);
      }
    }
    final GameStatsEntry? previousEntry = gamesStatsEntry[game.dbkey];

    if (dbEntry == null) {
      return;
    }

    gamesStatsEntry[game.dbkey] = dbEntry;
    if (previousEntry != dbEntry) {
      notifyListeners();
    }
  }

  Future<GameStatsEntry?> _getGameStatsEntry(Game game) async {
    await di<TippersViewModel>().isUserLinked;

    _isSelectedTipperPaidUpMember = di<TippersViewModel>().selectedTipper
        .paidForComp(selectedDAUComp);

    String subKey = _isSelectedTipperPaidUpMember! ? 'paid' : 'free';
    final snapshot = await _db
        .child(statsPathRootLocal)
        .child(selectedDAUComp.dbkey!)
        .child(_gameStatsReadRoot)
        .child(subKey)
        .child(game.dbkey)
        .get();

    return _gameStatsEntryFromSnapshot(snapshot);
  }

  GameStatsEntry? _gameStatsEntryFromSnapshot(DataSnapshot snapshot) {
    if (!snapshot.exists || snapshot.value is! Map) {
      return null;
    }

    return GameStatsEntry.fromJson(
      Map<String, dynamic>.from(snapshot.value as Map),
    );
  }

  void _updateRoundWinners() {
    Map<int, List<RoundWinnerEntry>> roundWinners = {};
    Map<int, int> maxRoundPoints = {};

    // Iterate over each round
    for (var roundEntry in _allTipperRoundStats.entries) {
      int roundNumber = roundEntry.key;

      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      // Find the maximum points for the round
      for (var tipperEntry in tipperStats.entries) {
        // only include stats from tippers who's paid status matches that of the selected tipper
        // for example if the authenticated tipper is a paid member, only include other paid members for stats
        if (_isSelectedTipperPaidUpMember !=
            tipperEntry.key.paidForComp(selectedDAUComp)) {
          // dont include, skip to the next tipper
          continue;
        }

        RoundStats roundPoints = tipperEntry.value;
        int totalPoints = roundPoints.aflPoints + roundPoints.nrlPoints;

        if (maxRoundPoints[roundNumber] == null ||
            totalPoints > maxRoundPoints[roundNumber]!) {
          maxRoundPoints[roundNumber] = totalPoints;
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
        RoundStats roundPoints = tipperEntry.value;
        int totalPoints = roundPoints.aflPoints + roundPoints.nrlPoints;

        if (totalPoints == maxRoundPoints[roundNumber]! &&
            (roundPoints.nrlMaxPoints + roundPoints.aflMaxPoints > 0)) {
          roundWinners[roundNumber] ??= [];
          roundWinners[roundNumber]!.add(
            RoundWinnerEntry(
              roundNumber: roundPoints.roundNumber,
              tipper: tipper,
              total: totalPoints,
              nRL: roundPoints.nrlPoints,
              aFL: roundPoints.aflPoints,
              aflMargins: roundPoints.aflMarginTips,
              aflUPS: roundPoints.aflMarginUPS,
              nrlMargins: roundPoints.nrlMarginTips,
              nrlUPS: roundPoints.nrlMarginUPS,
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
    Map<Tipper, int> cumulativePoints = {};

    // Calculate cumulative points up to the specified round
    for (var roundEntry in _allTipperRoundStats.entries) {
      int roundIndex = roundEntry.key;

      // Only include rounds up to the specified round number
      if (roundIndex + 1 > upToRoundNumber) {
        continue;
      }

      Map<Tipper, RoundStats> tipperStats = roundEntry.value;

      for (var tipperEntry in tipperStats.entries) {
        Tipper tipper = tipperEntry.key;
        RoundStats roundPoints = tipperEntry.value;

        // Only include tippers who's paid status matches that of the authenticated tipper
        if (_isSelectedTipperPaidUpMember !=
            tipper.paidForComp(selectedDAUComp)) {
          continue;
        }

        cumulativePoints[tipper] =
            (cumulativePoints[tipper] ?? 0) +
            roundPoints.aflPoints +
            roundPoints.nrlPoints;
      }
    }

    // Convert to list and sort by cumulative points
    var pointEntries = cumulativePoints.entries.toList();
    pointEntries.sort((a, b) => b.value.compareTo(a.value));

    // Assign ranks
    Map<Tipper, int> ranks = {};
    int rank = 1;
    int skip = 1;
    for (int i = 0; i < pointEntries.length; i++) {
      if (i > 0 && pointEntries[i].value < pointEntries[i - 1].value) {
        rank += skip;
        skip = 1;
      } else if (i > 0 && pointEntries[i].value == pointEntries[i - 1].value) {
        skip++;
      }
      ranks[pointEntries[i].key] = rank;
    }

    return ranks;
  }

  void _updateLeaderboardForComp() {
    // Create a map to accumulate points for each tipper
    Map<Tipper, LeaderboardEntry> leaderboardMap = {};

    // Get the most recent completed round
    int latestCompletedRound = selectedDAUComp.latestsCompletedRoundNumber();

    // Live scoring can add stats for the round after the latest completed one.
    // In that case CNG must compare the live ladder with the completed-round
    // ladder, rather than skipping back an additional round.
    final hasStatsAfterLatestCompletedRound = _allTipperRoundStats.keys.any(
      (roundIndex) => roundIndex + 1 > latestCompletedRound,
    );
    final previousRankRound = hasStatsAfterLatestCompletedRound
        ? latestCompletedRound
        : latestCompletedRound - 1;

    // Calculate previous round ranks if there are any completed rounds
    Map<Tipper, int> previousRoundRanks = {};
    if (previousRankRound > 0) {
      previousRoundRanks = _calculateCumulativeRankUpToRound(
        previousRankRound,
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
        RoundStats roundPoints = tipperEntry.value;

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

        // Update leaderboard entry with round points
        leaderboardMap[tipper]!.total +=
            roundPoints.aflPoints + roundPoints.nrlPoints;
        leaderboardMap[tipper]!.nRL += roundPoints.nrlPoints;
        leaderboardMap[tipper]!.aFL += roundPoints.aflPoints;
        leaderboardMap[tipper]!.aflMargins += roundPoints.aflMarginTips;
        leaderboardMap[tipper]!.aflUPS += roundPoints.aflMarginUPS;
        leaderboardMap[tipper]!.nrlMargins += roundPoints.nrlMarginTips;
        leaderboardMap[tipper]!.nrlUPS += roundPoints.nrlMarginUPS;
      }
    }

    // Convert the map to a list and sort by total points
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

  List<RoundStats> getTipperRoundPointsForComp(Tipper tipper) {
    if (!_initialRoundPointsLoadCompleted.isCompleted) {
      return [];
    }

    List<RoundStats> tipperRoundPoints = [];
    for (var round in _allTipperRoundStats.entries) {
      int roundNumber = round.key;

      // skip rounds in stats data that exceed the max round number - these are likely finals rounds
      if (roundNumber + 1 >
          (di<DAUCompsViewModel>().selectedDAUComp?.daurounds.length ?? 0)) {
        continue;
      }
      if (round.value.containsKey(tipper)) {
        tipperRoundPoints.add(round.value[tipper]!);
      }
    }

    return tipperRoundPoints;
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
                : [...oldScoring.crowdSourcedScores!, ...crowdSourcedScores],
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

    await di<StatsViewModel>()._writeLiveScoreToDb(game, crowdSourcedScores);
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
      final currentHomeScore = tip.game.scoring?.currentScore(
        ScoringTeam.home,
      );
      final currentAwayScore = tip.game.scoring?.currentScore(
        ScoringTeam.away,
      );
      final homeScoreChanged = homeScore != originalHomeScore;
      final awayScoreChanged = awayScore != originalAwayScore;

      // Process BOTH scores in single atomic operation
      List<CrowdSourcedScore> scoresToAdd = [];

      void addScore(ScoringTeam scoreTeam, String score) {
        scoresToAdd.add(
          CrowdSourcedScore(
            DateTime.now().toUtc(),
            scoreTeam,
            tip.tipper.dbkey!,
            int.tryParse(score)!,
            false,
          ),
        );
      }

      if (homeScoreChanged) {
        addScore(ScoringTeam.home, homeScore);
      }

      if (awayScoreChanged) {
        addScore(ScoringTeam.away, awayScore);
      }

      if (scoresToAdd.isNotEmpty) {
        if (!homeScoreChanged && currentHomeScore == null) {
          addScore(ScoringTeam.home, homeScore);
        }
        if (!awayScoreChanged && currentAwayScore == null) {
          addScore(ScoringTeam.away, awayScore);
        }
      }

      // Add all scores atomically
      await _addMultipleLiveScores(tip.game, scoresToAdd);

      // Backend database triggers recalculate scoring from live score writes.
    });
  }

  Future<void> _writeLiveScoreToDb(
    Game game,
    List<CrowdSourcedScore> submittedScores,
  ) async {
    if (!_gamesWithLiveScores.contains(game)) {
      _gamesWithLiveScores.add(game);
    }

    final updates = <String, Object?>{
      '${game.dbkey}/current': _liveScoreCurrentPayload(game),
    };
    for (final score in submittedScores) {
      final historyKey =
          '${score.submittedTimeUTC.microsecondsSinceEpoch}-${score.scoreTeam.name}';
      updates['${game.dbkey}/history/$historyKey'] = score.toJson();
    }

    await _db
        .child(statsPathRootLocal)
        .child(selectedDAUComp.dbkey!)
        .child(p.liveScoresBackendRoot)
        .update(updates);
    log(
      'StatsViewModel._writeLiveScoreToDb() Wrote live score current snapshot for game ${game.dbkey}',
    );
  }

  Map<String, Object?> _liveScoreCurrentPayload(Game game) {
    final scoring = game.scoring;
    CrowdSourcedScore? latestScore;
    for (final score in scoring?.crowdSourcedScores ?? <CrowdSourcedScore>[]) {
      if (latestScore == null ||
          score.submittedTimeUTC.isAfter(latestScore.submittedTimeUTC)) {
        latestScore = score;
      }
    }

    return <String, Object?>{
      'homeInterimScore': scoring?.currentScore(ScoringTeam.home),
      'awayInterimScore': scoring?.currentScore(ScoringTeam.away),
      'submittedTimeUTC': latestScore?.submittedTimeUTC.toIso8601String(),
      'tipperID': latestScore?.tipperID,
      'gameComplete': latestScore?.gameComplete ?? false,
      'crowdSourcedScores': scoring?.crowdSourcedScores
          ?.map((score) => score.toJson())
          .toList(),
    };
  }

  bool _hasOfficialFixtureScores(Game? game) {
    return game?.scoring != null &&
        game!.scoring!.homeTeamScore != null &&
        game.scoring!.awayTeamScore != null;
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

      List<MapEntry<Tipper, int>> roundPoints = [];

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
        roundPoints.add(
          MapEntry(
            tipper,
            _allTipperRoundStats[roundIndex]![tipper]!.aflPoints +
                _allTipperRoundStats[roundIndex]![tipper]!.nrlPoints,
          ),
        );
      }

      roundPoints.sort((a, b) => b.value.compareTo(a.value));

      int rank = 1;
      int? lastScore;
      int sameRankCount = 0;

      for (var entry in roundPoints) {
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
      di<TippersViewModel>().removeListener(_handleTippersUpdated);
    }
    if (_hasRoundPointsListener) {
      _allRoundPointsStream.cancel();
      _hasRoundPointsListener = false;
    }
    if (_hasLiveScoresListener) {
      _liveScoresStream.cancel();
      _hasLiveScoresListener = false;
    }
    if (_hasGameStatsListener) {
      _gameStatsStream.cancel();
      _hasGameStatsListener = false;
    }
    _roundStatsByTipperDbKey.clear();
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
        aflPoints: 0,
        nrlPoints: 0,
        aflMaxPoints: 0,
        nrlMaxPoints: 0,
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
        aflPoints: 0,
        nrlPoints: 0,
        aflMaxPoints: 0,
        nrlMaxPoints: 0,
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
