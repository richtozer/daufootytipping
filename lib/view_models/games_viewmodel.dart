import 'dart:async';
import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart'; 
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

const gamesPathRoot = '/DAUCompsGames';

class GamesViewModel extends ChangeNotifier {
  // Properties
  List<Game> _games = [];
  final _db = FirebaseDatabase.instance.ref();
  late StreamSubscription<DatabaseEvent> _gamesStream;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  DAUComp selectedDAUComp;
  late TeamsViewModel _teamsViewModel;
  get teamsViewModel => _teamsViewModel;

  final List<DAURound> _roundsThatNeedScoringUpdate = [];

  final DAUCompsViewModel _dauCompsViewModel;

  bool _isUpdating = false;

  // Constructor
  GamesViewModel(this.selectedDAUComp, this._dauCompsViewModel) {
    _teamsViewModel = TeamsViewModel();
    _initialize();
  }

  // Initialize the view model
  void _initialize() async {
    // await teams load to complete
    await _teamsViewModel.initialLoadComplete;
    // Listen to the games in the selected DAUComp
    _listenToGames();
  }

  // Database listeners
  void _listenToGames() {
    _gamesStream = _db
        .child('$gamesPathRoot/${selectedDAUComp.dbkey}')
        .onValue
        .listen((event) {
      _handleEvent(event);
    });
  }

  void _handleEvent(DatabaseEvent event) {
    if (_isUpdating) {
      log('GamesViewModel_handleEvent: _isUpdating is true. Returning.');
      return; // Prevent re-entrant updates
    }
    _isUpdating = true;
    try {
      if (event.snapshot.exists) {
        final allGames =
            Map<String, dynamic>.from(event.snapshot.value as dynamic);

        // Deserialize the games
        List<Game> gamesList = allGames.entries.map((entry) {
          String dbKey = entry.key; // Retrieve the Firebase key
          String league = dbKey.split('-').first;
          dynamic gameAsJSON = entry.value;

          // Find and deserialize the home and away teams
          Team? homeTeam =
              _teamsViewModel.findTeam('$league-${gameAsJSON['HomeTeam']}');
          Team? awayTeam =
              _teamsViewModel.findTeam('$league-${gameAsJSON['AwayTeam']}');

          if (homeTeam == null || awayTeam == null) {
            throw Exception(
                'Error in GamesViewModel_handleEvent: homeTeam or awayTeam is null');
          }

          Scoring? scoring = Scoring(
              homeTeamScore: gameAsJSON['HomeTeamScore'],
              awayTeamScore: gameAsJSON['AwayTeamScore']);

          Game game = Game.fromJson(
              dbKey, Map<String, dynamic>.from(gameAsJSON), homeTeam, awayTeam);
          game.scoring = scoring;

          return game;
        }).toList();

        _games = gamesList;
        _games.sort();
        log('GamesViewModel_handleEvent: ${_games.length} games found for DAUComp ${selectedDAUComp.name}');
      } else {
        log('No games found for DAUComp ${selectedDAUComp.name}');
      }

      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }

      // Link games with rounds
      _dauCompsViewModel.linkGamesWithRounds(selectedDAUComp.daurounds);
    } catch (e) {
      log('Error in GamesViewModel_handleEvent: $e');
      if (!_initialLoadCompleter.isCompleted) _initialLoadCompleter.complete();
      rethrow;
    } finally {
      notifyListeners();
      log('GamesViewModel_handleEvent: notifyListeners()');
      _isUpdating = false;
    }
  }

  final Map<String, dynamic> updates = {};

  Future<void> updateGameAttribute(String gameDbKey, String attributeName,
      dynamic attributeValue, String league) async {
    await initialLoadComplete;

    //make sure the related team records exist
    if (attributeName == 'HomeTeam' || attributeName == 'AwayTeam') {
      Team team = Team(
          dbkey: '$league-$attributeValue',
          name: attributeValue,
          league: League.values.firstWhere((e) => e.name == league));
      //make sure the related team records exist
      _teamsViewModel.addTeam(team);
    }

    //find the game in the local list. it it's there, compare the attribute value and update if different
    Game? gameToUpdate = await findGame(gameDbKey);
    if (gameToUpdate != null) {
      dynamic oldValue = gameToUpdate.toJson()[attributeName];
      if (attributeValue != oldValue) {
        log('Game: $gameDbKey needs update for attribute $attributeName: $oldValue -> $attributeValue');
        updates['$gamesPathRoot/${selectedDAUComp.dbkey}/$gameDbKey/$attributeName'] =
            attributeValue;
        if (attributeName == 'HomeTeamScore' ||
            attributeName == 'AwayTeamScore') {
          // the score has changed, add the round to the list of rounds that need scoring updates
          // avoid adding rounds multiple times
          // also in the unlikely event we have scores but no rounds defined yet then skip this update
          if (selectedDAUComp.daurounds.isEmpty) {
            log('Game: $gameDbKey has scores but there are no rounds defined. Skipping scoring update.');
            return;
          }
          final round = gameToUpdate.getDAURound(selectedDAUComp);
          if (round != null && !_roundsThatNeedScoringUpdate.contains(round)) {
            _roundsThatNeedScoringUpdate
                .add(gameToUpdate.getDAURound(selectedDAUComp)!);
            // also force a gamestats update - in normal processing this should be the initial calcation
            di<StatsViewModel>().getGamesStatsEntry(gameToUpdate, true);
          }
        }
      }
    } else {
      log('Game: $gameDbKey not found in local list. adding full game record');
      // add new record to updates Map
      updates['$gamesPathRoot/${selectedDAUComp.dbkey}/$gameDbKey/$attributeName'] =
          attributeValue;
    }
  }

  Future<void> saveBatchOfGameAttributes() async {
    if (_isUpdating) return; // Prevent re-entrant updates
    _isUpdating = true;
    try {
      // check if there are any updates to save
      if (updates.isEmpty) {
        log('GamesViewModel_saveBatchOfGameAttributes: no updates to save');
        return;
      }
      await initialLoadComplete;
      // turn off listeners
      _gamesStream.cancel();
      await _db.update(updates);
      // turn listeners back on
      _listenToGames();

      // if any game scores have changes, the round will be flagged for scoring
      // update in List<DAURound> _roundsThatNeedScoringUpdate
      // update the round scores then remove the round from the list
      for (DAURound dauRound in _roundsThatNeedScoringUpdate) {
        log('GamesViewModel_saveBatchOfGameAttributes: updating scoring for round ${dauRound.dAUroundNumber}');
        await di<StatsViewModel>().updateStats(selectedDAUComp, dauRound, null);
      }
      // clear the list
      _roundsThatNeedScoringUpdate.clear();
    } finally {
      log('GamesViewModel_saveBatchOfGameAttributes: notifyListeners()');
      _isUpdating = false;
    }
  }

  Future<List<Game>> getGames() async {
    await initialLoadComplete;
    return _games;
  }

  Future<Game?> findGame(String gameDbKey) async {
    await initialLoadComplete;
    return _games.firstWhereOrNull((game) => game.dbkey == gameDbKey);
  }

  Future<List<Game>> getGamesForRound(DAURound dauRound) async {
    await initialLoadComplete;

    List<Game> gamesForRound =
        _games.where((game) => (game.isGameInRound(dauRound))).toList();

    // loop through the games and remove any where the startTimeUTC is past aflRegularCompEndDateUTC or nrlRegularCompEndDateUTC
    removeGamesOutsideRegularComp(gamesForRound);

    return gamesForRound;
  }

  void removeGamesOutsideRegularComp(List<Game> gamesForRound) {
    // loop through the games and remove any where the startTimeUTC is past aflRegularCompEndDateUTC or nrlRegularCompEndDateUTC
    gamesForRound.removeWhere((game) {
      bool shouldRemove = false;

      if (game.league == League.afl &&
          selectedDAUComp.aflRegularCompEndDateUTC != null) {
        shouldRemove = game.startTimeUTC
            .isAfter(selectedDAUComp.aflRegularCompEndDateUTC!);
      } else if (game.league == League.nrl &&
          selectedDAUComp.nrlRegularCompEndDateUTC != null) {
        shouldRemove = game.startTimeUTC
            .isAfter(selectedDAUComp.nrlRegularCompEndDateUTC!);
      }

      if (shouldRemove) {
        log('removeGamesOutsideRegularComp() Removing game: ${game.dbkey}, Start Time: ${game.startTimeUTC}');
      }

      return shouldRemove;
    });
  }

  @override
  void dispose() {
    _gamesStream.cancel(); // stop listening to stream
    super.dispose();
  }

  // Helper method to calculate ladder points for a game
  int _calculateLadderPoints(Game game, Team targetTeam, League league) {
    bool isHomeTeam = game.homeTeam.dbkey == targetTeam.dbkey;
    // Ensure scores are not null before accessing them
    int targetScore = isHomeTeam ? game.scoring!.homeTeamScore! : game.scoring!.awayTeamScore!;
    int opponentScore = isHomeTeam ? game.scoring!.awayTeamScore! : game.scoring!.homeTeamScore!;

    if (targetScore > opponentScore) { // Target team won
      return league == League.afl ? 4 : 2;
    } else if (targetScore < opponentScore) { // Target team lost
      return 0;
    } else { // Draw
      return league == League.afl ? 2 : 1;
    }
  }

  // Helper method to determine the result string (W, L, D)
  String _determineResult(Game game, Team targetTeam) {
    bool isHomeTeam = game.homeTeam.dbkey == targetTeam.dbkey;
    // Ensure scores are not null
    int targetScore = isHomeTeam ? game.scoring!.homeTeamScore! : game.scoring!.awayTeamScore!;
    int opponentScore = isHomeTeam ? game.scoring!.awayTeamScore! : game.scoring!.homeTeamScore!;

    if (targetScore > opponentScore) return "W";
    if (targetScore < opponentScore) return "L";
    return "D";
  }

  Future<List<TeamGameHistoryItem>> getTeamGameHistory(Team targetTeam, League league) async {
    await initialLoadComplete;

    List<TeamGameHistoryItem> historyItems = [];

    // Filter games
    List<Game> relevantGames = _games.where((game) {
      bool isTargetTeamInvolved = game.homeTeam.dbkey == targetTeam.dbkey || game.awayTeam.dbkey == targetTeam.dbkey;
      bool isCorrectLeague = game.league == league;
      bool hasScores = game.scoring != null && game.scoring!.homeTeamScore != null && game.scoring!.awayTeamScore != null;
      return isTargetTeamInvolved && isCorrectLeague && hasScores;
    }).toList();

    // Process filtered games
    for (Game game in relevantGames) {
      Team opponentTeam;
      int teamScore;
      int opponentScore;

      if (game.homeTeam.dbkey == targetTeam.dbkey) {
        opponentTeam = game.awayTeam;
        teamScore = game.scoring!.homeTeamScore!;
        opponentScore = game.scoring!.awayTeamScore!;
      } else {
        opponentTeam = game.homeTeam;
        teamScore = game.scoring!.awayTeamScore!;
        opponentScore = game.scoring!.homeTeamScore!;
      }

      String result = _determineResult(game, targetTeam);
      int ladderPoints = _calculateLadderPoints(game, targetTeam, league);

      historyItems.add(
        TeamGameHistoryItem(
          opponentName: opponentTeam.name,
          opponentLogoUri: opponentTeam.logoURI,
          teamScore: teamScore,
          opponentScore: opponentScore,
          result: result,
          ladderPoints: ladderPoints,
          gameDate: game.startTimeUTC,
          roundNumber: game.fixtureRoundNumber,
        ),
      );
    }

    // Sort results by gameDate in descending order
    historyItems.sort((a, b) => b.gameDate.compareTo(a.gameDate));

    return historyItems;
  }

  List<Game> _filterGamesForMatchup(List<Game> games, Team teamA, Team teamB, League league) {
    return games.where((game) {
      bool isCorrectLeague = game.league == league;
      bool hasScores = game.scoring != null && game.scoring!.homeTeamScore != null && game.scoring!.awayTeamScore != null;
      bool teamsInvolved = (game.homeTeam.dbkey == teamA.dbkey && game.awayTeam.dbkey == teamB.dbkey) ||
                           (game.homeTeam.dbkey == teamB.dbkey && game.awayTeam.dbkey == teamA.dbkey);
      return isCorrectLeague && hasScores && teamsInvolved;
    }).toList();
  }
  
  Future<List<Game>> _fetchGamesForDAUCompKey(String dauCompDbKey) async {
    log('GamesViewModel_fetchGamesForDAUCompKey: Fetching games for DAUComp key $dauCompDbKey');
    
    // Testability hook: If testGamesByCompKey is set and contains data for this key, return it.
    if (testGamesByCompKey != null && testGamesByCompKey!.containsKey(dauCompDbKey)) {
      log('GamesViewModel_fetchGamesForDAUCompKey: Using test data for DAUComp key $dauCompDbKey');
      final testGames = testGamesByCompKey![dauCompDbKey]!;
      return Future.value(List<Game>.from(testGames)); // Return a copy
    }

    List<Game> fetchedGames = [];
    try {
      await _teamsViewModel.initialLoadComplete; // Ensure teams are ready for deserialization

      final event = await _db.child('$gamesPathRoot/$dauCompDbKey').once();
      if (event.snapshot.exists) {
        final allGamesData = Map<String, dynamic>.from(event.snapshot.value as dynamic);
        
        fetchedGames = allGamesData.entries.map((entry) {
          String gameDbKey = entry.key;
          String leagueName = gameDbKey.split('-').first; 
          dynamic gameAsJSON = entry.value;

          Team? homeTeam = _teamsViewModel.findTeam('$leagueName-${gameAsJSON['HomeTeam']}');
          Team? awayTeam = _teamsViewModel.findTeam('$leagueName-${gameAsJSON['AwayTeam']}');

          if (homeTeam == null || awayTeam == null) {
            log('GamesViewModel_fetchGamesForDAUCompKey: Warning - homeTeam or awayTeam is null for game $gameDbKey in DAUComp $dauCompDbKey. Skipping game.');
            return null; 
          }

          Scoring? scoring = Scoring(
            homeTeamScore: gameAsJSON['HomeTeamScore'],
            awayTeamScore: gameAsJSON['AwayTeamScore'],
          );

          Game game = Game.fromJson(gameDbKey, Map<String, dynamic>.from(gameAsJSON), homeTeam, awayTeam);
          game.scoring = scoring;
          return game;
        }).whereType<Game>().toList(); 

        log('GamesViewModel_fetchGamesForDAUCompKey: Found ${fetchedGames.length} games for DAUComp $dauCompDbKey from Firebase');
      } else {
        log('GamesViewModel_fetchGamesForDAUCompKey: No games found for DAUComp $dauCompDbKey from Firebase');
      }
    } catch (e) {
      log('GamesViewModel_fetchGamesForDAUCompKey: Error fetching games for DAUComp $dauCompDbKey: $e');
    }
    return fetchedGames;
  }

  Future<List<Game>> getCompleteMatchupHistory(Team teamA, Team teamB, League league) async {
    log('GamesViewModel_getCompleteMatchupHistory: Called for ${teamA.name} vs ${teamB.name}, league ${league.name}');
    await initialLoadComplete; 
    await _teamsViewModel.initialLoadComplete; 

    List<Game> allMatchupGames = [];
    
    await _dauCompsViewModel.initialDAUCompLoadComplete; 
    List<DAUComp> allDAUComps = _dauCompsViewModel.daucomps;

    log('GamesViewModel_getCompleteMatchupHistory: Found ${allDAUComps.length} DAUComps to check.');

    for (DAUComp dauComp in allDAUComps) {
      if (dauComp.dbkey == null) {
        log('GamesViewModel_getCompleteMatchupHistory: Skipping a DAUComp with null dbkey.');
        continue;
      }
      log('GamesViewModel_getCompleteMatchupHistory: Fetching games for DAUComp ${dauComp.name} (${dauComp.dbkey!})');
      List<Game> gamesFromThisDAUComp = await _fetchGamesForDAUCompKey(dauComp.dbkey!);
      List<Game> filteredGames = _filterGamesForMatchup(gamesFromThisDAUComp, teamA, teamB, league);
      allMatchupGames.addAll(filteredGames);
      log('GamesViewModel_getCompleteMatchupHistory: Added ${filteredGames.length} games from DAUComp ${dauComp.name}. Total matchups so far: ${allMatchupGames.length}');
    }

    allMatchupGames.sort((a, b) => b.startTimeUTC.compareTo(a.startTimeUTC));
    log('GamesViewModel_getCompleteMatchupHistory: Total ${allMatchupGames.length} matchup games found across all DAUComps.');
    return allMatchupGames;
  }

  Future<List<Game>> getMatchupHistory(Team teamA, Team teamB, League league) async {
    await initialLoadComplete;

    List<Game> relevantGames = _filterGamesForMatchup(_games, teamA, teamB, league);

    relevantGames.sort((a, b) => b.startTimeUTC.compareTo(a.startTimeUTC));

    return relevantGames;
  }

  // --- Testability additions ---
  @visibleForTesting
  set testGames(List<Game> games) {
    _games = games;
    _games.sort(); 
  }

  @visibleForTesting
  void completeInitialLoadForTest() {
    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }
  }

  @visibleForTesting
  Map<String, List<Game>>? testGamesByCompKey;
  // --- End Testability additions ---
}
