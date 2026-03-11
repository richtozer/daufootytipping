import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tip_history_entry.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';

abstract class TipHistoryRepository {
  Future<List<TipHistoryEntry>> fetchTipHistory(Tipper tipper);

  Future<List<TipHistoryEntry>> fetchCurrentTipHistory(Tipper tipper) async {
    return fetchTipHistory(tipper);
  }
}

abstract class TipHistoryLogSource {
  Future<List<TipHistoryEntry>> fetchTipLogs(TipHistoryLookup lookup);
}

class TipHistoryLookup {
  final String tipperDbKey;
  final String gameId;
  final League league;
  final int year;
  final int roundNumber;
  final List<String> roundKeys;
  final String homeTeamName;
  final String awayTeamName;
  final String? homeTeamLogoUri;
  final String? awayTeamLogoUri;

  const TipHistoryLookup({
    required this.tipperDbKey,
    required this.gameId,
    required this.league,
    required this.year,
    required this.roundNumber,
    required this.roundKeys,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.homeTeamLogoUri,
    required this.awayTeamLogoUri,
  });
}

class FirestoreTipHistoryLogSource implements TipHistoryLogSource {
  final FirebaseFirestore _firestore;

  FirestoreTipHistoryLogSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<TipHistoryEntry>> fetchTipLogs(TipHistoryLookup lookup) async {
    final List<TipHistoryEntry> tipHistoryEntries = <TipHistoryEntry>[];
    final Set<String> seenTipLogIds = <String>{};

    for (final String roundKey in lookup.roundKeys) {
      final QuerySnapshot<Map<String, dynamic>> tipLogSnapshot =
          await _firestore
              .collection('tipLogs')
              .doc(lookup.year.toString())
              .collection(roundKey)
              .doc(lookup.tipperDbKey)
              .collection(lookup.gameId)
              .orderBy('tipSubmittedUTC', descending: true)
              .get();

      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in tipLogSnapshot.docs) {
        if (!seenTipLogIds.add('${lookup.gameId}:${doc.id}')) {
          continue;
        }

        final Map<String, dynamic> data = doc.data();
        final Map<String, dynamic> gameDetails = Map<String, dynamic>.from(
          data['gameDetails'] as Map? ?? <String, dynamic>{},
        );
        final League league = League.values.byName(
          (gameDetails['league'] as String?) ?? lookup.league.name,
        );
        tipHistoryEntries.add(
          TipHistoryEntry(
            gameId: lookup.gameId,
            league: league,
            year: lookup.year,
            roundNumber: lookup.roundNumber,
            homeTeamName:
                (gameDetails['homeTeam'] as String?) ?? lookup.homeTeamName,
            awayTeamName:
                (gameDetails['awayTeam'] as String?) ?? lookup.awayTeamName,
            homeTeamLogoUri: lookup.homeTeamLogoUri,
            awayTeamLogoUri: lookup.awayTeamLogoUri,
            tip: GameResult.values.byName(data['tip'] as String),
            tipSubmittedUTC: DateTime.parse(data['tipSubmittedUTC'] as String),
            submittedBy: data['submittedBy'] as String?,
          ),
        );
      }
    }

    return tipHistoryEntries;
  }
}

class FirestoreTipHistoryRepository implements TipHistoryRepository {
  final List<DAUComp> dauComps;
  final TeamsViewModel teamsViewModel;
  final DatabaseReference _database;
  final TipHistoryLogSource _logSource;

  FirestoreTipHistoryRepository({
    required this.dauComps,
    required this.teamsViewModel,
    DatabaseReference? database,
    TipHistoryLogSource? logSource,
  }) : _database = database ?? FirebaseDatabase.instance.ref(),
       _logSource = logSource ?? FirestoreTipHistoryLogSource();

  @override
  Future<List<TipHistoryEntry>> fetchCurrentTipHistory(Tipper tipper) async {
    await teamsViewModel.initialLoadComplete;
    final List<List<_ResolvedRealtimeTip>> entriesByComp =
        await Future.wait<List<_ResolvedRealtimeTip>>(
      dauComps
          .where((DAUComp dauComp) => dauComp.dbkey != null)
          .map(
            (DAUComp dauComp) => _loadResolvedRealtimeTipsForComp(
              dauComp,
              tipper,
            ),
          ),
    );
    return _sortEntries(
      entriesByComp
          .expand((List<_ResolvedRealtimeTip> entries) => entries)
          .map((_ResolvedRealtimeTip entry) => entry.entry)
          .toList(),
    );
  }

  @override
  Future<List<TipHistoryEntry>> fetchTipHistory(Tipper tipper) async {
    await teamsViewModel.initialLoadComplete;
    final List<List<_ResolvedRealtimeTip>> entriesByComp =
        await Future.wait<List<_ResolvedRealtimeTip>>(
      dauComps
          .where((DAUComp dauComp) => dauComp.dbkey != null)
          .map(
            (DAUComp dauComp) => _loadResolvedRealtimeTipsForComp(
              dauComp,
              tipper,
            ),
          ),
    );
    final List<_ResolvedRealtimeTip> resolvedTips = entriesByComp
        .expand((List<_ResolvedRealtimeTip> entries) => entries)
        .toList();
    final List<List<TipHistoryEntry>> mergedEntries = await Future.wait<
      List<TipHistoryEntry>
    >(
      resolvedTips.map(
        (_ResolvedRealtimeTip resolvedTip) async =>
            _mergeRealtimeTipWithLogEntries(
              resolvedTip.entry,
              await _logSource.fetchTipLogs(resolvedTip.lookup),
            ),
      ),
    );

    return _sortEntries(
      mergedEntries
          .expand((List<TipHistoryEntry> entries) => entries)
          .toList(),
    );
  }

  List<TipHistoryEntry> _sortEntries(List<TipHistoryEntry> entries) {
    entries.sort(
      (TipHistoryEntry a, TipHistoryEntry b) =>
          b.tipSubmittedUTC.compareTo(a.tipSubmittedUTC),
    );
    return entries;
  }

  Future<List<_ResolvedRealtimeTip>> _loadResolvedRealtimeTipsForComp(
    DAUComp dauComp,
    Tipper tipper,
  ) async {
    final String? compDbKey = dauComp.dbkey;
    final String? tipperDbKey = tipper.dbkey;
    if (compDbKey == null || tipperDbKey == null) {
      return const <_ResolvedRealtimeTip>[];
    }

    final DataSnapshot tipsSnapshot = await _database
        .child('${p.tipsPathRoot}/$compDbKey/$tipperDbKey')
        .get();
    if (!tipsSnapshot.exists || tipsSnapshot.value == null) {
      return const <_ResolvedRealtimeTip>[];
    }

    final Map<String, dynamic> tipsData = Map<String, dynamic>.from(
      tipsSnapshot.value as dynamic,
    );
    if (tipsData.isEmpty) {
      return const <_ResolvedRealtimeTip>[];
    }

    final List<_HistoricalGameDescriptor> gamesForComp = await _loadGamesForComp(
      dauComp,
    );
    final Map<String, _HistoricalGameDescriptor> gamesById =
        <String, _HistoricalGameDescriptor>{
          for (final _HistoricalGameDescriptor game in gamesForComp)
            game.gameId: game,
        };

    final List<_ResolvedRealtimeTip> tipHistoryEntries = <_ResolvedRealtimeTip>[];
    for (final MapEntry<String, dynamic> tipEntry in tipsData.entries) {
      final _HistoricalGameDescriptor? game = gamesById[tipEntry.key];
      if (game == null || tipEntry.value is! Map) {
        continue;
      }

      final Tip realtimeTip = Tip.fromJson(
        Map<String, dynamic>.from(tipEntry.value as Map),
        game.gameId,
        tipper,
        game.game,
      );
      if (realtimeTip.isDefaultTip()) {
        continue;
      }

      final TipHistoryEntry realtimeEntry = TipHistoryEntry(
        gameId: game.gameId,
        league: game.league,
        year: game.year,
        roundNumber: game.displayRoundNumber,
        homeTeamName: game.homeTeamName,
        awayTeamName: game.awayTeamName,
        homeTeamLogoUri: game.homeTeamLogoUri,
        awayTeamLogoUri: game.awayTeamLogoUri,
        tip: realtimeTip.tip,
        tipSubmittedUTC: realtimeTip.submittedTimeUTC,
        submittedBy: null,
      );
      tipHistoryEntries.add(
        _ResolvedRealtimeTip(
          entry: realtimeEntry,
          lookup: game.toLookup(tipperDbKey),
        ),
      );
    }

    return tipHistoryEntries;
  }

  List<TipHistoryEntry> _mergeRealtimeTipWithLogEntries(
    TipHistoryEntry realtimeEntry,
    List<TipHistoryEntry> logEntries,
  ) {
    if (logEntries.isEmpty) {
      return <TipHistoryEntry>[realtimeEntry];
    }

    final bool realtimeAlreadyRepresented = logEntries.any(
      (TipHistoryEntry entry) =>
          entry.tip == realtimeEntry.tip &&
          entry.tipSubmittedUTC.toUtc() == realtimeEntry.tipSubmittedUTC.toUtc(),
    );
    if (realtimeAlreadyRepresented) {
      return logEntries;
    }

    return <TipHistoryEntry>[...logEntries, realtimeEntry];
  }

  Future<List<_HistoricalGameDescriptor>> _loadGamesForComp(DAUComp dauComp) async {
    final DataSnapshot gamesSnapshot = await _database
        .child('${p.gamesPathRoot}/${dauComp.dbkey}')
        .get();
    if (!gamesSnapshot.exists) {
      return const <_HistoricalGameDescriptor>[];
    }

    final Map<String, dynamic> allGames = Map<String, dynamic>.from(
      gamesSnapshot.value as dynamic,
    );

    return allGames.entries
        .map((MapEntry<String, dynamic> entry) {
          final String dbKey = entry.key;
          final Map<String, dynamic> gameData = Map<String, dynamic>.from(
            entry.value as dynamic,
          );
          final String leaguePrefix = dbKey.split('-').first;
          final Team? homeTeam = teamsViewModel.findTeam(
            '$leaguePrefix-${gameData['HomeTeam']}',
          );
          final Team? awayTeam = teamsViewModel.findTeam(
            '$leaguePrefix-${gameData['AwayTeam']}',
          );
          if (homeTeam == null || awayTeam == null) {
            return null;
          }

          final Game game = Game.fromJson(dbKey, gameData, homeTeam, awayTeam);
          final int? dauRoundNumber = _findRoundNumberSilently(game, dauComp);
          final List<String> roundKeys = <String>[
            if (dauRoundNumber != null) dauRoundNumber.toString(),
            game.fixtureRoundNumber.toString(),
            'null',
          ];
          return _HistoricalGameDescriptor(
            gameId: game.dbkey,
            game: game,
            league: game.league,
            year: game.startTimeUTC.year,
            displayRoundNumber: dauRoundNumber ?? game.fixtureRoundNumber,
            roundKeys: roundKeys,
            homeTeamName: game.homeTeam.name,
            awayTeamName: game.awayTeam.name,
            homeTeamLogoUri: _findTeamLogo(game.homeTeam.name, game.league),
            awayTeamLogoUri: _findTeamLogo(game.awayTeam.name, game.league),
          );
        })
        .nonNulls
        .toList();
  }

  int? _findRoundNumberSilently(Game game, DAUComp dauComp) {
    final DAURound? matchingRound = dauComp.daurounds.firstWhereOrNull(
      (DAURound round) =>
          _isDateInRound(game.startTimeUTC, round.getRoundStartDate(), round.getRoundEndDate()),
    );
    return matchingRound?.dAUroundNumber;
  }

  bool _isDateInRound(DateTime date, DateTime roundStart, DateTime roundEnd) {
    return (date.isAfter(roundStart) || date.isAtSameMomentAs(roundStart)) &&
        (date.isBefore(roundEnd) || date.isAtSameMomentAs(roundEnd));
  }

  String? _findTeamLogo(String teamName, League league) {
    return teamsViewModel.teams
        .firstWhereOrNull(
          (Team team) =>
              team.league == league &&
              team.name.toLowerCase() == teamName.toLowerCase(),
        )
        ?.logoURI;
  }
}

class _ResolvedRealtimeTip {
  final TipHistoryEntry entry;
  final TipHistoryLookup lookup;

  const _ResolvedRealtimeTip({
    required this.entry,
    required this.lookup,
  });
}

class _HistoricalGameDescriptor {
  final String gameId;
  final Game game;
  final League league;
  final int year;
  final int displayRoundNumber;
  final List<String> roundKeys;
  final String homeTeamName;
  final String awayTeamName;
  final String? homeTeamLogoUri;
  final String? awayTeamLogoUri;

  const _HistoricalGameDescriptor({
    required this.gameId,
    required this.game,
    required this.league,
    required this.year,
    required this.displayRoundNumber,
    required this.roundKeys,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.homeTeamLogoUri,
    required this.awayTeamLogoUri,
  });

  TipHistoryLookup toLookup(String tipperDbKey) {
    return TipHistoryLookup(
      tipperDbKey: tipperDbKey,
      gameId: gameId,
      league: league,
      year: year,
      roundNumber: displayRoundNumber,
      roundKeys: roundKeys,
      homeTeamName: homeTeamName,
      awayTeamName: awayTeamName,
      homeTeamLogoUri: homeTeamLogoUri,
      awayTeamLogoUri: awayTeamLogoUri,
    );
  }
}
