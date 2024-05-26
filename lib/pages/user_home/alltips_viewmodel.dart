import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const tipsPathRoot = '/AllTips';

class TipsViewModel extends ChangeNotifier {
  List<TipGame?> _tipGames = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;

  late final GamesViewModel _gamesViewModel;
  final String currentDAUCompDbKey;
  final Completer<void> _initialLoadCompleter = Completer();

  Future<void> get initialLoadCompleted async => _initialLoadCompleter.future;

  Tipper?
      tipper; // if this is supplied in the constructor, then we are only interested in the tips for this tipper

  //List<Tip> get tips => _tips;
  //List<Game> get games => _gamesViewModel.games;
  GamesViewModel get gamesViewModel => _gamesViewModel;

  late final TippersViewModel tipperViewModel;

  //constructor - this will get all tips from db
  TipsViewModel(
      this.tipperViewModel, this.currentDAUCompDbKey, this._gamesViewModel) {
    log('TipsViewModel constructor');
    _gamesViewModel.addListener(
        update); //listen for changes to _gamesViewModel so that we can notify our consumers that the data, we rely on, may have changed
    _listenToTips();
  }

  //constructor - this will get all tips from db for a specific tipper - less expensive and quicker db read
  TipsViewModel.forTipper(this.tipperViewModel, this.currentDAUCompDbKey,
      this._gamesViewModel, this.tipper) {
    _gamesViewModel.addListener(
        update); //listen for changes to _gamesViewModel so that we can notify our consumers that the data, we rely on, may have changed
    _listenToTips();
  }

  Future<List<TipGame?>> getAllTips() async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }
    return _tipGames;
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToTips() async {
    if (tipper != null) {
      _tipsStream = _db
          .child('$tipsPathRoot/$currentDAUCompDbKey/${tipper!.dbkey}')
          .onValue
          .listen((event) {
        _handleEvent(event);
      });
    } else {
      _tipsStream = _db
          .child('$tipsPathRoot/$currentDAUCompDbKey')
          .onValue
          .listen((event) {
        _handleEvent(event);
      });
    }
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        if (tipper == null) {
          log('deserializing tips for all tippers');
          final allTips =
              deepMapFromObject(event.snapshot.value as Map<Object?, Object?>);
          _tipGames = await deserializeTips(allTips);
        } else {
          log('deserializing tips for tipper ${tipper!.dbkey}');
          Map dbData = event.snapshot.value as Map;
          _tipGames = await Future.wait(dbData.entries.map((entry) async {
            Game? game = await _gamesViewModel.findGame(entry.key);
            if (game == null) {
              //log('game not found for tip ${entry.key}');
            } else {
              Map entryValue = entry.value as Map;
              return TipGame.fromJson(entryValue, entry.key, tipper!, game);
            }
            return null;
          }));
        }
      } else {
        log('No tips found in realtime database');
      }
    } finally {
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
    }
  }

  //this method, which allows for recusrsive maps, is no longer nessisary and could be removed

  Map<String, dynamic> deepMapFromObject(Map<Object?, Object?> map) {
    return Map<String, dynamic>.from(map.map((key, value) {
      if (value is Map<Object?, Object?>) {
        return MapEntry(key.toString(), deepMapFromObject(value));
      } else {
        return MapEntry(key.toString(), value);
      }
    }));
  }

  Future<List<TipGame>> deserializeTips(Map<String, dynamic> json,
      {tipper}) async {
    List<TipGame> allCompTips = [];

    for (var tipperEntry in json.entries) {
      Tipper? tipper = await tipperViewModel.findTipper(tipperEntry.key);
      if (tipper != null) {
        Map<String, dynamic> tipperTips = tipperEntry.value;
        for (var tipEntry in tipperTips.entries) {
          Game? game = await _gamesViewModel.findGame(tipEntry.key);
          if (game == null) {
            log('game not found for tip ${tipEntry.key}');
          } else {
            //log('game found for tip ${tipEntry.key}'
            TipGame tipGame =
                TipGame.fromJson(tipEntry.value, tipEntry.key, tipper, game);
            allCompTips.add(tipGame);
          }
        }
      } else {
        // tipper does not exist - skip this record
        log('Tipper ${tipperEntry.key} does not exist in deserializeTips');
      }
    }
    return await Future.wait(allCompTips.map((tip) => Future.value(tip)));
  }

  Future<TipGame?> findTip(Game game, Tipper tipper) async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }

    TipGame? tipGame = _tipGames.firstWhereOrNull(
      (tip) =>
          tip?.game.dbkey == game.dbkey && tip?.tipper.dbkey == tipper.dbkey,
    );

    // return a default 'd' tip if they forgot to submit a tip
    // and game has already started
    if ((game.gameState == GameState.resultKnown ||
            game.gameState == GameState.resultNotKnown) &&
        tipGame == null) {
      tipGame = TipGame(
        tip: GameResult.d,
        // set this tipper time as ephoch,
        // allows us to easily identify tips that were not submitted
        submittedTimeUTC: DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
        game: game,
        tipper: tipper,
      );
    }

    return tipGame;
  }

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(update);
    super.dispose();
  }

  Future<List<TipGame?>> getTipsForRound(
      Tipper tipper, int combinedRound) async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }

    //figure out which key to for this search. GoogleSheetService does not have
    //access to dbkey, so we need to use tippedID as the key

    if (tipper.dbkey != null) {
      return _tipGames
          .where((tipGame) =>
              tipGame?.tipper.dbkey == tipper.dbkey &&
              tipGame?.game.dauRound.dAUroundNumber == combinedRound)
          .toList();
    } else {
      return _tipGames
          .where((tipGame) =>
              tipGame?.tipper.tipperID == tipper.tipperID &&
              tipGame?.game.dauRound.dAUroundNumber == combinedRound)
          .toList();
    }

    // search all tips for the tipper and this round
  }
}
