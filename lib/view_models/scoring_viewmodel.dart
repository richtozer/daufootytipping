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

  // void update() {
  //   notifyListeners(); // Notify our consumers that the data may have changed to the parent gamesviewmodel.games data
  // }

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

        List<MapEntry<Tipper, Map<int, RoundScores>>> entries =
            (await Future.wait(
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
              log('Tipper ${entry.key} does not exist in _handleEventRoundScores');
              return null;
            }
          }),
        ))
                .where((item) => item != null)
                .toList()
                .cast<MapEntry<Tipper, Map<int, RoundScores>>>();

        _allTipperRoundScores = Map.fromEntries(entries);
      } else {
        log('Snapshot ${event.snapshot.ref.path} does not exist in _handleEventRoundScores');
      }

      if (!_initialRoundLoadCompleted.isCompleted) {
        _initialRoundLoadCompleted.complete();
      }

      // update the leaderboard
      _updateLeaderboardForComp();
      // Update the round winners
      _updateRoundWinners();

      notifyListeners();
    } catch (e) {
      log('Error listening to /Scores/round_scores: $e');

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

          notifyListeners();
        }
      }
    } catch (e) {
      log('Error listening to /Scores/live_scores: $e');
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
      TipsViewModel allTipsViewModel = di<TipsViewModel>();

      List<Tipper> tippersToUpdate = await _getTippersToUpdate(
          onlyUpdateThisTipper, tippersViewModel, daucompToUpdate);

      // when a tipper is no longer active in the comp then remove their scores from the database
      await _removeScoresInactiveTippers(tippersToUpdate, daucompToUpdate);

      var dauRoundsEdited =
          _getRoundsToUpdate(onlyUpdateThisRound, daucompToUpdate);

      // Check for any scoring changes for each tipper
      Map<Tipper, Map<int, RoundScores>> changedTippers = {};

      for (Tipper tipperToScore in tippersToUpdate) {
        for (DAURound dauRound in dauRoundsEdited) {
          RoundScores newScores = await _calculateRoundScoresForTipper(
              tipperToScore, dauRound, allTipsViewModel);

          if (_allTipperRoundScores[tipperToScore] == null ||
              _allTipperRoundScores[tipperToScore]![
                      dauRound.dAUroundNumber - 1] !=
                  newScores) {
            changedTippers[tipperToScore] ??= {};
            changedTippers[tipperToScore]![dauRound.dAUroundNumber - 1] =
                newScores;
          }
        }
      }

      // Only write changed scores to the database
      if (changedTippers.isNotEmpty) {
        await _writeRoundScoresToDb(changedTippers, daucompToUpdate);
      }

      String res =
          'Completed scoring updates for ${tippersToUpdate.length} tippers and ${dauRoundsEdited.length} rounds.';
      log(res);

      stopwatch.stop();
      log('updateScoring executed in ${stopwatch.elapsed}');

      _isScoring = false;
      notifyListeners();

      return res;
    } catch (e) {
      _isScoring = false;
      rethrow;
    }
  }

  Future<void> _removeScoresInactiveTippers(
      List<Tipper> tippersToUpdate, DAUComp daucompToUpdate) async {
    // when a tipper is no longer active in the comp then remove their scores from the database
    List<Tipper> tippersToRemove = [];
    for (var tipper in _allTipperRoundScores.keys) {
      if (!tippersToUpdate.contains(tipper)) {
        tippersToRemove.add(tipper);
      }
    }

    // iterate through tippersToRemove and remove their scores from the database
    for (var tipper in tippersToRemove) {
      await _db
          .child(scoresPathRoot)
          .child(daucompToUpdate.dbkey!)
          .child(roundScoresRoot)
          .child(tipper.dbkey!)
          .remove();
    }
  }

  Future<void> _writeRoundScoresToDb(
      Map<Tipper, Map<int, RoundScores>> updatedTipperRoundScores,
      DAUComp dauComp) async {
    // turn off the listener to avoid a feedback loop
    _allRoundScoresStream.cancel();

    for (var roundScore in updatedTipperRoundScores.entries) {
      // Prepare the data for update
      final updateData =
          (roundScore.value).map((k, v) => MapEntry(k.toString(), v.toJson()));
      // Generate a map for update to avoid overwriting
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

  void _updateRoundWinners() {
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
            roundNumber: round.key,
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
    notifyListeners();
  }

  void _updateLeaderboardForComp() {
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
        rank: 0, // replace with actual rank calculation - see below
        tipper: e.key,
        total: totalScore,
        nRL: nrlScore,
        aFL: aflScore,
        numRoundsWon: 0, // replace with actual numRoundsWon calculation
        aflMargins: aflMargins,
        aflUPS: aflMarginUps,
        nrlMargins: nrlMargins,
        nrlUPS: nrlMarginUps,
      );
    }).toList();

    //var leaderboard = await Future.wait(leaderboardFutures);
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
      // return the scores for each round, exclude rounds that have not been played yet
      // use getHighestRoundNumberWithAllGamesPlayed to determine the last round with all games played
      // then use that as an index to only return first n rounds in List<RoundScores>
      int latestRoundNumber = di<DAUCompsViewModel>()
          .selectedDAUComp!
          .getHighestRoundNumberWithAllGamesPlayed();

      return _allTipperRoundScores[tipper]!
          .entries
          .where((entry) => entry.key <= latestRoundNumber)
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
    if (_gamesWithLiveScores.contains(game)) {
      game.scoring = game.scoring;
    } else {
      _gamesWithLiveScores.add(game);
    }

    Map<String, Map<String, dynamic>> liveScores = {};
    for (var game in _gamesWithLiveScores) {
      liveScores[game.dbkey] = game.scoring!.toJson();

      await _db
          .child(scoresPathRoot)
          .child(currentDAUComp.dbkey!)
          .child(liveScoresRoot)
          .update(liveScores);
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
        //skip to the next game
        continue;
      }

      if (tipGame.game.gameState != GameState.notStarted ||
          tipGame.game.gameState != GameState.startingSoon) {
        int marginTip =
            (tipGame.tip == GameResult.a || tipGame.tip == GameResult.e)
                ? 1
                : 0;

        tipGame.game.league == League.afl
            ? proposedRoundScores.aflMarginTips += marginTip
            : proposedRoundScores.nrlMarginTips += marginTip;

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

          tipGame.game.league == League.afl
              ? proposedRoundScores.aflMarginUPS += marginUPS
              : proposedRoundScores.nrlMarginUPS += marginUPS;
        }
      }
    }
    return proposedRoundScores;
  }

  void _rankTippers() async {
    for (var roundIndex = 0;
        roundIndex < currentDAUComp.daurounds.length;
        roundIndex++) {
      List<MapEntry<Tipper, int>> roundScores = [];

      List<Tipper> tippers = await _getTippersToUpdate(
          null,
          di<TippersViewModel>(),
          currentDAUComp); // get all tippers for the comp

      for (var tipper in tippers) {
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
