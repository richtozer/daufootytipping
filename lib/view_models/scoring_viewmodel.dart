import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

// Define constants for Firestore database location
const scoresPathRoot = '/AllScores';
const roundScoresRoot = 'round_scores';
const liveScoresRoot = 'live_scores';

class ScoresViewModel extends ChangeNotifier {
  Map<Tipper, Map<int, RoundScores>> _allTipperRoundScores = {};
  Map<Tipper, Map<int, RoundScores>> get allTipperRoundScores =>
      _allTipperRoundScores;

  final List<Game> _gamesWithLiveScores = [];

  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _liveScoresStream;
  late StreamSubscription<DatabaseEvent> _allRoundScoresStream;

  final DAUComp currentDAUComp;

  bool _isScoring = false;
  bool get isScoring => _isScoring;

  final Completer<void> _initialLiveScoreLoadCompleter = Completer();
  Future<void> get initialLiveScoreLoadComplete =>
      _initialLiveScoreLoadCompleter.future;

  final Completer<void> _initialRoundLoadCompleted = Completer();
  Future<void> get initialRoundComplete => _initialRoundLoadCompleted.future;

  List<LeaderboardEntry> _leaderboard = [];
  List<LeaderboardEntry> get leaderboard => _leaderboard;

  Map<int, List<RoundWinnerEntry>> _roundWinners = {};
  Map<int, List<RoundWinnerEntry>> get roundWinners => _roundWinners;

  // Constructor
  ScoresViewModel(this.currentDAUComp) {
    log('***** ScoresViewModel_constructor(ALL TIPPERS)*** for comp: ${currentDAUComp.dbkey}');
    _listenToScores();
  }

  void _listenToScores() async {
    _allRoundScoresStream = _db
        .child('$scoresPathRoot/${currentDAUComp.dbkey}/$roundScoresRoot')
        .onValue
        .listen(_handleEventRoundScores, onError: (error) {
      log('Error listening to round scores: $error');
    });

    _liveScoresStream = _db
        .child('$scoresPathRoot/${currentDAUComp.dbkey}/$liveScoresRoot')
        .onValue
        .listen(_handleEventLiveScores, onError: (error) {
      log('Error listening to live scores: $error');
    });
  }

  Future<void> _handleEventRoundScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        var dbData = event.snapshot.value as Map<dynamic, dynamic>;

        List<Future<MapEntry<Tipper, Map<int, RoundScores>>?>> futureEntries =
            dbData.entries.map((entry) async {
          Tipper? tipper = await di<TippersViewModel>().findTipper(entry.key);
          if (tipper != null) {
            var list = entry.value as List<dynamic>;
            Map<int, RoundScores> scores = {
              for (int i = 0; i < list.length; i++)
                i: RoundScores.fromJson(Map<String, dynamic>.from(list[i]))
            };
            return MapEntry(tipper, scores);
          } else {
            log('_handleEventRoundScores() Tipper ${entry.key} does not exist in TipperViewModel. Skipping.');
            return null;
          }
        }).toList();

        List<MapEntry<Tipper, Map<int, RoundScores>>> entries =
            (await Future.wait(futureEntries))
                .where((item) => item != null)
                .cast<MapEntry<Tipper, Map<int, RoundScores>>>()
                .toList();

        _allTipperRoundScores = Map.fromEntries(entries);
      } else {
        log('Snapshot ${event.snapshot.ref.path} does not exist in _handleEventRoundScores');
      }

      if (!_initialRoundLoadCompleted.isCompleted) {
        _initialRoundLoadCompleted.complete();
      }

      // update the leaderboard
      await _updateLeaderboardForComp();
      // Update the round winners
      await _updateRoundWinners();
      // rank the tippers
      await _rankTippers();

      notifyListeners();
    } catch (e) {
      log('Error listening to /AllScores/round_scores: $e');

      if (!_initialRoundLoadCompleted.isCompleted) {
        _initialRoundLoadCompleted.complete();
      }
      rethrow;
    }
  }

  Future<void> _handleEventLiveScores(DatabaseEvent event) async {
    try {
      if (event.snapshot.exists) {
        var dbData = event.snapshot.value as Map<dynamic, dynamic>;

        _gamesWithLiveScores.clear();
        var gamesViewModel = di<GamesViewModel>();

        for (var entry in dbData.entries) {
          var game = await gamesViewModel.findGame(entry.key);
          var scoring =
              Scoring.fromJson(Map<String, dynamic>.from(entry.value));
          if (game!.scoring == null) {
            game.scoring = scoring;
          } else {
            game.scoring?.croudSourcedScores = scoring.croudSourcedScores;
          }

          _gamesWithLiveScores.add(game);

          log('Loaded live score for game ${game.dbkey}');
        }

        notifyListeners();
      }
    } catch (e) {
      log('Error listening to /AllScores/live_scores: $e');
      rethrow;
    } finally {
      if (!_initialLiveScoreLoadCompleter.isCompleted) {
        _initialLiveScoreLoadCompleter.complete();
      }
    }
  }

  Future<String> updateScoring(DAUComp daucompToUpdate,
      Tipper? onlyUpdateThisTipper, DAURound? onlyUpdateThisRound) async {
    var stopwatch = Stopwatch()..start();
    try {
      if (_isScoring) {
        return 'Scoring already in progress';
      }

      _isScoring = true;

      if (!_initialRoundLoadCompleted.isCompleted) {
        await _initialRoundLoadCompleted.future;
      }

      TippersViewModel tippersViewModel = di<TippersViewModel>();

      // we need to load tips for all tippers if onlyUpdateThisTipper is null
      TipsViewModel allTipsViewModel;
      if (onlyUpdateThisTipper == null) {
        allTipsViewModel = TipsViewModel(
            di<TippersViewModel>(), daucompToUpdate, di<GamesViewModel>());
      } else {
        // load the existing model via di
        allTipsViewModel = di<DAUCompsViewModel>().tipperTipsViewModel!;
      }

      List<Tipper> tippersToUpdate = await _getTippersToUpdate(
          onlyUpdateThisTipper, tippersViewModel, daucompToUpdate);

      await _removeScoresInactiveTippers(tippersToUpdate, daucompToUpdate);

      var dauRoundsEdited =
          _getRoundsToUpdate(onlyUpdateThisRound, daucompToUpdate);

      Map<Tipper, Map<int, RoundScores>> changedTippers = {};

      for (Tipper tipperToScore in tippersToUpdate) {
        for (DAURound dauRound in dauRoundsEdited) {
          RoundScores newScores = await _calculateRoundScoresForTipper(
              tipperToScore, dauRound, allTipsViewModel);

          // Check if the scores are null or different
          bool shouldUpdate = _allTipperRoundScores[tipperToScore] == null ||
              _allTipperRoundScores[tipperToScore]![
                      dauRound.dAUroundNumber - 1] ==
                  null ||
              _allTipperRoundScores[tipperToScore]![
                      dauRound.dAUroundNumber - 1] !=
                  newScores;

          if (shouldUpdate) {
            // If scores are null or different, update them
            changedTippers[tipperToScore] ??= {};
            changedTippers[tipperToScore]![dauRound.dAUroundNumber - 1] =
                newScores;
          }
          // Otherwise, skip the update
        }
      }

      if (changedTippers.isNotEmpty) {
        await _writeRoundScoresToDb(changedTippers, daucompToUpdate);
      }

      String res =
          'Completed scoring updates for ${tippersToUpdate.length} tippers and ${dauRoundsEdited.length} rounds.';
      log(res);

      stopwatch.stop();
      log('updateScoring executed in ${stopwatch.elapsed}');

      _isScoring = false;

      return res;
    } catch (e) {
      log('Error updating scoring: $e');
      _isScoring = false;
      rethrow;
    }
  }

  Future<void> _removeScoresInactiveTippers(
      List<Tipper> tippersToUpdate, DAUComp daucompToUpdate) async {
    List<Tipper> tippersToRemove = [];
    for (var tipper in _allTipperRoundScores.keys) {
      if (!tippersToUpdate.contains(tipper)) {
        tippersToRemove.add(tipper);
      }
    }

    for (var tipper in tippersToRemove) {
      await _db
          .child(scoresPathRoot)
          .child(daucompToUpdate.dbkey!)
          .child(roundScoresRoot)
          .child(tipper.dbkey!)
          .remove();
      log('Removed scores for inactive tipper ${tipper.name}');
    }
  }

  Future<void> _writeRoundScoresToDb(
      Map<Tipper, Map<int, RoundScores>> updatedTipperRoundScores,
      DAUComp dauComp) async {
    log('Writing round scores to DB for ${updatedTipperRoundScores.length} tippers');

    // turn off the listener
    _allRoundScoresStream.cancel();

    for (var roundScore in updatedTipperRoundScores.entries) {
      final updateData =
          (roundScore.value).map((k, v) => MapEntry(k.toString(), v.toJson()));
      final updateMap = {
        for (var entry in updateData.entries) entry.key: entry.value
      };

      await _db
          .child(scoresPathRoot)
          .child(dauComp.dbkey!)
          .child(roundScoresRoot)
          .child(roundScore.key.dbkey!)
          .update(updateMap);
    }

    // turn the listener back on
    _allRoundScoresStream = _db
        .child('$scoresPathRoot/${currentDAUComp.dbkey}/$roundScoresRoot')
        .onValue
        .listen(_handleEventRoundScores, onError: (error) {
      log('Error listening to round scores: $error');
    });
  }

  Future<void> _updateRoundWinners() async {
    Map<int, List<RoundWinnerEntry>> roundWinners = {};
    Map<int, int> maxRoundScores = {};

    for (var tipper in _allTipperRoundScores.keys) {
      for (var round in _allTipperRoundScores[tipper]!.entries) {
        if (maxRoundScores[round.key] == null) {
          maxRoundScores[round.key] = 0;
        }
        var roundScores = round.value;
        if (roundScores.aflScore + roundScores.nrlScore >
            maxRoundScores[round.key]!) {
          maxRoundScores[round.key] =
              roundScores.aflScore + roundScores.nrlScore;
        }
      }
    }

    for (var tipper in _allTipperRoundScores.keys) {
      for (var round in _allTipperRoundScores[tipper]!.entries) {
        var roundScores = round.value;
        if (roundScores.aflScore + roundScores.nrlScore ==
                maxRoundScores[round.key]! &&
            roundScores.nrlMaxScore + roundScores.aflMaxScore > 0) {
          roundWinners[round.key] ??= [];
          roundWinners[round.key]!.add(RoundWinnerEntry(
            roundNumber: roundScores.roundNumber,
            tipper: tipper,
            total: roundScores.aflScore + roundScores.nrlScore,
            nRL: roundScores.nrlScore,
            aFL: roundScores.aflScore,
            aflMargins: roundScores.aflMarginTips,
            aflUPS: roundScores.aflMarginUPS,
            nrlMargins: roundScores.nrlMarginTips,
            nrlUPS: roundScores.nrlMarginUPS,
          ));

          if (_leaderboard.isNotEmpty) {
            var leaderboardEntry =
                _leaderboard.firstWhere((element) => element.tipper == tipper);
            leaderboardEntry.numRoundsWon++;
          }
        }
      }
    }

    _roundWinners = roundWinners;
  }

  Future<void> _updateLeaderboardForComp() async {
    var leaderboard = _allTipperRoundScores.entries.map((e) {
      int totalScore = e.value.values.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflScore + roundScores.nrlScore));

      int nrlScore = e.value.values.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.nrlScore));

      int aflScore = e.value.values.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflScore));

      int aflMargins = e.value.values.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflMarginTips));

      int aflMarginUps = e.value.values.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.aflMarginUPS));

      int nrlMargins = e.value.values.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.nrlMarginTips));

      int nrlMarginUps = e.value.values.fold<int>(
          0,
          (previousValue, RoundScores roundScores) =>
              previousValue + (roundScores.nrlMarginUPS));

      return LeaderboardEntry(
        rank: 0, // to be replaced later with actual rank calculation
        tipper: e.key,
        total: totalScore,
        nRL: nrlScore,
        aFL: aflScore,
        numRoundsWon:
            0, // to be replaced later with actual numRoundsWon calculation
        aflMargins: aflMargins,
        aflUPS: aflMarginUps,
        nrlMargins: nrlMargins,
        nrlUPS: nrlMarginUps,
      );
    }).toList();

    leaderboard.sort((a, b) => b.total.compareTo(a.total));

    int rank = 1;
    int skip = 1;
    for (int i = 0; i < leaderboard.length; i++) {
      if (i > 0 && leaderboard[i].total < leaderboard[i - 1].total) {
        rank += skip;
        skip = 1;
      } else if (i > 0 && leaderboard[i].total == leaderboard[i - 1].total) {
        skip++;
      }
      leaderboard[i].rank = rank;
    }

    leaderboard.sort((a, b) {
      int rankComparison = a.rank.compareTo(b.rank);
      if (rankComparison == 0) {
        return a.tipper.name
            .toLowerCase()
            .compareTo(b.tipper.name.toLowerCase());
      } else {
        return rankComparison;
      }
    });

    _leaderboard = leaderboard.toList();

    return;
  }

  void sortRoundWinnersByRoundNumber(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) =>
          ascending ? a.key.compareTo(b.key) : b.key.compareTo(a.key));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  void sortRoundWinnersByWinner(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) => ascending
          ? a.value[0].tipper.name
              .toLowerCase()
              .compareTo(b.value[0].tipper.name.toLowerCase())
          : b.value[0].tipper.name
              .toLowerCase()
              .compareTo(a.value[0].tipper.name.toLowerCase()));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  void sortRoundWinnersByTotal(bool ascending) {
    var sortedEntries = _roundWinners.entries.toList()
      ..sort((a, b) => ascending
          ? a.value[0].total.compareTo(b.value[0].total)
          : b.value[0].total.compareTo(a.value[0].total));

    _roundWinners = Map.fromEntries(sortedEntries);
  }

  List<RoundScores> getTipperRoundScoresForComp(Tipper tipper) {
    if (!_initialRoundLoadCompleted.isCompleted) {
      return [];
    }

    if (_allTipperRoundScores.containsKey(tipper)) {
      int latestRoundNumber = di<DAUCompsViewModel>()
          .selectedDAUComp!
          .getHighestRoundNumberWithAllGamesPlayed();

      return _allTipperRoundScores[tipper]!
          .entries
          .where((entry) => entry.key <= latestRoundNumber - 1)
          .map((entry) => entry.value)
          .toList();
    } else {
      return [];
    }
  }

  Future<RoundScores> getTipperConsolidatedScoresForRound(
      DAURound round, Tipper tipper) async {
    if (!_initialRoundLoadCompleted.isCompleted) {
      await _initialRoundLoadCompleted.future;
    }

    if (_allTipperRoundScores[tipper] == null) {
      return RoundScores(
        roundNumber: round.dAUroundNumber,
        rank: 0,
        rankChange: 0,
        aflScore: 0,
        aflMaxScore: 0,
        nrlScore: 0,
        nrlMaxScore: 0,
        aflMarginTips: 0,
        aflMarginUPS: 0,
        nrlMarginTips: 0,
        nrlMarginUPS: 0,
      );
    }

    if (!_allTipperRoundScores[tipper]!.containsKey(round.dAUroundNumber - 1)) {
      return RoundScores(
        roundNumber: round.dAUroundNumber,
        rank: 0,
        rankChange: 0,
        aflScore: 0,
        aflMaxScore: 0,
        nrlScore: 0,
        nrlMaxScore: 0,
        aflMarginTips: 0,
        aflMarginUPS: 0,
        nrlMarginTips: 0,
        nrlMarginUPS: 0,
      );
    }

    return _allTipperRoundScores[tipper]![round.dAUroundNumber - 1]!;
  }

  void addLiveScore(Game game, CrowdSourcedScore croudSourcedScore) {
    final oldScoring = game.scoring;

    final newScoring = oldScoring?.copyWith(
        croudSourcedScores: oldScoring.croudSourcedScores == null
            ? [croudSourcedScore]
            : [...oldScoring.croudSourcedScores!, croudSourcedScore]);

    game.scoring = newScoring;

    if (game.scoring?.croudSourcedScores != null &&
        game.scoring!.croudSourcedScores!
                .where((element) =>
                    element.scoreTeam == croudSourcedScore.scoreTeam)
                .length >
            3) {
      game.scoring!.croudSourcedScores!.removeWhere((element) =>
          element.scoreTeam == croudSourcedScore.scoreTeam &&
          element.submittedTimeUTC ==
              game.scoring!.croudSourcedScores!
                  .where((element) =>
                      element.scoreTeam == croudSourcedScore.scoreTeam)
                  .reduce((value, element) =>
                      value.submittedTimeUTC.isBefore(element.submittedTimeUTC)
                          ? value
                          : element)
                  .submittedTimeUTC);
    }

    di<ScoresViewModel>()._writeLiveScoreToDb(game);
  }

  Future<void> _writeLiveScoreToDb(Game game) async {
    if (!_gamesWithLiveScores.contains(game)) {
      _gamesWithLiveScores.add(game);
    }

    Map<String, Map<String, dynamic>> liveScores = {};
    // Create a copy of the list for safe iteration
    var gamesCopy = List<Game>.from(_gamesWithLiveScores);
    for (var game in gamesCopy) {
      liveScores[game.dbkey] = game.scoring!.toJson();

      await _db
          .child(scoresPathRoot)
          .child(currentDAUComp.dbkey!)
          .child(liveScoresRoot)
          .update(liveScores);
      log('Wrote live score to DB for game ${game.dbkey}');
    }
  }

  Future<List<Tipper>> _getTippersToUpdate(Tipper? updateThisTipper,
      TippersViewModel tippersViewModel, DAUComp daucompToUpdate) async {
    if (updateThisTipper != null) {
      return [updateThisTipper];
    } else {
      return await tippersViewModel.getActiveTippers(daucompToUpdate);
    }
  }

  List<DAURound> _getRoundsToUpdate(
      DAURound? onlyUpdateThisRound, DAUComp daucompToUpdate) {
    var dauRoundsEdited = daucompToUpdate.daurounds;
    if (onlyUpdateThisRound != null) {
      dauRoundsEdited = [onlyUpdateThisRound];
    }
    return dauRoundsEdited;
  }

  Future<RoundScores> _calculateRoundScoresForTipper(Tipper tipperToScore,
      DAURound dauRound, TipsViewModel allTipsViewModel) async {
    RoundScores proposedRoundScores = RoundScores(
      roundNumber: dauRound.dAUroundNumber,
      rank: 0,
      rankChange: 0,
      aflScore: 0,
      aflMaxScore: 0,
      nrlScore: 0,
      nrlMaxScore: 0,
      aflMarginTips: 0,
      aflMarginUPS: 0,
      nrlMarginTips: 0,
      nrlMarginUPS: 0,
    );

    for (var game in dauRound.games) {
      TipGame? tipGame = await allTipsViewModel.findTip(game, tipperToScore);

      if (tipGame == null) {
        continue;
      }

      if (tipGame.game.gameState != GameState.notStarted &&
          tipGame.game.gameState != GameState.startingSoon) {
        int marginTip =
            (tipGame.tip == GameResult.a || tipGame.tip == GameResult.e)
                ? 1
                : 0;

        if (tipGame.game.league == League.afl) {
          proposedRoundScores.aflMarginTips += marginTip;
        } else {
          proposedRoundScores.nrlMarginTips += marginTip;
        }

        int score = tipGame.getTipScoreCalculated();
        int maxScore = tipGame.getMaxScoreCalculated();

        if (game.league == League.afl) {
          proposedRoundScores.aflScore += score;
          proposedRoundScores.aflMaxScore += maxScore;
        } else {
          proposedRoundScores.nrlScore += score;
          proposedRoundScores.nrlMaxScore += maxScore;
        }

        int marginUPS = 0;
        if (tipGame.game.scoring != null) {
          marginUPS = (tipGame.game.scoring!
                              .getGameResultCalculated(game.league) ==
                          GameResult.a &&
                      tipGame.tip == GameResult.a) ||
                  (tipGame.game.scoring!.getGameResultCalculated(game.league) ==
                          GameResult.e &&
                      tipGame.tip == GameResult.e)
              ? 1
              : 0;

          if (tipGame.game.league == League.afl) {
            proposedRoundScores.aflMarginUPS += marginUPS;
          } else {
            proposedRoundScores.nrlMarginUPS += marginUPS;
          }
        }
      }
    }

    return proposedRoundScores;
  }

  Future<void> _rankTippers() async {
    if (_allTipperRoundScores.isEmpty) {
      return;
    }

    List<Tipper> tippers =
        await _getTippersToUpdate(null, di<TippersViewModel>(), currentDAUComp);

    // log how many tippers we are ranking
    log('Ranking ${tippers.length} tippers for comp: ${currentDAUComp.dbkey}');

    for (var roundIndex = 0;
        roundIndex < currentDAUComp.daurounds.length;
        roundIndex++) {
      List<MapEntry<Tipper, int>> roundScores = [];

      for (var tipper in tippers) {
        if (_allTipperRoundScores[tipper] == null ||
            _allTipperRoundScores[tipper]![roundIndex] == null) {
          log('No scores for tipper ${tipper.name} in round $roundIndex');
          continue;
        }
        roundScores.add(MapEntry(
            tipper,
            _allTipperRoundScores[tipper]![roundIndex]!.aflScore +
                _allTipperRoundScores[tipper]![roundIndex]!.nrlScore));
      }

      roundScores.sort((a, b) => b.value.compareTo(a.value));

      int rank = 1;
      int? lastScore;
      int sameRankCount = 0;

      for (var entry in roundScores) {
        if (lastScore != null && entry.value != lastScore) {
          rank += sameRankCount + 1;
          sameRankCount = 0;
        } else if (lastScore != null && entry.value == lastScore) {
          sameRankCount++;
        }
        _allTipperRoundScores[entry.key]![roundIndex]!.rank = rank;

        if (roundIndex > 0) {
          int? lastRank =
              _allTipperRoundScores[entry.key]![roundIndex - 1]!.rank;
          int? changeInRank = lastRank - rank;
          _allTipperRoundScores[entry.key]![roundIndex]!.rankChange =
              changeInRank;
        }
        lastScore = entry.value;
      }
    }
  }

  @override
  void dispose() {
    _allRoundScoresStream.cancel();
    _liveScoresStream.cancel();
    super.dispose();
  }
}
