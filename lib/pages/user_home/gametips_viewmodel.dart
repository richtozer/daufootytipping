import 'dart:async';
import 'dart:developer';
import 'package:carousel_slider/carousel_controller.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class GameTipsViewModel extends ChangeNotifier {
  TipGame? _tipGame;

  TipGame? get tipGame => _tipGame;

  //late ScoresViewModel scoresViewModel;
  AllTipsViewModel allTipsViewModel;
  Tipper currentTipper;
  final String currentDAUComp;
  final Game game;

  final _db = FirebaseDatabase.instance.ref();

  bool _savingTip = false;
  bool get savingTip => _savingTip;

  final Completer<void> _initialLoadCompleter = Completer();
  Future<bool> get initialLoadCompleted async =>
      _initialLoadCompleter.isCompleted;

  LegacyTippingService legcyTippingService =
      GetIt.instance<LegacyTippingService>();

  int currentIndex = 0;

  final CarouselController _controller = CarouselController();
  get controller => _controller;

  //constructor
  GameTipsViewModel(
    this.currentTipper,
    this.currentDAUComp,
    this.game,
    this.allTipsViewModel,
  ) {
    //scoresViewModel = di<ScoresViewModel>();
    allTipsViewModel.addListener(update);
    allTipsViewModel.gamesViewModel.addListener(update);
    //scoresViewModel.addListener(update);

    _findTip();
    gameStartedTrigger();
  }

  // this method will delay returning until the game has started,
  // then use notifiyListeners to trigger the UI to update
  void gameStartedTrigger() async {
    // if the game has already started, then we don't need to wait , just return
    if ((game.gameState == GameState.resultNotKnown ||
        game.gameState == GameState.resultKnown)) {
      notifyListeners();
      return;
    }

    // calculate the time until the game starts and create a future.delayed
    // to wait until the game starts
    var timeUntilGameStarts =
        game.startTimeUTC.difference(DateTime.now().toUtc());
    await Future.delayed(timeUntilGameStarts);

    // now that the game has started, trigger the UI to update
    notifyListeners();
  }

  void update() {
    // we may have new data lets check if we need to update our tip
    _findTip();
  }

  void _findTip() async {
    await allTipsViewModel.initialLoadCompleted;

    _tipGame = await allTipsViewModel.findTip(game, currentTipper);

    // flag our intial load as complete
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    notifyListeners();
  }

  Future<TipGame?> gettip() async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }

    return _tipGame;
  }

  void addTip(
      List<Game> roundGames, TipGame tip, int combinedRoundNumber) async {
    try {
      assert(_initialLoadCompleter.isCompleted,
          'GameTipsViewModel.addTip() called before initial load completed');

      _savingTip = true;

      // create a json representation of the tip
      final tipJson = await tip.toJson();

      final Map<String, Map> updates = {};
      updates['$tipsPathRoot/$currentDAUComp/${tip.tipper.dbkey}/${tip.game.dbkey}'] =
          tipJson;
      await _db.update(updates);
      log('new tip logged: ${updates.toString()}');

      _tipGame = tip; // update the tipGame with the new tip

      // code section to support legacy tipping service
      // find the Tip game position in the roundGames list
      // int gameIndex =
      //     roundGames.indexWhere((game) => game.dbkey == tip.game.dbkey);

      // legcyTippingService.submitTip(
      //     currentTipper.name, tip, gameIndex, combinedRoundNumber);
    } catch (e) {
      // rethrow exception so that the UI can handle it
      rethrow;
    } finally {
      notifyListeners();
      _savingTip = false;
    }
  }

  @override
  void dispose() {
    allTipsViewModel.removeListener(update);
    allTipsViewModel.gamesViewModel.removeListener(update);
    //scoresViewModel.removeListener(update);
    super.dispose();
  }
}
