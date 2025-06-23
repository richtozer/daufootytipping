import 'dart:async';
import 'dart:developer';
import 'package:carousel_slider/carousel_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:watch_it/watch_it.dart';

// Helper class to structure historical matchup data for the UI
class HistoricalMatchupUIData {
  final String year;
  final String month;
  final String winningTeamName;
  final String winType; // "Home" or "Away" or "Draw"
  final String userTipTeamName;
  final bool isCurrentYear;
  final Game
      pastGame; // Keep a reference to the original game if needed for more details
  final String location; // New field

  HistoricalMatchupUIData({
    required this.year,
    required this.month,
    required this.winningTeamName,
    required this.winType,
    required this.userTipTeamName,
    required this.isCurrentYear,
    required this.pastGame,
    required this.location, // Added to constructor
  });
}

class GameTipViewModel extends ChangeNotifier {
  Tip? _tip;

  Tip? get tip => _tip;

  TipsViewModel allTipsViewModel;
  Tipper currentTipper;
  final DAUComp _currentDAUComp;
  Game game;

  int? _homeTeamScore;
  int? get homeTeamScore => _homeTeamScore;
  int? _awayTeamScore;
  int? get awayTeamScore => _awayTeamScore;

  final _db = FirebaseDatabase.instance.ref();

  bool _savingTip = false;
  bool get savingTip => _savingTip;

  final Completer<void> _initialLoadCompleter = Completer();
  Future<bool> get initialLoadCompleted async =>
      _initialLoadCompleter.isCompleted;

  int historicalTotalTipsOnCombination = 0;
  int historicalWinsOnCombination = 0;
  int historicalLossesOnCombination = 0;
  int historicalDrawsOnCombination = 0;
  String historicalInsightsString = "";

  int currentIndex = 0;

  final CarouselSliderController _controller = CarouselSliderController();
  CarouselSliderController get controller => _controller;

  //constructor
  GameTipViewModel(
    this.currentTipper,
    this._currentDAUComp,
    this.game,
    this.allTipsViewModel,
  ) {
    allTipsViewModel.addListener(_tipsUpdated); // Restored listener for tips
    // only monitor gamesViewModel if the comp still has active rounds
    if (_currentDAUComp.highestRoundNumberInPast() <
        _currentDAUComp.daurounds.length) {
      allTipsViewModel.gamesViewModel.addListener(_gamesViewModelUpdated);
    } else {
      log('GameTipsViewModel constructor: ${_currentDAUComp.name} has no active rounds. Not listening to gamesViewModel');
    }

    _findTip();
    _gameStartedTrigger();
  }

  // this method will delay returning until the game has started,
  // then use notifiyListeners to trigger the UI to update
  void _gameStartedTrigger() async {
    // if the game has already started, then we don't need to wait , just return
    if ((game.gameState == GameState.startedResultNotKnown ||
        game.gameState == GameState.startedResultKnown)) {
      return;
    }

    // calculate the time until the game starts and create a future.delayed
    // to wait until the game starts
    var timeUntilGameStarts =
        game.startTimeUTC.difference(DateTime.now().toUtc());

    // wait for the game to start before updating the UI
    await Future.delayed(timeUntilGameStarts);

    // now that the game has started, trigger the UI to update
    log('GameTipsViewModel._gameStartedTrigger()  Notify listeners called for game ${game.homeTeam.name} v ${game.awayTeam.name}, ${game.gameState}.');
    notifyListeners();
  }

  void _tipsUpdated() async {
    // we may have new data lets check if we need to update our tip
    Tip? newTip = (await allTipsViewModel.findTip(game, currentTipper));
    // if the tip has changed, then update the tip and notify listeners
    if (newTip != _tip) {
      _tip = newTip;
      log('GameTipsViewModel._tipsUpdated() Notify listeners called for game ${game.homeTeam.name} v ${game.awayTeam.name}, ${game.gameState}. ');
      notifyListeners();
    }
  }

  void _gamesViewModelUpdated() async {
    // we may have new game data, notify listeners
    game = (await allTipsViewModel.gamesViewModel.findGame(game.dbkey))!;
    _tip?.game.scoring = game.scoring; //update the tip scoring
    log('GameTipsViewModel._gamesViewModelUpdated() called for game ${game.dbkey}, ${game.gameState}. Notify listeners');

    _homeTeamScore = game.scoring?.currentScore(ScoringTeam.home);
    _awayTeamScore = game.scoring?.currentScore(ScoringTeam.away);

    notifyListeners();
  }

  void _findTip() async {
    await allTipsViewModel.initialLoadCompleted;

    _tip = await allTipsViewModel.findTip(game, currentTipper);

    // flag our intial load as complete
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    notifyListeners();

    // Fetch historical stats after the main tip is found and initial load is complete
    if (_initialLoadCompleter.isCompleted) {
      await _fetchHistoricalTipStats();
    }
  }

  Future<void> _fetchHistoricalTipStats() async {
    // Reset stats before recalculating
    historicalTotalTipsOnCombination = 0;
    historicalWinsOnCombination = 0;
    historicalLossesOnCombination = 0;
    historicalDrawsOnCombination = 0;
    historicalInsightsString = "";

    // Ensure allTipsViewModel has completed its initial load.
    // GameTipViewModel's _findTip already awaits allTipsViewModel.initialLoadCompleted
    // so it should be safe here.

    List<Tip?> tipperPastTips =
        allTipsViewModel.getTipsForTipper(currentTipper);

    if (tipperPastTips.isEmpty) {
      historicalInsightsString = "No past tips for this team combination.";
      notifyListeners();
      return;
    }

    for (Tip? pastTip in tipperPastTips) {
      if (pastTip == null) {
        // Should not happen if game is valid
        continue;
      }

      // Exclude current game
      if (pastTip.game.dbkey == game.dbkey) {
        continue;
      }

      bool sameCombination =
          (pastTip.game.homeTeam.dbkey == game.homeTeam.dbkey &&
                  pastTip.game.awayTeam.dbkey == game.awayTeam.dbkey) ||
              (pastTip.game.homeTeam.dbkey == game.awayTeam.dbkey &&
                  pastTip.game.awayTeam.dbkey == game.homeTeam.dbkey);

      if (sameCombination) {
        historicalTotalTipsOnCombination++;

        if (pastTip.game.scoring == null) {
          continue;
        }

        GameResult? actualGameResult =
            pastTip.game.scoring!.getGameResultCalculated(pastTip.game.league);

        bool isActualGameDraw = (pastTip.game.league == League.afl &&
                actualGameResult == GameResult.c) ||
            (pastTip.game.league == League.nrl &&
                actualGameResult == GameResult.c);

        bool isTipperPickedDraw = (pastTip.game.league == League.afl &&
                pastTip.tip == GameResult.c) ||
            (pastTip.game.league == League.nrl && pastTip.tip == GameResult.c);

        bool isWin = pastTip.tip == actualGameResult;

        if (isWin) {
          historicalWinsOnCombination++;
          if (isActualGameDraw && isTipperPickedDraw) {
            // Tipper correctly predicted a draw
            historicalDrawsOnCombination++;
          }
        } else {
          // Not a win
          // It's a loss if it's not a win AND it's not the specific case of (actual draw AND tipper picked draw)
          // The case (actual draw AND tipper picked draw) is already handled under "isWin"
          // So, if it's not a "Win" (meaning tip != actualResult), it's a Loss.
          historicalLossesOnCombination++;
        }
      }
    }

    if (historicalTotalTipsOnCombination == 0) {
      historicalInsightsString = "No past tips for this team combination.";
    } else {
      historicalInsightsString =
          "Previously on this matchup ($historicalTotalTipsOnCombination games): $historicalWinsOnCombination Wins, $historicalLossesOnCombination Losses, $historicalDrawsOnCombination Draws.";
    }
    notifyListeners();
  }

  // Test hook for unit tests
  Future<void> testHookFetchHistoricalTipStats() async {
    await _fetchHistoricalTipStats();
  }

  Future<Tip?> gettip() async {
    if (!_initialLoadCompleter.isCompleted) {
      await _initialLoadCompleter.future;
    }

    return _tip;
  }

  void addTip(Tip tip) async {
    try {
      assert(_initialLoadCompleter.isCompleted,
          'GameTipsViewModel.addTip() called before initial load completed');

      _savingTip = true;
      notifyListeners();

      // create a json representation of the tip
      final tipJson = tip.toJson();

      final Map<String, Map> updates = {};
      updates['$tipsPathRoot/${_currentDAUComp.dbkey}/${tip.tipper.dbkey}/${tip.game.dbkey}'] =
          tipJson;
      await _db.update(updates);
      log('new tip submitted: ${updates.toString()}');

      _tip = tip; // update the tip with the new tip

      // write a firebase analytic event that a tip was submitted
      FirebaseAnalytics.instance.logEvent(name: 'tip_submitted', parameters: {
        'game': tip.game.dbkey,
        'tipper': tip.tipper.name.toString(),
        'tip': tipJson.toString(),
        'submittedBy': currentTipper.name.toString(),
      });

      // Log the tip in Firestore
      _addLogOfTipToFirestore(tip);

      // do a mini stats update (asyncronously) for this round and tipper to update tips outstanding counts
      // also pass in the game, so we do a % tipped calculation
      di<StatsViewModel>().updateStats(
          _currentDAUComp, tip.game.getDAURound(_currentDAUComp), tip.tipper);

      // if we are in god mode, then also do a gamestats update
      if (di<TippersViewModel>().inGodMode == true) {
        di<StatsViewModel>().getGamesStatsEntry(game, true);
      }
    } catch (e) {
      log('GameTipsViewModel.addTip() error: $e');
      // rethrow exception so that the UI can handle it
      rethrow;
    } finally {
      _savingTip = false;
      notifyListeners();
    }
  }

  Future<void> _addLogOfTipToFirestore(Tip tip) async {
    // Extract the year, round, tipperId, gameId, and timestamp
    final year =
        tip.game.startTimeUTC.year; // Assuming the game has a start time
    final round = tip.game.getDAURound(_currentDAUComp)?.dAUroundNumber;
    final tipperId = tip.tipper.dbkey;
    final gameId = tip.game.dbkey;
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String(); // Use UTC timestamp as a unique key

    // Log the tip in Firestore
    try {
      await FirebaseFirestore.instance
          .collection('tipLogs')
          .doc(year.toString()) // Year as a document
          .collection(round.toString()) // Round as a sub-collection
          .doc(tipperId) // Tipper ID as a document
          .collection(gameId) // Game ID as a sub-collection
          .doc(timestamp) // Timestamp as a document
          .set({
        'tipperId': tipperId,
        'tipperName': tip.tipper.name,
        'gameId': gameId,
        'gameDetails': {
          'league': tip.game.league.name,
          'homeTeam': tip.game.homeTeam.name,
          'awayTeam': tip.game.awayTeam.name,
          'startTimeUTC': tip.game.startTimeUTC.toIso8601String(),
        },
        'tip': tip.game.league == League.afl
            ? tip.tip.afl
            : tip.tip.nrl, // Assuming `tip.tip` contains the actual tip value
        'tipSubmittedUTC': timestamp,
        'submittedBy': di<TippersViewModel>().authenticatedTipper?.name
      });

      log('_addLogOfTipToFirestore() Tip logged in Firestore for tipper: ${tip.tipper.name}, game: ${tip.game.dbkey}, timestamp: $timestamp');
    } catch (e) {
      log('Error logging tip in Firestore: $e');
    }
  }

  @override
  void dispose() {
    allTipsViewModel.gamesViewModel.removeListener(_gamesViewModelUpdated);
    allTipsViewModel.removeListener(_tipsUpdated);
    super.dispose();
  }

  Future<List<HistoricalMatchupUIData>> getFormattedHistoricalMatchups() async {
    log('GameTipViewModel.getFormattedHistoricalMatchups() called for game ${game.dbkey}');
    final List<HistoricalMatchupUIData> formattedMatchups = [];

    // 1. Get GamesViewModel
    final gamesViewModel = allTipsViewModel.gamesViewModel;
    await gamesViewModel.initialLoadComplete; // Ensure games are loaded

    // 2. Get historical matchups
    final List<Game> historicalGames =
        await gamesViewModel.getCompleteMatchupHistory(
      game.homeTeam,
      game.awayTeam,
      game.league,
    );

    log('Found ${historicalGames.length} historical games for ${game.homeTeam.name} vs ${game.awayTeam.name}');

    // 3. For each past game, format the data
    for (final pastGame in historicalGames) {
      if (pastGame.scoring == null ||
          pastGame.scoring!.homeTeamScore == null ||
          pastGame.scoring!.awayTeamScore == null) {
        log('Skipping game ${pastGame.dbkey} due to missing scores.');
        continue;
      }

      // a. Get user's tip for the past game
      final Tip? pastTip =
          await allTipsViewModel.findTip(pastGame, currentTipper);

      // b. Determine winning team and winType
      String winningTeamName = '';
      String winType = ''; // "Home", "Away", "Draw"

      if (pastGame.scoring!.homeTeamScore! > pastGame.scoring!.awayTeamScore!) {
        winningTeamName = pastGame.homeTeam.name;
        winType = 'Home';
      } else if (pastGame.scoring!.awayTeamScore! >
          pastGame.scoring!.homeTeamScore!) {
        winningTeamName = pastGame.awayTeam.name;
        winType = 'Away';
      } else {
        winningTeamName = 'Draw'; // Or "Nobody" or handle as per UI needs
        winType = 'Draw';
      }

      // c. Determine userTipTeamName
      String userTipTeamName = ''; // Default to empty
      if (pastTip != null && !pastTip.isDefaultTip()) {
        // New stricter condition
        if (pastTip.tip == GameResult.a || pastTip.tip == GameResult.b) {
          // Home tip
          userTipTeamName = pastGame.homeTeam.name;
        } else if (pastTip.tip == GameResult.d || pastTip.tip == GameResult.e) {
          // Away tip
          userTipTeamName = pastGame.awayTeam.name;
        } else if (pastTip.tip == GameResult.c) {
          // Draw tip
          userTipTeamName = 'Draw';
        }
      }
      // If pastTip is null or pastTip.isDefaultTip() is true, userTipTeamName remains empty.

      // d. Determine date components
      final gameDateLocal = pastGame.startTimeUTC.toLocal();
      final String year = DateFormat('yyyy').format(gameDateLocal);
      final String month = DateFormat('MMM').format(gameDateLocal);
      final bool isCurrentYear = gameDateLocal.year == DateTime.now().year;

      formattedMatchups.add(
        HistoricalMatchupUIData(
          year: year,
          month: month,
          winningTeamName: winningTeamName,
          winType: winType,
          userTipTeamName: userTipTeamName,
          isCurrentYear: isCurrentYear,
          pastGame: pastGame,
          location: pastGame.location, // Populate new field
        ),
      );
      log('Added historical matchup: ${pastGame.dbkey}, Winner: $winningTeamName, User Tip: $userTipTeamName, Location: ${pastGame.location}');
    }
    log('Finished formatting ${formattedMatchups.length} historical matchups.');
    return formattedMatchups;
  }
}
