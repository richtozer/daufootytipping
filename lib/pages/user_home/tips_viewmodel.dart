import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const tipsPathRoot = '/AllTips';

class TipsViewModel extends ChangeNotifier {
  List<Tip> _tips = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;
  final bool _savingTip = false;

  late GamesViewModel _gamesViewModel;
  final String parentDAUCompDBkey;
  final Completer<void> _initialLoadCompleter = Completer();

  List<Tip> get tips => _tips;
  List<Game> get games => _gamesViewModel.games;
  bool get savingTip => _savingTip;
  GamesViewModel get gamesViewModel => _gamesViewModel;
  Tipper currentTipper;
  final Map<String, Tip?> _gameTipsCache = {};

  //constructor
  TipsViewModel(this.currentTipper, this.parentDAUCompDBkey) {
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
        .child('$tipsPathRoot/$parentDAUCompDBkey/${currentTipper.dbkey}')
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
      log('No tips found for Tipper ${currentTipper.name}');
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

    for (var entry in json.entries) {
      String gameKey = entry.key;
      Map<String, dynamic> tipData = entry.value;

      futureTips.addAll(tipData.entries.map((entry) async {
        String key = entry.key;
        Map<String, dynamic> data = entry.value;

        Game? game = await _gamesViewModel.findGame(gameKey);
        assert(game != null);
        return Tip.fromJson(data, key, futureTipper, game!);
      }));
    }

    return await Future.wait(futureTips);
  }

  Future<Tip?> getLatestGameTip(Game game) async {
    if (!_gameTipsCache.containsKey(game.dbkey)) {
      _gameTipsCache[game.dbkey] = await getLatestGameTipFromDb(game);
    }
    return _gameTipsCache[game.dbkey];
  }

  Future<Tip?> getLatestGameTipFromDb(Game game) async {
    await _initialLoadCompleter.future;
    log('tips load complete, TipsViewModel.getLatestGameTipFromDb(${game.dbkey})');
    Tip? foundTip =
        _tips.lastWhereOrNull((tip) => tip.game.dbkey == game.dbkey);
    if (foundTip != null) {
      log('found tip ${foundTip.tip} for game ${game.dbkey} (${game.homeTeam.name} v ${game.awayTeam.name}, TipsViewModel.getLatestGameTipFromDb()');
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

  Future<int> countTipsLodgedForRound(int combinedRound) async {
    if (_initialLoadCompleter.isCompleted) {
      log('tips load already complete, countTipsOutstanding(combinedRound: $combinedRound)');
    } else {
      log('Waiting for initial Tip load to complete, countTipsOutstanding(combinedRound: $combinedRound)');
      await _initialLoadCompleter.future;
    }

    int tipsLodged = 0;

    List<Game>? combinedRoundGames = games
        .where((game) => game.combinedRoundNumber == combinedRound)
        .toList();
    for (var game in combinedRoundGames) {
      //count the number of tips lodged for this combined round
      await getLatestGameTip(game).then((tip) {
        if (tip != null) {
          tipsLodged++;
        }
      });
    }
    log(' $tipsLodged tips Lodged for combinedround $combinedRound');

    return Future<int>.value(tipsLodged);
  }

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(update);
    super.dispose();
  }
}
