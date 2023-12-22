import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const tipsPathRoot = '/Tips';

class GameTipsViewModel extends ChangeNotifier {
  List<Tip> _tips = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;
  bool _savingTip = false;

  late GamesViewModel _gamesViewModel;
  final String parentDAUCompDBkey;
  final Game game;
  final Completer<void> _initialLoadCompleter = Completer();

  List<Tip> get tips => _tips;
  List<Game> get games => _gamesViewModel.games;
  bool get savingTip => _savingTip;
  GamesViewModel get gamesViewModel => _gamesViewModel;
  Tipper currentTipper;
  final Map<String, Tip?> _gameTipsCache = {};

  //constructor
  GameTipsViewModel(this.currentTipper, this.parentDAUCompDBkey, this.game) {
    _gamesViewModel = GamesViewModel(parentDAUCompDBkey);
    _gamesViewModel.addListener(
        update); //listen for changes to _gamesViewModel so that we can notify our consumers that the data, we rely on, may have changed
    _listenToTips();
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToTips() async {
    _tipsStream = _db
        .child(
            '$tipsPathRoot/$parentDAUCompDBkey/${currentTipper.dbkey}/${game.dbkey}')
        .onValue
        .listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    if (event.snapshot.exists) {
      final allTips =
          deepMapFromObject(event.snapshot.value as Map<Object?, Object?>);

      _tips = await deserializeTips(allTips, currentTipper);
      _tips.sort();
    } else {
      log('No tips found for Tipper ${currentTipper.name} in game ${game.dbkey}');
    }
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    notifyListeners();
  }

  Map<String, dynamic> deepMapFromObject(Map<Object?, Object?> map) {
    return Map<String, dynamic>.from(map.map((key, value) {
      if (value is Map<Object?, Object?>) {
        return MapEntry(key.toString(), deepMapFromObject(value));
      } else {
        return MapEntry(key.toString(), value);
      }
    }));
  }

  Future<List<Tip>> deserializeTips(Map<String, dynamic> json, tipper) async {
    List<Future<Tip>> futureTips = [];
    Tipper futureTipper =
        await tipper; //its important we wait for the tipper to be resolved before we attempt to deserailise any tips in this function

    futureTips.addAll(json.entries.map((entry) async {
      String key = entry.key;
      Map<String, dynamic> data = entry.value;

      return Tip.fromJson(data, key, futureTipper, game);
    }));
    //}

    return await Future.wait(futureTips);
  }

  void addTip(Tip tip) async {
    try {
      _savingTip = true;

      // create a json representation of the tip
      final tipJson = await tip.toJson();

      //get a unique db key for this tip
      final newTipKey = _db
          .child(
              '$tipsPathRoot/$parentDAUCompDBkey/${tip.tipper.dbkey}/${tip.game.dbkey}')
          .push()
          .key;

      final Map<String, Map> updates = {};
      updates['$tipsPathRoot/$parentDAUCompDBkey/${tip.tipper.dbkey}/${tip.game.dbkey}/$newTipKey'] =
          tipJson;
      _db.update(updates);
      log('new tip logged: ${updates.toString()}');

      //invalidate any cache version
      _gameTipsCache.removeWhere((key, value) => key == tip.game.dbkey);

      await FirebaseAnalytics.instance
          .logEvent(name: 'tip_submitted', parameters: {
        'tipper': tip.tipper.name,
        'comp': parentDAUCompDBkey,
        'game':
            'Round: ${tip.game.combinedRoundNumber}, ${tip.game.homeTeam} v ${tip.game.awayTeam}',
        'tip': tip.tip.toString(),
        'submittedTimeUTC': tip.submittedTimeUTC.toString(),
      });
    } finally {
      _savingTip = false;
    }
  }

  Future<Tip?> getLatestGameTip() async {
    if (!_gameTipsCache.containsKey(game.dbkey)) {
      _gameTipsCache[game.dbkey] = await getLatestGameTipFromDb();
    }
    return _gameTipsCache[game.dbkey];
  }

  Future<Tip?> getLatestGameTipFromDb() async {
    await _initialLoadCompleter.future;
    log('tips load complete, getLatestGameTip(${game.dbkey})');
    Tip? foundTip =
        _tips.lastWhereOrNull((tip) => tip.game.dbkey == game.dbkey);
    if (foundTip != null) {
      log('found tip ${foundTip.tip} for game ${game.dbkey} (${game.homeTeam.name} v ${game.awayTeam.name}  )');
      return foundTip;
    } else {
      if (game.gameState == GameState.notStarted) {
        return null; //game has not started yet, so assign a null tip
      } else {
        return Tip(
            tip: GameResult
                .d, //if the game is in the past and there is no tip from Tipper, then default to a Away win
            submittedTimeUTC: DateTime.fromMicrosecondsSinceEpoch(0,
                isUtc:
                    true), //set the submitted time to the epoch to indicate that this is a default tip
            game: game,
            tipper: currentTipper);
      }
    }
  }

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(update);
    super.dispose();
  }
}
