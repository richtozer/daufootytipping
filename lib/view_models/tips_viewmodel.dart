import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const tipsPathRoot = '/AllTips';

class TipsViewModel extends ChangeNotifier {
  List<Tip?> _listOfTips = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;

  final DAUComp selectedDAUComp;
  final Completer<void> _initialLoadCompleter = Completer();

  Future<void> get initialLoadCompleted async => _initialLoadCompleter.future;

  Tipper?
      tipper; // if this is supplied in the constructor, then we are only interested in the tips for this tipper

  late final GamesViewModel _gamesViewModel;
  GamesViewModel get gamesViewModel => _gamesViewModel;

  late final TippersViewModel tipperViewModel;

  //constructor - this will get all tips from db
  TipsViewModel(
      this.tipperViewModel, this.selectedDAUComp, this._gamesViewModel) {
    log('TipsViewModel (all tips) constructor');
    _gamesViewModel.addListener(_update);
    _listenToTips();
  }

  //constructor - this will get all tips from db for a specific tipper - less expensive and quicker db read
  TipsViewModel.forTipper(this.tipperViewModel, this.selectedDAUComp,
      this._gamesViewModel, this.tipper) {
    log('TipsViewModel.forTipper constructor');
    _listenToTips();
  }

  void _update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToTips() async {
    if (tipper != null) {
      _tipsStream = _db
          .child('$tipsPathRoot/${selectedDAUComp.dbkey}/${tipper!.dbkey}')
          .onValue
          .listen((event) {
        _handleEvent(event);
      });
    } else {
      _tipsStream = _db
          .child('$tipsPathRoot/${selectedDAUComp.dbkey}')
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
              _deepMapFromObject(event.snapshot.value as Map<Object?, Object?>);
          log('_handleEvent (All tippers) - number of tippers to deserialize: ${allTips.length}');
          _listOfTips = await _deserializeTips(allTips);
        } else {
          log('deserializing tips for tipper ${tipper!.dbkey}');
          Map dbData = event.snapshot.value as Map;
          log('_handleEvent (Tipper ${tipper!.dbkey}) - number of tips to deserialize: ${dbData.length}');
          _listOfTips = await Future.wait(dbData.entries.map((entry) async {
            Game? game = await _gamesViewModel.findGame(entry.key);
            if (game == null) {
              //log('game not found for tip ${entry.key}');
            } else {
              Map entryValue = entry.value as Map;
              return Tip.fromJson(entryValue, entry.key, tipper!, game);
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

  Map<String, dynamic> _deepMapFromObject(Map<Object?, Object?> map) {
    return Map<String, dynamic>.from(map.map((key, value) {
      if (value is Map<Object?, Object?>) {
        return MapEntry(key.toString(), _deepMapFromObject(value));
      } else {
        return MapEntry(key.toString(), value);
      }
    }));
  }

  Future<List<Tip>> _deserializeTips(Map<String, dynamic> json) async {
    List<Tip> allCompTips = [];

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
            Tip tip = Tip.fromJson(tipEntry.value, tipEntry.key, tipper, game);
            allCompTips.add(tip);
          }
        }
      } else {
        // tipper does not exist - skip this record
        log('Tipper ${tipperEntry.key} does not exist in deserializeTips');
      }
    }
    return await Future.wait(allCompTips.map((tip) => Future.value(tip)));
  }

  Future<Tip?> findTip(Game game, Tipper tipper) async {
    await initialLoadCompleted;

    Tip? foundTip = _listOfTips.firstWhereOrNull(
      (tip) =>
          tip?.game.dbkey == game.dbkey && tip?.tipper.dbkey == tipper.dbkey,
    );

    // return a default 'd' tip if they forgot to submit a tip
    // and game has already started
    if ((game.gameState == GameState.startedResultKnown ||
            game.gameState == GameState.startedResultNotKnown) &&
        foundTip == null) {
      foundTip = Tip(
        tip: GameResult.d,
        // set this tipper time as ephoch,
        // allows us to easily identify tips that were not submitted
        submittedTimeUTC: DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
        game: game,
        tipper: tipper,
      );
      //log('Tip not found for game ${game.dbkey} and tipper ${tipper.name}. Defaulting to Away tip.');
    }

    return foundTip;
  }

  // returns true if the supplied tipper has submitted at least one tip for the comp
  Future<bool> hasSubmittedTips(Tipper tipper) async {
    await initialLoadCompleted;
    return _listOfTips.any((tip) => tip?.tipper.dbkey == tipper.dbkey);
  }

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(_update);
    super.dispose();
  }
}
