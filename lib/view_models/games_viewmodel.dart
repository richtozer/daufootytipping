import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/auth_aware_stream.dart';
import 'package:daufootytipping/services/crashlytics_error_classifier.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class GamesViewModel extends ChangeNotifier {
  // Properties
  List<Game> _games = [];
  final DatabaseReference _db;
  final Stream<bool> Function() _signedIn;
  late StreamSubscription<DatabaseEvent> _gamesStream;
  Future<void> _gamesSnapshotProcessing = Future<void>.value();

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  DAUComp selectedDAUComp;
  late TeamsViewModel _teamsViewModel;
  final bool _ownsTeamsViewModel;
  TeamsViewModel get teamsViewModel => _teamsViewModel;

  final DAUCompsViewModel _dauCompsViewModel;

  // Constructor
  GamesViewModel(
    this.selectedDAUComp,
    this._dauCompsViewModel, {
    TeamsViewModel? teamsViewModel,
    DatabaseReference? database,
    bool autoInitialize = true,
    Stream<bool> Function()? signedIn,
  }) : _ownsTeamsViewModel =
           teamsViewModel == null && !di.isRegistered<TeamsViewModel>(),
       _db = database ?? configuredDatabaseRef(),
       _signedIn = signedIn ?? firebaseSignedInStream {
    _teamsViewModel =
        teamsViewModel ??
        (di.isRegistered<TeamsViewModel>()
            ? di<TeamsViewModel>()
            : TeamsViewModel());
    if (autoInitialize) {
      _initialize();
    }
  }

  // Initialize the view model
  void _initialize() async {
    // await teams load to complete
    await _teamsViewModel.initialLoadComplete;
    // await dauComps load to complete
    await _dauCompsViewModel.initialDAUCompLoadComplete;
    // Listen to the games in the selected DAUComp
    _listenToGames();
  }

  /// A refusal of the games listener while a user is signed in is a real fault (the
  /// rules or the data), so a release build reports it to Crashlytics, without
  /// ending the session. Signing out closes the listener before the server can
  /// refuse it (see [authAwareStream]), and a dropped connection is not a fault,
  /// so neither is reported.
  void _reportSignedInListenerFailure(Object error, StackTrace stackTrace) {
    if (kDebugMode ||
        FirebaseAuth.instance.currentUser == null ||
        CrashlyticsErrorClassifier.isTransientRealtimeDatabaseDisconnect(
          error,
        )) {
      return;
    }
    unawaited(
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        fatal: false,
        reason: 'Games listener failed while signed in',
      ),
    );
  }

  // Database listeners
  void _listenToGames() {
    final DatabaseReference gamesReference = _db.child(_gamesPath);
    _gamesStream =
        authAwareStream<DatabaseEvent>(
          signedIn: _signedIn,
          open: () => gamesReference.onValue,
          onSourceError: (Object error, StackTrace stackTrace) {
            log(
              'GamesViewModel: games listener failed',
              error: error,
              stackTrace: stackTrace,
            );
            _reportSignedInListenerFailure(error, stackTrace);
          },
        ).listen((event) {
          _queueGamesSnapshotProcessing(event.snapshot);
        });
  }

  String get _gamesPath => '${p.gamesPathRoot}/${selectedDAUComp.dbkey}';

  void _queueGamesSnapshotProcessing(DataSnapshot snapshot) {
    _gamesSnapshotProcessing = _gamesSnapshotProcessing
        .catchError((Object error, StackTrace stackTrace) {
          log('GamesViewModel_handleEvent: recovering after error: $error');
        })
        .then((_) => _applyGamesSnapshot(snapshot));
  }

  Future<void> _applyGamesSnapshot(DataSnapshot snapshot) async {
    try {
      final bool isFirstLoad = !_initialLoadCompleter.isCompleted;
      final dynamic rawValue = snapshot.value;
      final int entryCount = rawValue is Map ? rawValue.length : 0;
      final int? payloadBytes = StartupProfiling.estimatePayloadBytes(rawValue);
      StartupProfiling.instant(
        'startup.games_snapshot_received',
        arguments: <String, Object?>{
          'exists': snapshot.exists,
          'entryCount': entryCount,
          'payloadBytes': payloadBytes ?? -1,
          'firstLoad': isFirstLoad,
          'compDbKey': selectedDAUComp.dbkey ?? 'unknown',
        },
      );
      if (snapshot.exists) {
        final allGames = Map<String, dynamic>.from(snapshot.value as dynamic);

        // Deserialize the games
        List<Game> gamesList = allGames.entries.map((entry) {
          String dbKey = entry.key; // Retrieve the Firebase key
          String league = dbKey.split('-').first;
          dynamic gameAsJSON = entry.value;

          // Find and deserialize the home and away teams
          Team? homeTeam = _teamsViewModel.findTeam(
            '$league-${gameAsJSON['HomeTeam']}',
          );
          Team? awayTeam = _teamsViewModel.findTeam(
            '$league-${gameAsJSON['AwayTeam']}',
          );

          if (homeTeam == null || awayTeam == null) {
            throw Exception(
              'Error in GamesViewModel_handleEvent: homeTeam or awayTeam is null',
            );
          }

          Scoring? scoring = Scoring(
            homeTeamScore: gameAsJSON['HomeTeamScore'],
            awayTeamScore: gameAsJSON['AwayTeamScore'],
          );

          Game game = Game.fromJson(
            dbKey,
            Map<String, dynamic>.from(gameAsJSON),
            homeTeam,
            awayTeam,
          );
          game.scoring = scoring;

          return game;
        }).toList();

        final configuredSeasonYear = selectedDAUComp.configuredSeasonYear();
        if (configuredSeasonYear != null) {
          final filteredGames = gamesList
              .where((game) => game.startTimeUTC.year == configuredSeasonYear)
              .toList();
          final droppedGamesCount = gamesList.length - filteredGames.length;
          if (droppedGamesCount > 0) {
            log(
              'GamesViewModel_handleEvent: ignored $droppedGamesCount out-of-season game(s) for ${selectedDAUComp.name} (${selectedDAUComp.dbkey}) while loading configured season $configuredSeasonYear.',
            );
          }
          gamesList = filteredGames;
        }

        gamesList.sort();
        _games = gamesList;
        log(
          'GamesViewModel_handleEvent: ${_games.length} games found for DAUComp ${selectedDAUComp.name}',
        );
      } else {
        log('No games found for DAUComp ${selectedDAUComp.name}');
      }

      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
        StartupProfiling.instant(
          'startup.games_initial_load_complete',
          arguments: <String, Object?>{
            'gameCount': _games.length,
            'compDbKey': selectedDAUComp.dbkey ?? 'unknown',
          },
        );
      }

      // Link games with rounds
      await _dauCompsViewModel.linkGamesWithRounds(selectedDAUComp.daurounds);
    } catch (e) {
      log('Error in GamesViewModel_handleEvent: $e');
      if (!_initialLoadCompleter.isCompleted) _initialLoadCompleter.complete();
      rethrow;
    } finally {
      notifyListeners();
      log('GamesViewModel_handleEvent: notifyListeners()');
    }
  }

  Future<List<Game>> getGames() async {
    await initialLoadComplete;
    return _games;
  }

  Future<void> refreshFromServer() async {
    await _teamsViewModel.initialLoadComplete;
    await _dauCompsViewModel.initialDAUCompLoadComplete;
    final DataSnapshot snapshot = await _db.child(_gamesPath).get();
    await _applyGamesSnapshot(snapshot);
  }

  void liveScoresUpdated() {
    notifyListeners();
  }

  Future<Game?> findGame(String gameDbKey) async {
    await initialLoadComplete;
    return _games.firstWhereOrNull((game) => game.dbkey == gameDbKey);
  }

  Future<List<Game>> getGamesForRound(DAURound dauRound) async {
    await initialLoadComplete;

    List<Game> gamesForRound = _games
        .where(
          (game) =>
              game.getDAURound(selectedDAUComp)?.dAUroundNumber ==
              dauRound.dAUroundNumber,
        )
        .toList();

    return gamesForRound;
  }

  // Helper method to calculate ladder points for a game
  int _calculateLadderPoints(Game game, Team targetTeam, League league) {
    bool isHomeTeam = game.homeTeam.dbkey == targetTeam.dbkey;
    // Ensure scores are not null before accessing them
    int targetScore = isHomeTeam
        ? game.scoring!.homeTeamScore!
        : game.scoring!.awayTeamScore!;
    int opponentScore = isHomeTeam
        ? game.scoring!.awayTeamScore!
        : game.scoring!.homeTeamScore!;

    if (targetScore > opponentScore) {
      // Target team won
      return league == League.afl ? 4 : 2;
    } else if (targetScore < opponentScore) {
      // Target team lost
      return 0;
    } else {
      // Draw
      return league == League.afl ? 2 : 1;
    }
  }

  // Helper method to determine the result string (W, L, D)
  String _determineResult(Game game, Team targetTeam) {
    bool isHomeTeam = game.homeTeam.dbkey == targetTeam.dbkey;
    // Ensure scores are not null
    int targetScore = isHomeTeam
        ? game.scoring!.homeTeamScore!
        : game.scoring!.awayTeamScore!;
    int opponentScore = isHomeTeam
        ? game.scoring!.awayTeamScore!
        : game.scoring!.homeTeamScore!;

    if (targetScore > opponentScore) return "Won";
    if (targetScore < opponentScore) return "Lost";
    return "Draw";
  }

  Future<List<TeamGameHistoryItem>> getTeamGameHistory(
    Team targetTeam,
    League league,
  ) async {
    await initialLoadComplete;

    List<TeamGameHistoryItem> historyItems = [];

    // Filter games
    List<Game> relevantGames = _games.where((game) {
      bool isTargetTeamInvolved =
          game.homeTeam.dbkey == targetTeam.dbkey ||
          game.awayTeam.dbkey == targetTeam.dbkey;
      bool isCorrectLeague = game.league == league;
      bool hasScores =
          game.scoring != null &&
          game.scoring!.homeTeamScore != null &&
          game.scoring!.awayTeamScore != null;
      return isTargetTeamInvolved && isCorrectLeague && hasScores;
    }).toList();

    // Process filtered games
    for (Game game in relevantGames) {
      Team opponentTeam;
      int teamScore;
      int opponentScore;
      bool isHomeGame;

      if (game.homeTeam.dbkey == targetTeam.dbkey) {
        opponentTeam = game.awayTeam;
        teamScore = game.scoring!.homeTeamScore!;
        opponentScore = game.scoring!.awayTeamScore!;
        isHomeGame = true;
      } else {
        opponentTeam = game.homeTeam;
        teamScore = game.scoring!.awayTeamScore!;
        opponentScore = game.scoring!.homeTeamScore!;
        isHomeGame = false;
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
          competitionName:
              null, // Current year method doesn't have competition name
          isHomeGame: isHomeGame,
        ),
      );
    }

    // Sort results by gameDate in descending order
    historyItems.sort((a, b) => b.gameDate.compareTo(a.gameDate));

    return historyItems;
  }

  Future<List<TeamGameHistoryItem>> getCompleteTeamGameHistory(
    Team targetTeam,
    League league,
  ) async {
    await initialLoadComplete;
    await _teamsViewModel.initialLoadComplete;

    List<TeamGameHistoryItem> historyItems = [];
    List<DAUComp> allDAUComps = _dauCompsViewModel.daucomps;

    for (DAUComp dauComp in allDAUComps) {
      if (dauComp.dbkey == null) continue;

      List<Game> gamesFromThisDAUComp = await _fetchGamesForDAUCompKey(
        dauComp.dbkey!,
      );

      // Filter games for the target team
      List<Game> relevantGames = gamesFromThisDAUComp.where((game) {
        bool isTargetTeamInvolved =
            game.homeTeam.dbkey == targetTeam.dbkey ||
            game.awayTeam.dbkey == targetTeam.dbkey;
        bool isCorrectLeague = game.league == league;
        bool hasScores =
            game.scoring != null &&
            game.scoring!.homeTeamScore != null &&
            game.scoring!.awayTeamScore != null;
        return isTargetTeamInvolved && isCorrectLeague && hasScores;
      }).toList();

      // Process filtered games
      for (Game game in relevantGames) {
        Team opponentTeam;
        int teamScore;
        int opponentScore;
        bool isHomeGame;

        if (game.homeTeam.dbkey == targetTeam.dbkey) {
          opponentTeam = game.awayTeam;
          teamScore = game.scoring!.homeTeamScore!;
          opponentScore = game.scoring!.awayTeamScore!;
          isHomeGame = true;
        } else {
          opponentTeam = game.homeTeam;
          teamScore = game.scoring!.awayTeamScore!;
          opponentScore = game.scoring!.homeTeamScore!;
          isHomeGame = false;
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
            competitionName:
                dauComp.name, // Add competition name for year grouping
            isHomeGame: isHomeGame,
          ),
        );
      }
    }

    // Sort results by gameDate in descending order
    historyItems.sort((a, b) => b.gameDate.compareTo(a.gameDate));

    return historyItems;
  }

  List<Game> _filterGamesForMatchup(
    List<Game> games,
    Team teamA,
    Team teamB,
    League league,
  ) {
    return games.where((game) {
      bool isCorrectLeague = game.league == league;
      bool hasScores =
          game.scoring != null &&
          game.scoring!.homeTeamScore != null &&
          game.scoring!.awayTeamScore != null;
      bool teamsInvolved =
          (game.homeTeam.dbkey == teamA.dbkey &&
              game.awayTeam.dbkey == teamB.dbkey) ||
          (game.homeTeam.dbkey == teamB.dbkey &&
              game.awayTeam.dbkey == teamA.dbkey);
      return isCorrectLeague && hasScores && teamsInvolved;
    }).toList();
  }

  final Map<String, List<Game>> _gamesByDAUCompKeyCache = {};

  Future<List<Game>> _fetchGamesForDAUCompKey(String dauCompDbKey) async {
    log(
      'GamesViewModel_fetchGamesForDAUCompKey: Fetching games for DAUComp key $dauCompDbKey',
    );

    if (_gamesByDAUCompKeyCache.containsKey(dauCompDbKey)) {
      return _gamesByDAUCompKeyCache[dauCompDbKey]!;
    }

    // Testability hook: If testGamesByCompKey is set and contains data for this key, return it.
    if (testGamesByCompKey != null &&
        testGamesByCompKey!.containsKey(dauCompDbKey)) {
      log(
        'GamesViewModel_fetchGamesForDAUCompKey: Using test data for DAUComp key $dauCompDbKey',
      );
      final testGames = testGamesByCompKey![dauCompDbKey]!;
      return Future.value(List<Game>.from(testGames)); // Return a copy
    }

    List<Game> fetchedGames = [];
    try {
      await _teamsViewModel
          .initialLoadComplete; // Ensure teams are ready for deserialization

      final event = await _db.child('${p.gamesPathRoot}/$dauCompDbKey').once();
      if (event.snapshot.exists) {
        final allGamesData = Map<String, dynamic>.from(
          event.snapshot.value as dynamic,
        );

        fetchedGames = allGamesData.entries
            .map((entry) {
              String gameDbKey = entry.key;
              String leagueName = gameDbKey.split('-').first;
              dynamic gameAsJSON = entry.value;

              Team? homeTeam = _teamsViewModel.findTeam(
                '$leagueName-${gameAsJSON['HomeTeam']}',
              );
              Team? awayTeam = _teamsViewModel.findTeam(
                '$leagueName-${gameAsJSON['AwayTeam']}',
              );

              if (homeTeam == null || awayTeam == null) {
                log(
                  'GamesViewModel_fetchGamesForDAUCompKey: Warning - homeTeam or awayTeam is null for game $gameDbKey in DAUComp $dauCompDbKey. Skipping game.',
                );
                return null;
              }

              Scoring? scoring = Scoring(
                homeTeamScore: gameAsJSON['HomeTeamScore'],
                awayTeamScore: gameAsJSON['AwayTeamScore'],
              );

              Game game = Game.fromJson(
                gameDbKey,
                Map<String, dynamic>.from(gameAsJSON),
                homeTeam,
                awayTeam,
              );
              game.scoring = scoring;
              return game;
            })
            .whereType<Game>()
            .toList();

        log(
          'GamesViewModel_fetchGamesForDAUCompKey: Found ${fetchedGames.length} games for DAUComp $dauCompDbKey from Firebase',
        );
      } else {
        log(
          'GamesViewModel_fetchGamesForDAUCompKey: No games found for DAUComp $dauCompDbKey from Firebase',
        );
      }
    } catch (e) {
      log(
        'GamesViewModel_fetchGamesForDAUCompKey: Error fetching games for DAUComp $dauCompDbKey: $e',
      );
    }
    _gamesByDAUCompKeyCache[dauCompDbKey] = fetchedGames;
    return fetchedGames;
  }

  Future<List<Game>> getCompleteMatchupHistory(
    Team teamA,
    Team teamB,
    League league,
  ) async {
    log(
      'GamesViewModel_getCompleteMatchupHistory: Called for ${teamA.name} vs ${teamB.name}, league ${league.name}',
    );

    await initialLoadComplete;
    await _teamsViewModel.initialLoadComplete;

    List<Game> allMatchupGames = [];

    //await _dauCompsViewModel.initialDAUCompLoadComplete;
    List<DAUComp> allDAUComps = _dauCompsViewModel.daucomps;

    log(
      'GamesViewModel_getCompleteMatchupHistory: Found ${allDAUComps.length} DAUComps to check.',
    );

    for (DAUComp dauComp in allDAUComps) {
      if (dauComp.dbkey == null) {
        log(
          'GamesViewModel_getCompleteMatchupHistory: Skipping a DAUComp with null dbkey.',
        );
        continue;
      }
      log(
        'GamesViewModel_getCompleteMatchupHistory: Fetching games for DAUComp ${dauComp.name} (${dauComp.dbkey!})',
      );
      List<Game> gamesFromThisDAUComp = await _fetchGamesForDAUCompKey(
        dauComp.dbkey!,
      );
      List<Game> filteredGames = _filterGamesForMatchup(
        gamesFromThisDAUComp,
        teamA,
        teamB,
        league,
      );
      allMatchupGames.addAll(filteredGames);
      log(
        'GamesViewModel_getCompleteMatchupHistory: Added ${filteredGames.length} games from DAUComp ${dauComp.name}. Total matchups so far: ${allMatchupGames.length}',
      );
    }

    allMatchupGames.sort((a, b) => b.startTimeUTC.compareTo(a.startTimeUTC));
    log(
      'GamesViewModel_getCompleteMatchupHistory: Total ${allMatchupGames.length} matchup games found across all DAUComps.',
    );
    return allMatchupGames;
  }

  Future<List<Game>> getMatchupHistory(
    Team teamA,
    Team teamB,
    League league,
  ) async {
    await initialLoadComplete;

    List<Game> relevantGames = _filterGamesForMatchup(
      _games,
      teamA,
      teamB,
      league,
    );

    relevantGames.sort((a, b) => b.startTimeUTC.compareTo(a.startTimeUTC));

    return relevantGames;
  }

  @override
  void dispose() {
    unawaited(_gamesStream.cancel());
    if (_ownsTeamsViewModel) {
      _teamsViewModel.dispose();
    }
    super.dispose();
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
