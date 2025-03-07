import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

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
      _tipper; // if this is supplied in the constructor, then we are only interested in the tips for this tipper

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
      this._gamesViewModel, this._tipper) {
    log('TipsViewModel.forTipper constructor for tipper ${_tipper!.dbkey}');
    _listenToTips();
  }

  void _update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToTips() {
    if (_tipper != null) {
      _tipsStream = _db
          .child('$tipsPathRoot/${selectedDAUComp.dbkey}/${_tipper!.dbkey}')
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
        if (_tipper == null) {
          final allTips =
              _deepMapFromObject(event.snapshot.value as Map<Object?, Object?>);
          log('TipsViewModel._handleEvent() All tippers - Deserialize tip for ${allTips.length} tippers.');
          _listOfTips = await _deserializeTips(allTips);
        } else {
          log('_handleEvent deserializing tips for tipper ${_tipper!.dbkey}');
          Map dbData = event.snapshot.value as Map;
          log('_handleEvent (Tipper ${_tipper!.dbkey}) - number of tips to deserialize: ${dbData.length}');
          _listOfTips = await Future.wait(dbData.entries.map((tipEntry) async {
            Game? game = await _gamesViewModel.findGame(tipEntry.key);
            if (game == null) {
              assert(game != null);
              log('TipsViewModel._handleEvent() Game not found for tip ${tipEntry.key}');
            } else {
              Map entryValue = tipEntry.value as Map;
              return Tip.fromJson(entryValue, tipEntry.key, _tipper!, game);
            }
            return null;
          }));
        }
      } else {
        log('TipsViewModel._handleEvent() No tips found in realtime database');
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
            assert(game != null);
            log('TipsViewModel._deserializeTips() Game not found for tip ${tipEntry.key}');
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

  //delete a tip
  Future<void> deleteTip(Tip tip) async {
    await _db
        .child(
            '$tipsPathRoot/${selectedDAUComp.dbkey}/${tip.tipper.dbkey}/${tip.game.dbkey}')
        .remove();
  }

  // returns true if the supplied tipper has submitted at least one tip for the comp
  Future<bool> hasSubmittedTips(Tipper tipper) async {
    await initialLoadCompleted;
    return _listOfTips.any((tip) => tip?.tipper.dbkey == tipper.dbkey);
  }

  // method to return the number of tips submitted for the supplied round and league
  int _numberOfTipsSubmittedForRoundAndLeague(DAURound round, League league) {
    return _listOfTips
        .where((tip) =>
            tip!.game.getDAURound(selectedDAUComp) == round &&
            tip.game.league == league)
        .length;
  }

  // method to return count of outstanding tips for the supplied round and league
  int numberOfOutstandingTipsForRoundAndLeague(DAURound round, League league) {
    // Calculate the number of tips outstanding for this league round
    int totalGames = round.getGamesForLeague(league).length;
    int tipsSubmitted = _numberOfTipsSubmittedForRoundAndLeague(round, league);
    return totalGames - tipsSubmitted;
  }

  // method to return the number of margin tips for the supplied round and league
  int numberOfMarginTipsSubmittedForRoundAndLeague(
      DAURound round, League league) {
    return _listOfTips
        .where((tip) =>
            tip!.game.getDAURound(selectedDAUComp) == round &&
            tip.game.league == league &&
            (tip.tip == GameResult.a || tip.tip == GameResult.e))
        .length;
  }

  Future<double> percentageOfTippersTipped(
      GameResult gameResult, Game game) async {
    await initialLoadCompleted;

    // throw an exception if the tipper is not null
    if (_tipper != null) {
      throw Exception(
          'percentageOfTippersTipped() should not be called when doing agregates for scoring. _tipper is not null');
    }
    // get the paidForComp status for the selected tipper
    bool isScoringPaidComp = false;
    isScoringPaidComp =
        di<TippersViewModel>().selectedTipper.paidForComp(selectedDAUComp);

    // loop through all tippers and remove those that dont have the same paidForComp status
    List<Tipper> tippers = _listOfTips
        .map((tip) => tip!.tipper)
        .where((tipper) =>
            tipper.paidForComp(selectedDAUComp) == isScoringPaidComp)
        .toList();

    // now do the calculation
    int totalTippers = tippers.length;
    int totalTippersTipped = 0;

    // loop through each tipper and call findTip()
    for (Tipper tipper in tippers) {
      findTip(game, tipper).then((tip) {
        if (tip?.tip == gameResult) {
          totalTippersTipped++;
        }
      });
    }

    return totalTippersTipped / totalTippers;
  }

  List<Tip?> getTipsForTipper(Tipper tipper) {
    return _listOfTips
        .where((tip) => tip!.tipper.dbkey == tipper.dbkey)
        .toList();
  }

  updateTip(Tip tip) {
    _db
        .child(
            '$tipsPathRoot/${selectedDAUComp.dbkey}/${tip.tipper.dbkey}/${tip.game.dbkey}')
        .update(tip.toJson());
  }

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(_update);
    super.dispose();
  }

  deleteAllTipsForTipper(Tipper originalTipper) {
    try {
      _db
          .child(
              '$tipsPathRoot/${selectedDAUComp.dbkey}/${originalTipper.dbkey}')
          .remove();
    } catch (e) {
      log('Error deleting all tips for tipper ${originalTipper.dbkey}');
    }
  }
}
