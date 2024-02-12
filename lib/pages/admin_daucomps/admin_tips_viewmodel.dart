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

  late final TippersViewModel tipperViewModel;

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

  @override
  void dispose() {
    _tipsStream.cancel(); // stop listening to stream
    _gamesViewModel.removeListener(update);
    super.dispose();
  }
}
