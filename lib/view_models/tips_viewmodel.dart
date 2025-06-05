import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/services/app_lifecycle_observer.dart';

// define  constant for firestore database location
const tipsPathRoot = '/AllTips';

class TipsViewModel extends ChangeNotifier {
  List<Tip?> _listOfTips = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;

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
    _lifecycleSubscription = di<AppLifecycleObserver>().lifecycleStateStream.listen((state) {
      if (state == AppLifecycleState.resumed) {
        _listenToTips(); // Re-subscribe on resume
      }
    });
    _gamesViewModel.addListener(_update);
    _listenToTips();
  }

  //constructor - this will get all tips from db for a specific tipper - less expensive and quicker db read
  TipsViewModel.forTipper(this.tipperViewModel, this.selectedDAUComp,
      this._gamesViewModel, this._tipper) {
    log('TipsViewModel.forTipper constructor for tipper ${_tipper!.dbkey}');
    _lifecycleSubscription = di<AppLifecycleObserver>().lifecycleStateStream.listen((state) {
      if (state == AppLifecycleState.resumed) {
        _listenToTips(); // Re-subscribe on resume
      }
    });
    _gamesViewModel.addListener(_update);
    _listenToTips();
  }

  void _update() {
    notifyListeners(); //notify our consumers that the data may have changed to gamesviewmodel.games data that we have a dependency on
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
              Map<String, dynamic>.from(event.snapshot.value as Map);
          log('TipsViewModel._handleEvent() All tippers - Deserialize tip for ${allTips.length} tippers.');
          _listOfTips = await _deserializeTips(allTips);
        } else {
          log('_handleEvent deserializing tips for tipper ${_tipper!.dbkey}');
          Map<String, dynamic> dbData =
              Map<String, dynamic>.from(event.snapshot.value as Map);
          log('_handleEvent (Tipper ${_tipper!.dbkey}) - number of tips to deserialize: ${dbData.length}');
          _listOfTips = await Future.wait(dbData.entries.map((tipEntry) async {
            Game? game = await _gamesViewModel.findGame(tipEntry.key);
            if (game == null) {
              assert(game != null);
              log('TipsViewModel._handleEvent() Game not found for tip ${tipEntry.key}');
              return null;
            } else {
              Map<String, dynamic> entryValue =
                  Map<String, dynamic>.from(tipEntry.value as Map);
              return Tip.fromJson(entryValue, tipEntry.key, _tipper!, game);
            }
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

  Future<List<Tip>> _deserializeTips(Map<String, dynamic> json) async {
    List<Tip> allCompTips = [];

    for (var tipperEntry in json.entries) {
      Tipper? tipper = await tipperViewModel.findTipper(tipperEntry.key);
      if (tipper != null) {
        Map<String, dynamic> tipperTips =
            Map<String, dynamic>.from(tipperEntry.value as Map);
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

  int _numberOfTipsSubmittedForRoundAndLeague(DAURound round, League league) {
    return _listOfTips.where((tip) {
      // Attempt to get the round for the game, if it fails, return false
      return tip!.game.getDAURound(selectedDAUComp) == round &&
          tip.game.league == league;
    }).length;
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

  Future<GameStatsEntry> percentageOfTippersTipped(Game game) async {
    // throw an exception if the tipper is not null
    if (_tipper != null) {
      throw Exception(
          'percentageOfTippersTipped() should not be called when doing aggregates for scoring. _tipper is not null');
    }
    // get the paidForComp status for the selected tipper
    bool isScoringPaidComp = false;
    isScoringPaidComp =
        di<TippersViewModel>().selectedTipper.paidForComp(selectedDAUComp);

    // loop through all tippers and remove those that don't have the same paidForComp status
    List<Tipper> tippers = tipperViewModel.tippers
        .where((tipper) =>
            tipper.paidForComp(selectedDAUComp) == isScoringPaidComp)
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
          gameStatsEntry.percentageTippedHomeMargin =
              gameStatsEntry.reducePrecision(totalTippersTipped / totalTippers);
          break;
        case GameResult.b:
          gameStatsEntry.percentageTippedHome =
              gameStatsEntry.reducePrecision(totalTippersTipped / totalTippers);
          break;
        case GameResult.c:
          gameStatsEntry.percentageTippedDraw =
              gameStatsEntry.reducePrecision(totalTippersTipped / totalTippers);
          break;
        case GameResult.d:
          gameStatsEntry.percentageTippedAway =
              gameStatsEntry.reducePrecision(totalTippersTipped / totalTippers);
          break;
        case GameResult.e:
          gameStatsEntry.percentageTippedAwayMargin =
              gameStatsEntry.reducePrecision(totalTippersTipped / totalTippers);
          break;
        case GameResult.z:
          break;
      }
    }
    // calculate the average score across all tippers for this game
    if (runningAverageScoreCountTips > 0) {
      gameStatsEntry.averageScore = gameStatsEntry.reducePrecision(
          runningAverageScoreTotal / runningAverageScoreCountTips);
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

  updateTip(Tip tip) {
    _db
        .child(
            '$tipsPathRoot/${selectedDAUComp.dbkey}/${tip.tipper.dbkey}/${tip.game.dbkey}')
        .update(tip.toJson());
  }

  @override
  void dispose() {
    _lifecycleSubscription?.cancel();
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
