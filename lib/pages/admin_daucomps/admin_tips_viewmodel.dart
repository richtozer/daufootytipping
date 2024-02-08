import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// define  constant for firestore database location
const tipsPathRoot = '/AllTips';

class AllTipsViewModel extends ChangeNotifier {
  List<Tip> _tips = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;

  late final GamesViewModel _gamesViewModel;
  final String currentDAUComp;
  final Completer<void> _initialLoadCompleter = Completer();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  //List<Tip> get tips => _tips;
  //List<Game> get games => _gamesViewModel.games;
  GamesViewModel get gamesViewModel => _gamesViewModel;

  TippersViewModel tipperViewModel = TippersViewModel();

  //constructor
  AllTipsViewModel(
      this.tipperViewModel, this.currentDAUComp, this._gamesViewModel) {
    _gamesViewModel.addListener(
        update); //listen for changes to _gamesViewModel so that we can notify our consumers that the data, we rely on, may have changed
    _listenToTips();
  }

  Future<List<Tip>> getTips() async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }
    return _tips;
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToTips() async {
    _tipsStream =
        _db.child('$tipsPathRoot/$currentDAUComp').onValue.listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    if (event.snapshot.exists) {
      final allTips =
          deepMapFromObject(event.snapshot.value as Map<Object?, Object?>);

      _tips = await deserializeTips(allTips);
    } else {
      log('No tips found in realtime database');
    }
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    notifyListeners();
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

  Future<List<Tip>> deserializeTips(Map<String, dynamic> json) async {
    List<Tip> allCompTips = [];

    for (var tipperEntry in json.entries) {
      Tipper tipper = await tipperViewModel.findTipper(tipperEntry.key);
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
    }
    return await Future.wait(allCompTips.map((tip) => Future.value(tip)));
  }

  /* Future<Tip?> getLatestGameTip(Game game, Tipper tipper) async {

    //TODO this also need to search for the tipper
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
  } */

  //method to get Tips for a specific round and return them in legacy format
  //ie a list of NRL tips padded to 8, and a list of AFL tips padded to 9
  // as one string
  /*  Future<String> getTipsForRound(int round, String tipTemplate) async {
    if (_initialLoadCompleter.isCompleted) {
      log('tips load already complete, getTipsForRound(round: $round)');
    } else {
      log('Waiting for initial Tip load to complete, getTipsForRound(round: $round)');
      await _initialLoadCompleter.future;
    }

    List<Game>? roundGames =
        games.where((game) => game.roundNumber == round).toList();
    String roundTips = tipTemplate;
    for (var game in roundGames) {
      //get the tip for this game
      Tip? existingTip = await getLatestGameTip(game);
      if (existingTip != null) {
        roundTips.replaceRange(
            game.matchNumber - 1, game.matchNumber, existingTip.tip.name);
      }
    }
    log('roundTips: $roundTips');
    return roundTips;
  } */

  /* Future<int> countTipsLodgedForRound(int combinedRound) async {
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
  } */

  // method to return tips as a String of existing tips for given Tipper.
  // The string will include the tips in the order of the games in the list, starting with NRL and then AFL.
  // If a tip is not found for a given game, a default tip of 'D' is returned as part of the string
  // NRL tips are padded to 8 characters, AFL tips are padded to 9 characters using z
  // input parameters are combinedRoundNumber and tipperDbKey
/*   Future<String> getConsolidatedTipsForRoundForTipper(
      int combinedRoundNumber, Tipper tipper) async {
    log('getDefaultTipsForRoundForTipper() waiting for initial Game load to complete');
    await initialLoadComplete;
    log('getDefaultTipsForRoundForTipper() initial Game load to COMPLETED');

    //create a list of default tips for the given round
    String defaultTips = await _gamesViewModel
        .getDefaultTipsForCombinedRoundNumber(combinedRoundNumber);

    //get the tipper's tips for the given round
    String tipperTips;
    tipperTips = await getTipsForRound(combinedRoundNumber, defaultTips);

    return tipperTips;
  } */

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(update);
    super.dispose();
  }
}
