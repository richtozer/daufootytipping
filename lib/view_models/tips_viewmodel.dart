import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:dau_shared/services/outstanding_tips_calculator.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class _CachedCrossCompTip {
  const _CachedCrossCompTip({required this.tip, required this.cachedAtUtc});

  final Tip? tip;
  final DateTime cachedAtUtc;
}

class TipsViewModel extends ChangeNotifier {
  List<Tip?> _listOfTips = [];
  Map<String, Map<String, Tip>>? _tipsByGameAndTipper;
  final DatabaseReference _db;
  StreamSubscription<DatabaseEvent>? _tipsStream;

  final DAUComp selectedDAUComp;
  final Completer<void> _initialLoadCompleter = Completer();

  Future<void> get initialLoadCompleted async => _initialLoadCompleter.future;

  bool get isInitialLoadComplete => _initialLoadCompleter.isCompleted;

  /// Synchronously finds the index of the first game in [games] that the
  /// [tipper] has not yet tipped. Returns -1 if tips have not loaded or if
  /// every game has a tip.
  int firstUntippedGameIndex(List<Game> games, Tipper tipper) {
    if (!_initialLoadCompleter.isCompleted) return -1;
    for (var i = 0; i < games.length; i++) {
      final hasTip = _listOfTips.any(
        (tip) =>
            tip != null &&
            _matchesGame(tip.game, games[i]) &&
            tip.tipper.dbkey == tipper.dbkey,
      );
      if (!hasTip) return i;
    }
    return -1;
  }

  /// The tipper whose tips this holds.
  final Tipper _tipper;

  late final GamesViewModel _gamesViewModel;
  GamesViewModel get gamesViewModel => _gamesViewModel;

  late final TippersViewModel tipperViewModel;

  //constructor - this will get all tips from db for a specific tipper - less expensive and quicker db read
  TipsViewModel.forTipper(
    this.tipperViewModel,
    this.selectedDAUComp,
    this._gamesViewModel,
    this._tipper, {
    DatabaseReference? database,
    bool listenToTips = true,
  }) : _db = database ?? configuredDatabaseRef(),
       _gameReadRetryDelay = defaultGameReadRetryDelay {
    log('TipsViewModel.forTipper constructor for tipper ${_tipper.dbkey}');
    _gamesViewModel.addListener(_update);
    if (listenToTips) {
      _listenToTips();
    } else {
      _completeInitialLoadIfNeeded();
    }
  }

  /// For looking at a tipper's tips the way the R2 rules allow: one started game
  /// at a time and nothing wider (the tipper's own node and the competition's
  /// are for the tipper and administrators only). Nothing is listened to until
  /// [watchGames] says which games.
  TipsViewModel.forTipperGames(
    this.tipperViewModel,
    this.selectedDAUComp,
    this._gamesViewModel,
    this._tipper, {
    DatabaseReference? database,
    Duration gameReadRetryDelay = defaultGameReadRetryDelay,
  }) : _db = database ?? configuredDatabaseRef(),
       _gameReadRetryDelay = gameReadRetryDelay {
    _perGame = true;
    log('TipsViewModel.forTipperGames constructor for tipper ${_tipper.dbkey}');
    _gamesViewModel.addListener(_update);
  }

  /// How long to wait before trying again to read a game the server would not
  /// show: the device's clock may be a little ahead of the server's, so the game
  /// has started here but its tips are not yet readable there.
  static const Duration defaultGameReadRetryDelay = Duration(seconds: 5);

  /// How many times in a row a game is tried again without being asked to.
  static const int maxAutomaticGameReadRetries = 3;

  bool _perGame = false;
  bool _disposed = false;
  final Duration _gameReadRetryDelay;
  final Map<String, StreamSubscription<DatabaseEvent>> _gameStreams = {};
  final Map<String, Tip> _perGameTips = {};
  Map<String, Game> _wantedGames = {};
  final Map<String, int> _failedGameReads = {};
  Timer? _gameReadRetryTimer;

  /// Per-game mode only (anything else ignores the call): listens to the tips of
  /// exactly [games], opens a listener for each game not yet watched and closes
  /// the ones no longer wanted. Asking again for the same games changes nothing
  /// and notifies nobody, so a screen may call it on every refresh. Completes
  /// once every newly watched game has answered once; a game the server refuses
  /// to show (its kickoff has not passed there yet) counts as answered, with no
  /// tip. Such a game is not watched any more, so asking again tries it afresh,
  /// and it is tried again on its own a few times, a few seconds apart.
  Future<void> watchGames(Iterable<Game> games) async {
    if (!_perGame || _disposed) {
      return;
    }
    final Map<String, Game> wanted = {
      for (final game in games) game.dbkey: game,
    };
    _wantedGames = wanted;
    _failedGameReads.removeWhere(
      (String key, int _) => !wanted.containsKey(key),
    );

    bool changed = false;
    for (final String key
        in _gameStreams.keys
            .where((key) => !wanted.containsKey(key))
            .toList()) {
      await _gameStreams.remove(key)?.cancel();
      _perGameTips.remove(key);
      changed = true;
    }

    final List<Future<void>> firstAnswers = [];
    for (final MapEntry<String, Game> entry in wanted.entries) {
      if (_gameStreams.containsKey(entry.key)) {
        continue;
      }
      final Completer<void> firstAnswer = Completer<void>();
      firstAnswers.add(firstAnswer.future);
      late final StreamSubscription<DatabaseEvent> subscription;
      subscription = _db
          .child(
            '${p.tipsPathRoot}/${selectedDAUComp.dbkey}/${_tipper.dbkey}/${entry.key}',
          )
          .onValue
          .listen(
            (DatabaseEvent event) {
              _failedGameReads.remove(entry.key);
              _applyGameSnapshot(entry.value, event.snapshot);
              if (!firstAnswer.isCompleted) {
                firstAnswer.complete();
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              log(
                'TipsViewModel.watchGames() cannot read the tip for game ${entry.key}: $error',
              );
              _gameReadFailed(entry.key, subscription);
              if (!firstAnswer.isCompleted) {
                firstAnswer.complete();
              }
            },
          );
      _gameStreams[entry.key] = subscription;
    }

    if (changed) {
      _publishPerGameTips();
    }
    await Future.wait(firstAnswers);
    _completeInitialLoadIfNeeded();
  }

  /// The server would not show the tip for [gameKey], and a listener it has
  /// refused does not recover. Drops it, so that the next [watchGames] opens a
  /// fresh one, and tries once more on its own after a short wait, a few times.
  void _gameReadFailed(
    String gameKey,
    StreamSubscription<DatabaseEvent> failed,
  ) {
    unawaited(failed.cancel());
    if (identical(_gameStreams[gameKey], failed)) {
      _gameStreams.remove(gameKey);
    }
    if (_perGameTips.remove(gameKey) != null) {
      _publishPerGameTips();
    }
    final int failures = (_failedGameReads[gameKey] ?? 0) + 1;
    _failedGameReads[gameKey] = failures;
    if (failures > maxAutomaticGameReadRetries || _disposed) {
      return;
    }
    if (_gameReadRetryTimer?.isActive ?? false) {
      return;
    }
    _gameReadRetryTimer = Timer(_gameReadRetryDelay, () {
      unawaited(watchGames(_wantedGames.values));
    });
  }

  void _applyGameSnapshot(Game game, DataSnapshot snapshot) {
    final Object? value = snapshot.exists ? snapshot.value : null;
    if (value is Map) {
      _perGameTips[game.dbkey] = Tip.fromJson(
        Map<String, dynamic>.from(value),
        game.dbkey,
        _tipper,
        game,
      );
    } else {
      _perGameTips.remove(game.dbkey);
    }
    _publishPerGameTips();
  }

  void _publishPerGameTips() {
    _listOfTips = _perGameTips.values.toList();
    _tipsByGameAndTipper = null;
    _crossCompTipCache.clear();
    notifyListeners();
  }

  void _update() {
    _tipsByGameAndTipper = null;
    _crossCompTipCache.clear();
    notifyListeners(); //notify our consumers that the data may have changed to gamesViewModel.games data that we have a dependency on
  }

  void _listenToTips() {
    _tipsStream = _db
        .child('${p.tipsPathRoot}/${selectedDAUComp.dbkey}/${_tipper.dbkey}')
        .onValue
        .listen((event) {
          _handleEvent(event);
        });
  }

  void _completeInitialLoadIfNeeded() {
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    await _applyTipsSnapshot(event.snapshot);
  }

  Future<void> _applyTipsSnapshot(DataSnapshot snapshot) async {
    try {
      if (snapshot.exists) {
        log('_handleEvent deserializing tips for tipper ${_tipper.dbkey}');
        final stopwatch = Stopwatch()..start();
        Map<String, dynamic> dbData = Map<String, dynamic>.from(
          snapshot.value as Map,
        );
        log(
          '_handleEvent (Tipper ${_tipper.dbkey}) - number of tips to deserialize: ${dbData.length}',
        );
        // Pre-load game map for instant O(1) lookups
        final games = await _gamesViewModel.getGames();
        final Map<String, Game> gameMap = {
          for (final game in games) game.dbkey: game,
        };

        _listOfTips = dbData.entries.map((tipEntry) {
          Game? game = gameMap[tipEntry.key];
          if (game == null) {
            assert(game != null);
            log(
              'TipsViewModel._handleEvent() Game not found for tip ${tipEntry.key}',
            );
            return null;
          } else {
            Map<String, dynamic> entryValue = Map<String, dynamic>.from(
              tipEntry.value as Map,
            );
            return Tip.fromJson(entryValue, tipEntry.key, _tipper, game);
          }
        }).toList();
        stopwatch.stop();
        log(
          'Single tipper tip loading completed in ${stopwatch.elapsedMilliseconds}ms for ${_listOfTips.length} tips',
        );
        StartupProfiling.instant(
          'startup.single_tipper_tips_loaded',
          arguments: <String, Object?>{
            'elapsedMs': stopwatch.elapsedMilliseconds,
            'tipCount': _listOfTips.length,
          },
        );
      } else {
        log('TipsViewModel._handleEvent() No tips found in realtime database');
        _listOfTips = <Tip?>[];
      }
    } finally {
      _tipsByGameAndTipper = null;
      _crossCompTipCache.clear();
      if (!_initialLoadCompleter.isCompleted) {
        _completeInitialLoadIfNeeded();
        StartupProfiling.instant(
          'startup.tips_initial_load_complete',
          arguments: <String, Object?>{
            'tipperScoped': true,
            'tipCount': _listOfTips.length,
          },
        );
      }
      notifyListeners();
    }
  }

  Future<void> refreshFromServer() async {
    if (_perGame) {
      for (final String gameKey in _gameStreams.keys.toList()) {
        final Game? game = await _gamesViewModel.findGame(gameKey);
        if (game == null) {
          continue;
        }
        _applyGameSnapshot(
          game,
          await _db
              .child(
                '${p.tipsPathRoot}/${selectedDAUComp.dbkey}/${_tipper.dbkey}/$gameKey',
              )
              .get(),
        );
      }
      return;
    }
    final path = '${p.tipsPathRoot}/${selectedDAUComp.dbkey}/${_tipper.dbkey}';
    await _applyTipsSnapshot(await _db.child(path).get());
  }

  bool _matchesGame(Game cachedGame, Game lookupGame) {
    return cachedGame.dbkey == lookupGame.dbkey &&
        cachedGame.startTimeUTC == lookupGame.startTimeUTC &&
        cachedGame.homeTeam.dbkey == lookupGame.homeTeam.dbkey &&
        cachedGame.awayTeam.dbkey == lookupGame.awayTeam.dbkey;
  }

  Tip? _defaultTipIfGameStarted(Game game, Tipper tipper) {
    if (game.gameState == GameState.startedResultKnown ||
        game.gameState == GameState.startedResultNotKnown) {
      return Tip(
        tip: GameResult.d,
        // set this tipper time as epoch,
        // allows us to easily identify tips that were not submitted
        submittedTimeUTC: DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
        game: game,
        tipper: tipper,
      );
    }

    return null;
  }

  Tip _rebindTipToCurrentGame(Tip tip, Game currentGame) {
    if (identical(tip.game, currentGame)) {
      return tip;
    }

    return Tip(
      dbkey: tip.dbkey,
      game: currentGame,
      tipper: tip.tipper,
      tip: tip.tip,
      submittedTimeUTC: tip.submittedTimeUTC,
    );
  }

  Future<Tip?> findTip(Game game, Tipper tipper) async {
    await initialLoadCompleted;

    Tip? foundTip = _tipsForGameByTipper(game)[tipper.dbkey];

    if (foundTip == null && _gameBelongsToComp(game, selectedDAUComp)) {
      foundTip = _findCurrentCompTipByGameKey(game, tipper);
    }

    if (foundTip != null) {
      foundTip = _rebindTipToCurrentGame(foundTip, game);
    }

    foundTip ??= _defaultTipIfGameStarted(game, tipper);

    return foundTip;
  }

  Tip? _findCurrentCompTipByGameKey(Game game, Tipper tipper) {
    return _listOfTips.firstWhereOrNull(
      (tip) =>
          tip != null &&
          tip.game.dbkey == game.dbkey &&
          tip.tipper.dbkey == tipper.dbkey,
    );
  }

  Map<String, Tip> _tipsForGameByTipper(Game game) {
    _tipsByGameAndTipper ??= _buildTipsByGameAndTipper();
    return _tipsByGameAndTipper![_gameTipCacheKey(game)] ?? const {};
  }

  Map<String, Map<String, Tip>> _buildTipsByGameAndTipper() {
    final index = <String, Map<String, Tip>>{};
    for (final tip in _listOfTips) {
      if (tip == null || tip.tipper.dbkey == null) {
        continue;
      }
      final gameKey = _gameTipCacheKey(tip.game);
      index.putIfAbsent(gameKey, () => <String, Tip>{})[tip.tipper.dbkey!] =
          tip;
    }
    return index;
  }

  String _gameTipCacheKey(Game game) {
    return '${game.dbkey}|${game.startTimeUTC.toUtc().millisecondsSinceEpoch}|${game.homeTeam.dbkey}|${game.awayTeam.dbkey}';
  }

  bool _gameBelongsToComp(Game game, DAUComp dauComp) {
    for (final round in dauComp.daurounds) {
      final start = round.getRoundStartDate();
      final end = round.getRoundEndDate();
      final isOnOrAfterStart =
          game.startTimeUTC.isAfter(start) ||
          game.startTimeUTC.isAtSameMomentAs(start);
      final isOnOrBeforeEnd =
          game.startTimeUTC.isBefore(end) ||
          game.startTimeUTC.isAtSameMomentAs(end);
      if (isOnOrAfterStart && isOnOrBeforeEnd) {
        return true;
      }
    }

    return false;
  }

  static const Duration _crossCompTipCacheTtl = Duration(minutes: 5);
  final Map<String, _CachedCrossCompTip> _crossCompTipCache = {};

  String _crossCompCacheKey(String compDbKey, Game game, Tipper tipper) {
    return '$compDbKey|${tipper.dbkey}|${game.dbkey}|${game.startTimeUTC.toUtc().millisecondsSinceEpoch}';
  }

  Future<Tip?> findTipAcrossCompetitions(
    Game game,
    Tipper tipper,
    Iterable<DAUComp> dauComps,
  ) async {
    await initialLoadCompleted;

    final candidateComps = dauComps
        .where((comp) => comp.dbkey != null && _gameBelongsToComp(game, comp))
        .toList();

    if (candidateComps.any((comp) => comp.dbkey == selectedDAUComp.dbkey)) {
      final currentCompTip = await findTip(game, tipper);
      if (currentCompTip != null && !currentCompTip.isDefaultTip()) {
        return currentCompTip;
      }
    }

    for (final comp in candidateComps) {
      final compDbKey = comp.dbkey;
      if (compDbKey == null || compDbKey == selectedDAUComp.dbkey) {
        continue;
      }

      final cacheKey = _crossCompCacheKey(compDbKey, game, tipper);
      if (_crossCompTipCache.containsKey(cacheKey)) {
        final cachedEntry = _crossCompTipCache[cacheKey]!;
        final cacheAge = DateTime.now().toUtc().difference(
          cachedEntry.cachedAtUtc,
        );
        if (cacheAge <= _crossCompTipCacheTtl) {
          if (cachedEntry.tip != null) {
            return cachedEntry.tip;
          }
          continue;
        }
        _crossCompTipCache.remove(cacheKey);
      }

      final snapshot = await _db
          .child('${p.tipsPathRoot}/$compDbKey/${tipper.dbkey}/${game.dbkey}')
          .get();

      Tip? loadedTip;
      if (snapshot.exists && snapshot.value != null) {
        loadedTip = Tip.fromJson(
          Map<String, dynamic>.from(snapshot.value as Map),
          game.dbkey,
          tipper,
          game,
        );
      }

      _crossCompTipCache[cacheKey] = _CachedCrossCompTip(
        tip: loadedTip,
        cachedAtUtc: DateTime.now().toUtc(),
      );

      if (loadedTip != null) {
        return loadedTip;
      }
    }

    return _defaultTipIfGameStarted(game, tipper);
  }

  /// Waits for a specific tip to be updated in the in-memory cache after database changes
  /// This ensures stats calculations run on current data, not stale cache
  Future<void> waitForTipUpdate(Tip expectedTip) async {
    await initialLoadCompleted;

    // Wait for the database streaming listener to process the change
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));

      Tip? foundTip = _listOfTips.firstWhereOrNull(
        (tip) =>
            tip != null &&
            _matchesGame(tip.game, expectedTip.game) &&
            tip.tipper.dbkey == expectedTip.tipper.dbkey,
      );

      // Continue waiting if tip not found or tip data doesn't match
      if (foundTip == null) {
        return true; // Keep waiting
      }

      // Check if the tip data matches (comparing key fields)
      bool tipMatches =
          foundTip.tip == expectedTip.tip &&
          // Compare at second precision to accommodate compact epoch seconds storage
          (foundTip.submittedTimeUTC.millisecondsSinceEpoch ~/ 1000) ==
              (expectedTip.submittedTimeUTC.millisecondsSinceEpoch ~/ 1000);

      return !tipMatches; // Stop waiting when tips match
    });
  }

  // returns true if the supplied tipper has submitted at least one tip for the comp
  Future<bool> hasSubmittedTips(Tipper tipper) async {
    await initialLoadCompleted;
    return _listOfTips.any((tip) => tip?.tipper.dbkey == tipper.dbkey);
  }

  // Outstanding tips for games that have not started yet (includes startingSoon).
  int numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
    DAURound round,
    League league,
  ) {
    return OutstandingTipsCalculator.countUpcomingUntippedGames(
      games: round.getGamesForLeague(league),
      submittedGameKeys: _listOfTips
          .whereType<Tip>()
          .map((tip) => tip.game.dbkey)
          .toSet(),
      now: DateTime.now().toUtc(),
    );
  }

  // method to return the number of margin tips for the supplied round and league
  int numberOfMarginTipsSubmittedForRoundAndLeague(
    DAURound round,
    League league,
  ) {
    return _listOfTips
        .where(
          (tip) =>
              tip!.game.getDAURound(selectedDAUComp) == round &&
              tip.game.league == league &&
              (tip.tip == GameResult.a || tip.tip == GameResult.e),
        )
        .length;
  }

  /// The tip [tipper] has made for the game, as this device shows it, or null if
  /// they have not tipped it. Unlike [findTip], a game never tipped is not given a
  /// default tip. A tip the device has queued but the server has not yet accepted
  /// is shown too.
  Tip? submittedTipForGame(String gameKey, Tipper tipper) {
    for (final tip in _listOfTips) {
      if (tip != null &&
          tip.game.dbkey == gameKey &&
          tip.tipper.dbkey == tipper.dbkey) {
        return tip;
      }
    }
    return null;
  }

  List<Tip?> getTipsForTipper(Tipper tipper) {
    return _listOfTips
        .where((tip) => tip!.tipper.dbkey == tipper.dbkey)
        .toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _gameReadRetryTimer?.cancel();
    _tipsStream?.cancel(); // stop listening to stream
    for (final StreamSubscription<DatabaseEvent> stream
        in _gameStreams.values) {
      stream.cancel();
    }
    _gameStreams.clear();
    _gamesViewModel.removeListener(_update);
    super.dispose();
  }

  @visibleForTesting
  void setTipsForTest(List<Tip?> tips) {
    _listOfTips = List<Tip?>.from(tips);
    _tipsByGameAndTipper = null;
    _completeInitialLoadIfNeeded();
  }
}
