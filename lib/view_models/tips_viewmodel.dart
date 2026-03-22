import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class _CachedCrossCompTip {
  const _CachedCrossCompTip({required this.tip, required this.cachedAtUtc});

  final Tip? tip;
  final DateTime cachedAtUtc;
}

class TipsViewModel extends ChangeNotifier {
  List<Tip?> _listOfTips = [];
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

  Tipper?
  _tipper; // if this is supplied in the constructor, then we are only interested in the tips for this tipper

  late final GamesViewModel _gamesViewModel;
  GamesViewModel get gamesViewModel => _gamesViewModel;

  late final TippersViewModel tipperViewModel;

  //constructor - this will get all tips from db
  TipsViewModel(
    this.tipperViewModel,
    this.selectedDAUComp,
    this._gamesViewModel,
    {DatabaseReference? database, bool listenToTips = true,}
  ) : _db = database ?? FirebaseDatabase.instance.ref() {
    log('TipsViewModel (all tips) constructor');
    _gamesViewModel.addListener(_update);
    if (listenToTips) {
      _listenToTips();
    } else {
      _completeInitialLoadIfNeeded();
    }
  }

  //constructor - this will get all tips from db for a specific tipper - less expensive and quicker db read
  TipsViewModel.forTipper(
    this.tipperViewModel,
    this.selectedDAUComp,
    this._gamesViewModel,
    this._tipper,
    {DatabaseReference? database, bool listenToTips = true,}
  ) : _db = database ?? FirebaseDatabase.instance.ref() {
    log('TipsViewModel.forTipper constructor for tipper ${_tipper!.dbkey}');
    _gamesViewModel.addListener(_update);
    if (listenToTips) {
      _listenToTips();
    } else {
      _completeInitialLoadIfNeeded();
    }
  }

  void _update() {
    notifyListeners(); //notify our consumers that the data may have changed to gamesViewModel.games data that we have a dependency on
  }

  void _listenToTips() {
    if (_tipper != null) {
      _tipsStream = _db
          .child('${p.tipsPathRoot}/${selectedDAUComp.dbkey}/${_tipper!.dbkey}')
          .onValue
          .listen((event) {
            _handleEvent(event);
          });
    } else {
      _tipsStream = _db
          .child('${p.tipsPathRoot}/${selectedDAUComp.dbkey}')
          .onValue
          .listen((event) {
            _handleEvent(event);
          });
    }
  }

  void _completeInitialLoadIfNeeded() {
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        if (_tipper == null) {
          final allTips = Map<String, dynamic>.from(
            event.snapshot.value as Map,
          );
          log(
            'TipsViewModel._handleEvent() All tippers - Deserialize tip for ${allTips.length} tippers.',
          );
          _listOfTips = await _deserializeTips(allTips);
        } else {
          log('_handleEvent deserializing tips for tipper ${_tipper!.dbkey}');
          final stopwatch = Stopwatch()..start();
          Map<String, dynamic> dbData = Map<String, dynamic>.from(
            event.snapshot.value as Map,
          );
          log(
            '_handleEvent (Tipper ${_tipper!.dbkey}) - number of tips to deserialize: ${dbData.length}',
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
              return Tip.fromJson(entryValue, tipEntry.key, _tipper!, game);
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
        }
      } else {
        log('TipsViewModel._handleEvent() No tips found in realtime database');
      }
    } finally {
      _crossCompTipCache.clear();
      if (!_initialLoadCompleter.isCompleted) {
        _completeInitialLoadIfNeeded();
        StartupProfiling.instant(
          'startup.tips_initial_load_complete',
          arguments: <String, Object?>{
            'tipperScoped': _tipper != null,
            'tipCount': _listOfTips.length,
          },
        );
      }
      notifyListeners();
    }
  }

  Future<List<Tip>> _deserializeTips(Map<String, dynamic> json) async {
    final stopwatch = Stopwatch()..start();
    List<Tip> allCompTips = [];

    int processedTippers = 0;
    for (var tipperEntry in json.entries) {
      // Yield control every 5 tippers to prevent UI blocking
      if (processedTippers % 5 == 0) {
        await Future.microtask(() {});
      }

      Tipper? tipper = await tipperViewModel.findTipper(tipperEntry.key);
      if (tipper != null) {
        Map<String, dynamic> tipperTips = Map<String, dynamic>.from(
          tipperEntry.value as Map,
        );
        for (var tipEntry in tipperTips.entries) {
          Game? game = await _gamesViewModel.findGame(tipEntry.key);
          if (game == null) {
            assert(game != null);
            log(
              'TipsViewModel._deserializeTips() Game not found for tip ${tipEntry.key}',
            );
          } else {
            //log('game found for tip ${tipEntry.key}'
            Tip tip = Tip.fromJson(tipEntry.value, tipEntry.key, tipper, game);
            allCompTips.add(tip);
          }
        }
      } else {
        // tipper does not exist - skip this record
        log('Tipper ${tipperEntry.key} does not exist in deserializeTips');
      }
      processedTippers++;
    }

    stopwatch.stop();
    log(
      '_deserializeTips completed in ${stopwatch.elapsedMilliseconds}ms for ${allCompTips.length} tips',
    );

    return await Future.wait(allCompTips.map((tip) => Future.value(tip)));
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

  Future<Tip?> findTip(Game game, Tipper tipper) async {
    await initialLoadCompleted;

    Tip? foundTip = _listOfTips.firstWhereOrNull(
      (tip) =>
          tip != null &&
          _matchesGame(tip.game, game) &&
          tip.tipper.dbkey == tipper.dbkey,
    );

    foundTip ??= _defaultTipIfGameStarted(game, tipper);

    return foundTip;
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

    final candidateComps =
        dauComps
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
        final cacheAge = DateTime.now().toUtc().difference(cachedEntry.cachedAtUtc);
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
      bool tipMatches = foundTip.tip == expectedTip.tip &&
          // Compare at second precision to accommodate compact epoch seconds storage
          (foundTip.submittedTimeUTC.millisecondsSinceEpoch ~/ 1000) ==
              (expectedTip.submittedTimeUTC.millisecondsSinceEpoch ~/ 1000);

      return !tipMatches; // Stop waiting when tips match
    });
  }

  //delete a tip
  Future<void> deleteTip(Tip tip) async {
    await _db
        .child(
          '${p.tipsPathRoot}/${selectedDAUComp.dbkey}/${tip.tipper.dbkey}/${tip.game.dbkey}',
        )
        .remove();
  }

  // returns true if the supplied tipper has submitted at least one tip for the comp
  Future<bool> hasSubmittedTips(Tipper tipper) async {
    await initialLoadCompleted;
    return _listOfTips.any((tip) => tip?.tipper.dbkey == tipper.dbkey);
  }

  int _numberOfTipsSubmittedForRoundAndLeague(DAURound round, League league) {
    return _listOfTips.where((tip) {
      // Attempt to get the round for the game, if it fails, return false
      return tip!.game.getDAURound(selectedDAUComp) == round &&
          tip.game.league == league;
    }).length;
  }

  int _numberOfTipsSubmittedForGames(Iterable<Game> games) {
    final gameDbKeys = games.map((game) => game.dbkey).toSet();
    return _listOfTips.where((tip) => tip != null && gameDbKeys.contains(tip.game.dbkey)).length;
  }

  // method to return count of outstanding tips for the supplied round and league
  int numberOfOutstandingTipsForRoundAndLeague(DAURound round, League league) {
    // Calculate the number of tips outstanding for this league round
    int totalGames = round.getGamesForLeague(league).length;
    int tipsSubmitted = _numberOfTipsSubmittedForRoundAndLeague(round, league);
    return totalGames - tipsSubmitted;
  }

  // Outstanding tips for games that have not started yet (includes startingSoon).
  int numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
    DAURound round,
    League league,
  ) {
    final gamesToTip = round.getGamesForLeague(league).where(
      (game) =>
          game.gameState == GameState.notStarted ||
          game.gameState == GameState.startingSoon,
    );
    final tipsSubmitted = _numberOfTipsSubmittedForGames(gamesToTip);
    final outstanding = gamesToTip.length - tipsSubmitted;
    return outstanding > 0 ? outstanding : 0;
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

  Future<GameStatsEntry> percentageOfTippersTipped(Game game) async {
    // throw an exception if the tipper is not null
    if (_tipper != null) {
      throw Exception(
        'percentageOfTippersTipped() should not be called when doing aggregates for scoring. _tipper is not null',
      );
    }
    // get the paidForComp status for the selected tipper
    bool isScoringPaidComp = false;
    isScoringPaidComp = di<TippersViewModel>().selectedTipper.paidForComp(
      selectedDAUComp,
    );

    // loop through all tippers and remove those that don't have the same paidForComp status
    List<Tipper> tippers = tipperViewModel.tippers
        .where(
          (tipper) => tipper.paidForComp(selectedDAUComp) == isScoringPaidComp,
        )
        .toList();

    double runningAverageScoreTotal = 0.0;
    int runningAverageScoreCountTips = 0;
    GameStatsEntry gameStatsEntry = GameStatsEntry(
      percentageTippedHomeMargin: 0.0,
      percentageTippedHome: 0.0,
      percentageTippedDraw: 0.0,
      percentageTippedAway: 0.0,
      percentageTippedAwayMargin: 0.0,
    );

    // enumerate each game result and do the calculation
    for (GameResult gameResult in GameResult.values) {
      // now do the calculation
      int totalTippers = tippers.length;
      int totalTippersTipped = 0;

      // Collect all the futures
      List<Future<void>> futures = tippers.map((tipper) async {
        Tip? tip = await findTip(game, tipper);
        if (tip?.tip == gameResult) {
          totalTippersTipped++;
        }
        // add this tip to the running average
        runningAverageScoreCountTips++;
        runningAverageScoreTotal += tip?.getTipScoreCalculated() ?? 0;
      }).toList();

      // Wait for all futures to complete
      await Future.wait(futures);

      // switch on the game result and set the correct value
      switch (gameResult) {
        case GameResult.a:
          gameStatsEntry.percentageTippedHomeMargin = gameStatsEntry
              .reducePrecision(totalTippersTipped / totalTippers);
          break;
        case GameResult.b:
          gameStatsEntry.percentageTippedHome = gameStatsEntry.reducePrecision(
            totalTippersTipped / totalTippers,
          );
          break;
        case GameResult.c:
          gameStatsEntry.percentageTippedDraw = gameStatsEntry.reducePrecision(
            totalTippersTipped / totalTippers,
          );
          break;
        case GameResult.d:
          gameStatsEntry.percentageTippedAway = gameStatsEntry.reducePrecision(
            totalTippersTipped / totalTippers,
          );
          break;
        case GameResult.e:
          gameStatsEntry.percentageTippedAwayMargin = gameStatsEntry
              .reducePrecision(totalTippersTipped / totalTippers);
          break;
        case GameResult.z:
          break;
      }
    }
    // calculate the average score across all tippers for this game
    if (runningAverageScoreCountTips > 0) {
      gameStatsEntry.averageScore = gameStatsEntry.reducePrecision(
        runningAverageScoreTotal / runningAverageScoreCountTips,
      );
    } else {
      gameStatsEntry.averageScore = 0.0;
    }
    return gameStatsEntry;
  }

  List<Tip?> getTipsForTipper(Tipper tipper) {
    return _listOfTips
        .where((tip) => tip!.tipper.dbkey == tipper.dbkey)
        .toList();
  }

  Future<void> updateTip(Tip tip) async {
    await _db
        .child(
          '${p.tipsPathRoot}/${selectedDAUComp.dbkey}/${tip.tipper.dbkey}/${tip.game.dbkey}',
        )
        .update(tip.toJson());
  }

  @override
  void dispose() {
    _tipsStream?.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(_update);
    super.dispose();
  }

  @visibleForTesting
  void setTipsForTest(List<Tip?> tips) {
    _listOfTips = List<Tip?>.from(tips);
    _completeInitialLoadIfNeeded();
  }

  Future<void> deleteAllTipsForTipper(Tipper originalTipper) async {
    try {
      await _db
          .child(
            '${p.tipsPathRoot}/${selectedDAUComp.dbkey}/${originalTipper.dbkey}',
          )
          .remove();
    } catch (e) {
      log('Error deleting all tips for tipper ${originalTipper.dbkey}');
    }
  }
}
