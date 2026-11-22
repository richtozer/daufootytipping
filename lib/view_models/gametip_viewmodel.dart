import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/services/unconfirmed_tips_service.dart';
import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:daufootytipping/services/tipping_deadline.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

typedef TipAnalyticsLogger = Future<void> Function(
  String name,
  Map<String, Object> parameters,
);

typedef TipLogWriter = Future<void> Function(Tip tip);

// Helper class to structure historical matchup data for the UI
class HistoricalMatchupUIData {
  final String year;
  final String month;
  final String winningTeamName;
  final String winType; // "Home" or "Away" or "Draw"
  final String userTipTeamName;
  final bool isCurrentYear;
  final Game
  pastGame; // Keep a reference to the original game if needed for more details
  final String location; // New field

  HistoricalMatchupUIData({
    required this.year,
    required this.month,
    required this.winningTeamName,
    required this.winType,
    required this.userTipTeamName,
    required this.isCurrentYear,
    required this.pastGame,
    required this.location, // Added to constructor
  });
}

class GameTipViewModel extends ChangeNotifier {
  Tip? _tip;

  Tip? get tip => _tip;

  TipsViewModel allTipsViewModel;
  Tipper currentTipper;
  final DAUComp _currentDAUComp;
  Game game;

  int? _homeTeamScore;
  int? get homeTeamScore => _homeTeamScore;
  int? _awayTeamScore;
  int? get awayTeamScore => _awayTeamScore;
  late GameState _gameState;

  final DatabaseReference _db;
  final TipAnalyticsLogger _logAnalyticsEvent;
  final TipLogWriter? _writeTipLog;
  final Duration _writeAcknowledgementLimit;
  final UnconfirmedTipsService? _unconfirmedTips;
  bool _disposed = false;
  Timer? _tipDeadlineTimer;
  ConfigViewModel? _deadlineConfig;

  void _scheduleTipDeadline() {
    _tipDeadlineTimer?.cancel();
    final remaining = tippingDeadline(game.startTimeUTC)
        .difference(tippingNow());
    if (remaining > Duration.zero) {
      _tipDeadlineTimer = Timer(remaining, _notifyListenersIfAlive);
    }
    _notifyListenersIfAlive();
  }

  late final bool _listensToGamesViewModel;

  bool _savingTip = false;
  bool get savingTip => _savingTip;

  final Completer<void> _initialLoadCompleter = Completer();
  Future<bool> get initialLoadCompleted async =>
      _initialLoadCompleter.isCompleted;

  //constructor
  GameTipViewModel(
    this.currentTipper,
    this._currentDAUComp,
    this.game,
    this.allTipsViewModel, {
    DatabaseReference? database,
    TipAnalyticsLogger? logAnalyticsEvent,
    TipLogWriter? writeTipLog,
    Duration writeAcknowledgementLimit = defaultWriteAcknowledgementLimit,
    UnconfirmedTipsService? unconfirmedTips,
  }) : _db = database ?? configuredDatabaseRef(),
       _logAnalyticsEvent = logAnalyticsEvent ?? _defaultLogAnalyticsEvent,
       _writeTipLog = writeTipLog,
       _writeAcknowledgementLimit = writeAcknowledgementLimit,
       _unconfirmedTips = unconfirmedTips {
    _homeTeamScore = game.scoring?.currentScore(ScoringTeam.home);
    _awayTeamScore = game.scoring?.currentScore(ScoringTeam.away);
    _gameState = game.gameState;
    _listensToGamesViewModel =
        _currentDAUComp.latestsCompletedRoundNumber() <
        _currentDAUComp.daurounds.length;
    allTipsViewModel.addListener(_tipsUpdated); // Restored listener for tips
    // only monitor gamesViewModel if the comp still has active rounds
    if (_listensToGamesViewModel) {
      allTipsViewModel.gamesViewModel.addListener(_gamesViewModelUpdated);
    } else {
      log(
        'GameTipsViewModel constructor: ${_currentDAUComp.name} has no active rounds. Not listening to gamesViewModel',
      );
    }

    _findTip();
    _gameStartedTrigger();
    if (di.isRegistered<ConfigViewModel>()) {
      _deadlineConfig = di<ConfigViewModel>();
      _deadlineConfig!.addListener(_scheduleTipDeadline);
    }
    _scheduleTipDeadline();
  }

  // this method will delay returning until the game has started,
  // then use notifyListeners to trigger the UI to update
  void _gameStartedTrigger() async {
    // if the game has already started, then we don't need to wait , just return
    if ((game.gameState == GameState.startedResultNotKnown ||
        game.gameState == GameState.startedResultKnown)) {
      return;
    }

    // calculate the time until the game starts and create a future.delayed
    // to wait until the game starts
    var timeUntilGameStarts = game.startTimeUTC.difference(
      DateTime.now().toUtc(),
    );

    // wait for the game to start before updating the UI
    await Future.delayed(timeUntilGameStarts);

    if (_disposed) {
      return;
    }

    // now that the game has started, trigger the UI to update
    log(
      'GameTipsViewModel._gameStartedTrigger()  Notify listeners called for game ${game.homeTeam.name} v ${game.awayTeam.name}, ${game.gameState}.',
    );
    _notifyListenersIfAlive();
  }

  void _tipsUpdated() async {
    // we may have new data lets check if we need to update our tip
    Tip? newTip = (await allTipsViewModel.findTip(game, currentTipper));
    if (_disposed) {
      return;
    }
    // if the tip has changed, then update the tip and notify listeners
    if (!_isEquivalentTip(newTip, _tip)) {
      _tip = newTip;
      _syncTipGameScoring();
      log(
        'GameTipsViewModel._tipsUpdated() Notify listeners called for game ${game.homeTeam.name} v ${game.awayTeam.name}, ${game.gameState}. ',
      );
      _notifyListenersIfAlive();
    }
  }

  bool _isEquivalentTip(Tip? a, Tip? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return a == b;
    }

    return a.game.dbkey == b.game.dbkey &&
        a.tipper.dbkey == b.tipper.dbkey &&
        a.tip == b.tip &&
        (a.submittedTimeUTC.millisecondsSinceEpoch ~/ 1000) ==
            (b.submittedTimeUTC.millisecondsSinceEpoch ~/ 1000);
  }

  void _gamesViewModelUpdated() async {
    final previousHomeScore = _homeTeamScore;
    final previousAwayScore = _awayTeamScore;
    final previousGameState = _gameState;

    final previousKickoff = game.startTimeUTC;
    game = (await allTipsViewModel.gamesViewModel.findGame(game.dbkey))!;
    if (_disposed) {
      return;
    }
    if (game.startTimeUTC != previousKickoff) {
      // The fixture was moved: tipping now closes at a different time.
      _scheduleTipDeadline();
    }
    _tip?.game.scoring = game.scoring; //update the tip scoring

    _homeTeamScore = game.scoring?.currentScore(ScoringTeam.home);
    _awayTeamScore = game.scoring?.currentScore(ScoringTeam.away);
    _gameState = game.gameState;

    final scoresChanged =
        previousHomeScore != _homeTeamScore ||
        previousAwayScore != _awayTeamScore;
    final gameStateChanged = previousGameState != game.gameState;

    if (!scoresChanged && !gameStateChanged) {
      log(
        'GameTipsViewModel._gamesViewModelUpdated() no-op for game ${game.dbkey}; scores and state unchanged.',
      );
      return;
    }

    log(
      'GameTipsViewModel._gamesViewModelUpdated() called for game ${game.dbkey}, ${game.gameState}. Notify listeners',
    );
    _notifyListenersIfAlive();
  }

  void _findTip() async {
    await allTipsViewModel.initialLoadCompleted;
    if (_disposed) {
      return;
    }

    _tip = await allTipsViewModel.findTip(game, currentTipper);
    if (_disposed) {
      return;
    }
    _syncTipGameScoring();

    // flag our initial load as complete
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    _notifyListenersIfAlive();
  }

  void _syncTipGameScoring() {
    _tip?.game.scoring = game.scoring;
  }

  Future<Tip?> getTip() async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }

    return _tip;
  }

  Future<void> addTip(Tip tip) async {
    try {
      assert(
        _initialLoadCompleter.isCompleted,
        'GameTipsViewModel.addTip() called before initial load completed',
      );

      _savingTip = true;
      _notifyListenersIfAlive();

      // create a json representation of the tip
      final tipJson = tip.toJson();

      final Map<String, Map> updates = {};
      updates['${p.tipsPathRoot}/${_currentDAUComp.dbkey}/${tip.tipper.dbkey}/${tip.game.dbkey}'] =
          tipJson;
      final UnconfirmedTipsService? unconfirmedTips = _unconfirmedTipsService();
      final UnconfirmedTip unconfirmed = _unconfirmedRecord(tip);
      // Kept on the device before the write is handed to the database, not
      // after the wait: the database holds a write it cannot send across a
      // restart, and if the app closes before the screen stops waiting, this is
      // the only record that a tip is outstanding.
      await unconfirmedTips?.queued(unconfirmed);
      final Future<void> write = _db.update(updates);
      final WriteAcknowledgement acknowledgement;
      try {
        acknowledgement = await awaitAcknowledgement(
          write,
          limit: _writeAcknowledgementLimit,
          onLateError: (Object error, StackTrace stackTrace) {
            log(
              'GameTipsViewModel.addTip() queued tip was rejected: $error',
              error: error,
              stackTrace: stackTrace,
            );
            // The screen has stopped waiting, so this is the only way the user
            // hears that the tip did not count.
            unawaited(unconfirmedTips?.rejected(unconfirmed));
          },
        );
      } on Object {
        // Refused while the screen was still waiting: the screen reports it.
        await unconfirmedTips?.answered(unconfirmed);
        rethrow;
      }
      if (acknowledgement == WriteAcknowledgement.stillPending) {
        // The database keeps the write and sends it when the connection
        // recovers. The record stays on the device, so that a rejection or a
        // closed app is still reported; the Firestore record of the tip waits
        // for the write to be sent.
        unawaited(
          write.then<void>((_) async {
            await unconfirmedTips?.answered(unconfirmed);
            await (_writeTipLog ?? _addLogOfTipToFirestore)(tip);
          }, onError: (Object _) {}),
        );
        log('GameTipsViewModel.addTip() tip not confirmed within the limit');
        throw const WriteNotConfirmedException('tip submission');
      }
      await unconfirmedTips?.answered(unconfirmed);
      log('new tip submitted: ${updates.toString()}');

      _tip = tip; // update the tip with the new tip

      // write a firebase analytic event that a tip was submitted
      await _logAnalyticsEvent('tip_submitted', {
        'game': tip.game.dbkey,
        'tipper': tip.tipper.name.toString(),
        'tip': tipJson.toString(),
        'submittedBy': currentTipper.name.toString(),
      });

      // Log the tip in Firestore
      unawaited((_writeTipLog ?? _addLogOfTipToFirestore)(tip));

      // Wait for the database change event to update the in-memory cache
      // This ensures stats calculations use current data, not stale cache
      await allTipsViewModel.waitForTipUpdate(tip);
      final selectedTipperTipsViewModel =
          di<DAUCompsViewModel>().selectedTipperTipsViewModel;
      if (selectedTipperTipsViewModel != null &&
          !identical(selectedTipperTipsViewModel, allTipsViewModel)) {
        await selectedTipperTipsViewModel.waitForTipUpdate(tip);
      }

      // if we are in god mode, then also do a gamestats update after main stats complete
      if (di<TippersViewModel>().inGodMode == true) {
        di<StatsViewModel>().getGamesStatsEntry(game, true);
      }
    } catch (e) {
      log('GameTipsViewModel.addTip() error: $e');
      // rethrow exception so that the UI can handle it
      rethrow;
    } finally {
      _savingTip = false;
      _notifyListenersIfAlive();
    }
  }

  UnconfirmedTipsService? _unconfirmedTipsService() =>
      _unconfirmedTips ??
      (di.isRegistered<UnconfirmedTipsService>()
          ? di<UnconfirmedTipsService>()
          : null);

  UnconfirmedTip _unconfirmedRecord(Tip tip) => UnconfirmedTip(
    compKey: _currentDAUComp.dbkey ?? '',
    tipperKey: tip.tipper.dbkey ?? '',
    gameKey: tip.game.dbkey,
    choice: tip.tip.name,
    submittedUtcSeconds: tip.submittedTimeUTC.millisecondsSinceEpoch ~/ 1000,
    gameLabel: '${tip.game.homeTeam.name} v ${tip.game.awayTeam.name}',
    deadlineUtcMs: tippingDeadline(tip.game.startTimeUTC)
        .toUtc()
        .millisecondsSinceEpoch,
    queuedAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
  );

  void _notifyListenersIfAlive() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  Future<void> _addLogOfTipToFirestore(Tip tip) async {
    final seasonYear = tip.game.startTimeUTC.year;
    final round = tip.game.getDAURound(_currentDAUComp)?.dAUroundNumber;
    final tipperId = tip.tipper.dbkey;
    final gameId = tip.game.dbkey;
    final submittedAtUTC = DateTime.now().toUtc();
    final submittedAtIsoUTC = submittedAtUTC.toIso8601String();
    final gameStartTimeUTC = tip.game.startTimeUTC.toUtc();

    final PackageInfoService packageInfoService = di<PackageInfoService>();
    final packageInfo = await packageInfoService.packageInfo;
    final submittedBy = di<TippersViewModel>().authenticatedTipper;
    final tipValue = tip.game.league == League.afl ? tip.tip.afl : tip.tip.nrl;

    // Log the tip in Firestore
    try {
      await FirebaseFirestore.instance.collection('tipLogs2').add({
        'createdAt': FieldValue.serverTimestamp(),
        'submittedAtUTC': Timestamp.fromDate(submittedAtUTC),
        'submittedAtIsoUTC': submittedAtIsoUTC,
        'seasonYear': seasonYear,
        'round': round,
        'compId': _currentDAUComp.dbkey,
        'compName': _currentDAUComp.name,
        'tipperId': tipperId,
        'tipperName': tip.tipper.name,
        'gameId': gameId,
        'league': tip.game.league.name,
        'homeTeam': tip.game.homeTeam.name,
        'awayTeam': tip.game.awayTeam.name,
        'gameStartTimeUTC': Timestamp.fromDate(gameStartTimeUTC),
        'gameStartTimeIsoUTC': gameStartTimeUTC.toIso8601String(),
        'tipResult': tip.tip.name,
        'tip': tipValue,
        'submittedByTipperId': submittedBy?.dbkey,
        'submittedBy': submittedBy?.name,
        'appVersion': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
        'installTimeUTC': packageInfo.installTime == null
            ? null
            : Timestamp.fromDate(packageInfo.installTime!.toUtc()),
        'lastUpdateTimeUTC': packageInfo.updateTime == null
            ? null
            : Timestamp.fromDate(packageInfo.updateTime!.toUtc()),
        'platform': UniversalPlatform.operatingSystem,
      });

      log(
        '_addLogOfTipToFirestore() Tip logged in Firestore for tipper: ${tip.tipper.name}, game: ${tip.game.dbkey}, timestamp: $submittedAtIsoUTC',
      );
    } catch (e) {
      log('Error logging tip in Firestore: $e');
    }
  }

  static Future<void> _defaultLogAnalyticsEvent(
    String name,
    Map<String, Object> parameters,
  ) {
    return FirebaseAnalytics.instance.logEvent(
      name: name,
      parameters: parameters,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _tipDeadlineTimer?.cancel();
    _deadlineConfig?.removeListener(_scheduleTipDeadline);
    if (_listensToGamesViewModel) {
      allTipsViewModel.gamesViewModel.removeListener(_gamesViewModelUpdated);
    }
    allTipsViewModel.removeListener(_tipsUpdated);
    super.dispose();
  }
}
