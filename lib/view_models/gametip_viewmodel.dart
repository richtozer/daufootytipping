import 'dart:async';
import 'dart:developer';
import 'package:carousel_slider/carousel_controller.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class GameTipViewModel extends ChangeNotifier {
  Tip? _tip;

  Tip? get tip => _tip;

  TipsViewModel allTipsViewModel;
  Tipper currentTipper;
  final String _currentDAUCompDbkey;
  Game game;
  GameState? _gameState;
  GameState get gameState => _gameState!;
  final DAURound _dauRound;

  int? _homeTeamScore;
  int? get homeTeamScore => _homeTeamScore;
  int? _awayTeamScore;
  int? get awayTeamScore => _awayTeamScore;

  final _db = FirebaseDatabase.instance.ref();

  bool _savingTip = false;
  bool get savingTip => _savingTip;

  final Completer<void> _initialLoadCompleter = Completer();
  Future<bool> get initialLoadCompleted async =>
      _initialLoadCompleter.isCompleted;

  int currentIndex = 0;

  final CarouselSliderController _controller = CarouselSliderController();
  get controller => _controller;

  //constructor
  GameTipViewModel(
    this.currentTipper,
    this._currentDAUCompDbkey,
    this.game,
    this.allTipsViewModel,
    this._dauRound,
  ) {
    _gameState = game.gameState;
    allTipsViewModel.addListener(_tipsUpdated);
    allTipsViewModel.gamesViewModel.addListener(_gamesViewModelUpdated);

    _findTip();
    _gameStartedTrigger();
  }

  // this method will delay returning until the game has started,
  // then use notifiyListeners to trigger the UI to update
  void _gameStartedTrigger() async {
    // if the game has already started, then we don't need to wait , just return
    if ((game.gameState == GameState.startedResultNotKnown ||
        game.gameState == GameState.startedResultKnown)) {
      notifyListeners();
      return;
    }

    // calculate the time until the game starts and create a future.delayed
    // to wait until the game starts
    var timeUntilGameStarts =
        game.startTimeUTC.difference(DateTime.now().toUtc());

    // wait for the game to start before updating the UI
    await Future.delayed(timeUntilGameStarts);

    // now that the game has started, trigger the UI to update
    notifyListeners();
  }

  void _tipsUpdated() async {
    // we may have new data lets check if we need to update our tip
    _tip = (await allTipsViewModel.findTip(game, currentTipper));
    log('GameTipsViewModel._tipsUpdated() called. TEST - DONT Notify listeners');
    notifyListeners();
  }

  void _gamesViewModelUpdated() async {
    // we may have new game data, notify listeners
    game = (await allTipsViewModel.gamesViewModel.findGame(game.dbkey))!;
    log('GameTipsViewModel._gamesViewModelUpdated() called for game ${game.homeTeam.name} v ${game.awayTeam.name}, ${game.gameState}. Notify listeners');

    _gameState = game.gameState;
    _homeTeamScore = game.scoring?.currentScore(ScoringTeam.home);
    _awayTeamScore = game.scoring?.currentScore(ScoringTeam.away);

    notifyListeners();
  }

  void _findTip() async {
    await allTipsViewModel.initialLoadCompleted;

    _tip = await allTipsViewModel.findTip(game, currentTipper);

    // flag our intial load as complete
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    notifyListeners();
  }

  Future<Tip?> gettip() async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }

    return _tip;
  }

  void addTip(List<Game> roundGames, Tip tip) async {
    try {
      assert(_initialLoadCompleter.isCompleted,
          'GameTipsViewModel.addTip() called before initial load completed');

      _savingTip = true;
      notifyListeners();

      // remember the tip prior to the update
      final Tip? oldTip = _tip;

      // create a json representation of the tip
      final tipJson = await tip.toJson();

      final Map<String, Map> updates = {};
      updates['$tipsPathRoot/$_currentDAUCompDbkey/${tip.tipper.dbkey}/${tip.game.dbkey}'] =
          tipJson;
      await _db.update(updates);
      log('new tip submitted: ${updates.toString()}');

      _tip = tip; // update the tip with the new tip

      // update the margin counts.
      await di<StatsViewModel>()
          .updateMarginsAsResultOfTip(tip, oldTip, _dauRound);
    } catch (e) {
      // rethrow exception so that the UI can handle it
      rethrow;
    } finally {
      _savingTip = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    allTipsViewModel.removeListener(_tipsUpdated);
    allTipsViewModel.gamesViewModel.removeListener(_tipsUpdated);
    super.dispose();
  }
}
