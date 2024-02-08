import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/location_latlong.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

// define  constant for firestore database location
const tipsPathRoot = '/AllTips';

class GameTipsViewModel extends ChangeNotifier {
  Tip? _tip;
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _tipsStream;
  bool _savingTip = false;

  final String currentDAUComp;
  final Game game;
  final Completer<void> _initialLoadCompleter = Completer();

  Tip? get tip => _tip;

  bool get savingTip => _savingTip;

  Tipper currentTipper;

  LegacyTippingService legcyTippingService =
      GetIt.instance<LegacyTippingService>();

  //constructor
  GameTipsViewModel(this.currentTipper, this.currentDAUComp, this.game) {
    _listenToTips();
  }

  void update() {
    notifyListeners(); //notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  }

  void _listenToTips() async {
    _tipsStream = _db
        .child(
            '$tipsPathRoot/$currentDAUComp/${currentTipper.dbkey}/${game.dbkey}')
        .onValue
        .listen((event) {
      _handleEvent(event);
    });
  }

  Future<void> _handleEvent(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        final tipJson = event.snapshot.value;
        final Map<String, dynamic> tipData =
            Map<String, dynamic>.from(tipJson as Map<Object?, Object?>);

        log('Tip found for Tipper ${currentTipper.name} in game ${game.dbkey}, tipData: $tipData');

        _tip = Tip.fromJson(tipData, game.dbkey, currentTipper, game);
      } else {
        log('No tip found for Tipper ${currentTipper.name} in game ${game.dbkey}');
      }
    } catch (e) {
      log('Error in GameTipsViewModel._handleEvent: $e');
    } finally {
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
    }
  }

  void addTip(List<Game> roundGames, Tip tip, int combinedRoundNumber) async {
    try {
      _savingTip = true;

      // create a json representation of the tip
      final tipJson = await tip.toJson();

      final Map<String, Map> updates = {};
      updates['$tipsPathRoot/$currentDAUComp/${tip.tipper.dbkey}/${tip.game.dbkey}'] =
          tipJson;
      await _db.update(updates);
      log('new tip logged: ${updates.toString()}');

      // code section to support legacy tipping service
      // find the Tip game position in the roundGames list
      int gameIndex =
          roundGames.indexWhere((game) => game.dbkey == tip.game.dbkey);

      legcyTippingService.submitTip(
          currentTipper.name, tip, gameIndex, combinedRoundNumber);

      // end code section to support legacy tipping service

      //unsubscripe the tipper from the FCM topic for this game
      await FirebaseMessaging.instance.unsubscribeFromTopic(tip.game.dbkey);

      await FirebaseAnalytics.instance
          .logEvent(name: 'tip_submitted', parameters: {
        'tipper': tip.tipper.name,
        'comp': currentDAUComp,
        'game':
            'Round: $combinedRoundNumber, ${tip.game.homeTeam} v ${tip.game.awayTeam}',
        'tip': tip.tip.toString(),
        'submittedTimeUTC': tip.submittedTimeUTC.toString(),
      });
    } catch (e) {
      // rethrow exception so that the UI can handle it
      rethrow;
    } finally {
      _savingTip = false;
    }
  }

  Future<Tip?> getLatestGameTip() async {
    return await getLatestGameTipFromDb();
  }

  Future<Tip?> getLatestGameTipFromDb() async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
      log('tips load complete, GameTipsViewModel.getLatestGameTip(${game.dbkey})');
    }

    if (_tip != null) {
      log('found tip ${_tip!.tip} for game ${game.dbkey} (${game.homeTeam.name} v ${game.awayTeam.name} GameTipsViewModel.getLatestGameTipFromDb()');
      return _tip;
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

  LatLng? getLatLng() {
    if (game.locationLatLong != null) {
      return game.locationLatLong!;
    } else {
      return null;
    }
  }

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    super.dispose();
  }
}
