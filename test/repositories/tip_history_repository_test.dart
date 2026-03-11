import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip_history_entry.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/repositories/tip_history_repository.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockTeamsViewModel extends Mock implements TeamsViewModel {}

class FakeTipHistoryLogSource implements TipHistoryLogSource {
  final Map<String, List<TipHistoryEntry>> logsByGameId;

  FakeTipHistoryLogSource(this.logsByGameId);

  @override
  Future<List<TipHistoryEntry>> fetchTipLogs(TipHistoryLookup lookup) async {
    return List<TipHistoryEntry>.from(logsByGameId[lookup.gameId] ?? const []);
  }
}

void main() {
  group('FirestoreTipHistoryRepository', () {
    late MockDatabaseReference mockDatabase;
    late MockDatabaseReference mockGamesRef;
    late MockDatabaseReference mockTipsRef;
    late MockDataSnapshot mockGamesSnapshot;
    late MockDataSnapshot mockTipsSnapshot;
    late MockTeamsViewModel mockTeamsViewModel;
    late Tipper tipper;
    late DAUComp dauComp;
    late Team homeTeam;
    late Team awayTeam;

    setUp(() {
      mockDatabase = MockDatabaseReference();
      mockGamesRef = MockDatabaseReference();
      mockTipsRef = MockDatabaseReference();
      mockGamesSnapshot = MockDataSnapshot();
      mockTipsSnapshot = MockDataSnapshot();
      mockTeamsViewModel = MockTeamsViewModel();

      homeTeam = Team(
        dbkey: 'nrl-home',
        name: 'Home',
        league: League.nrl,
      );
      awayTeam = Team(
        dbkey: 'nrl-away',
        name: 'Away',
        league: League.nrl,
      );
      tipper = Tipper(
        dbkey: 'tipper-1',
        authuid: 'auth-1',
        email: 'tipper@example.com',
        name: 'Tipper',
        tipperRole: TipperRole.tipper,
        compsPaidFor: const <DAUComp>[],
      );
      dauComp = DAUComp(
        dbkey: 'comp-2025',
        name: '2025',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: <DAURound>[
          DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: DateTime.parse('2025-03-01T00:00:00Z'),
            lastGameKickOffUTC: DateTime.parse('2025-03-31T23:59:59Z'),
          ),
        ],
      );

      when(() => mockTeamsViewModel.initialLoadComplete)
          .thenAnswer((_) async {});
      when(() => mockTeamsViewModel.findTeam('nrl-home')).thenReturn(homeTeam);
      when(() => mockTeamsViewModel.findTeam('nrl-away')).thenReturn(awayTeam);
      when(() => mockTeamsViewModel.teams).thenReturn(<Team>[homeTeam, awayTeam]);

      when(
        () => mockDatabase.child('${p.gamesPathRoot}/${dauComp.dbkey}'),
      ).thenReturn(mockGamesRef);
      when(() => mockGamesRef.get()).thenAnswer((_) async => mockGamesSnapshot);
      when(() => mockGamesSnapshot.exists).thenReturn(true);
      when(() => mockGamesSnapshot.value).thenReturn(<String, dynamic>{
        'nrl-01-001': <String, dynamic>{
          'HomeTeam': 'home',
          'AwayTeam': 'away',
          'Location': 'Stadium',
          'DateUtc': '2025-03-10T10:00:00Z',
          'RoundNumber': 1,
          'MatchNumber': 1,
        },
      });

      when(
        () => mockDatabase.child('${p.tipsPathRoot}/${dauComp.dbkey}/${tipper.dbkey}'),
      ).thenReturn(mockTipsRef);
      when(() => mockTipsRef.get()).thenAnswer((_) async => mockTipsSnapshot);
      when(() => mockTipsSnapshot.exists).thenReturn(true);
      when(() => mockTipsSnapshot.value).thenReturn(<String, dynamic>{
        'nrl-01-001': <String, dynamic>{
          'r': GameResult.b.name,
          't': 1740823200,
        },
      });
    });

    test('loads tip history from realtime tips when no firestore history exists', () async {
      final repository = FirestoreTipHistoryRepository(
        dauComps: <DAUComp>[dauComp],
        teamsViewModel: mockTeamsViewModel,
        database: mockDatabase,
        logSource: FakeTipHistoryLogSource(const <String, List<TipHistoryEntry>>{}),
      );

      final history = await repository.fetchTipHistory(tipper);

      expect(history, hasLength(1));
      expect(history.single.gameId, 'nrl-01-001');
      expect(history.single.tip, GameResult.b);
      expect(history.single.year, 2025);
      expect(history.single.roundNumber, 1);
      expect(
        history.single.tipSubmittedUTC,
        DateTime.fromMillisecondsSinceEpoch(1740823200 * 1000, isUtc: true),
      );
    });

    test('fetchCurrentTipHistory returns final realtime tip only', () async {
      final repository = FirestoreTipHistoryRepository(
        dauComps: <DAUComp>[dauComp],
        teamsViewModel: mockTeamsViewModel,
        database: mockDatabase,
        logSource: FakeTipHistoryLogSource(<String, List<TipHistoryEntry>>{
          'nrl-01-001': <TipHistoryEntry>[
            TipHistoryEntry(
              gameId: 'nrl-01-001',
              league: League.nrl,
              year: 2025,
              roundNumber: 1,
              homeTeamName: 'Home',
              awayTeamName: 'Away',
              homeTeamLogoUri: null,
              awayTeamLogoUri: null,
              tip: GameResult.d,
              tipSubmittedUTC: DateTime.parse('2025-03-01T09:00:00Z'),
            ),
          ],
        }),
      );

      final history = await repository.fetchCurrentTipHistory(tipper);

      expect(history, hasLength(1));
      expect(history.single.tip, GameResult.b);
      expect(
        history.single.tipSubmittedUTC,
        DateTime.fromMillisecondsSinceEpoch(1740823200 * 1000, isUtc: true),
      );
    });

    test('uses firestore history when available for a tipped game', () async {
      final TipHistoryEntry earlierChange = TipHistoryEntry(
        gameId: 'nrl-01-001',
        league: League.nrl,
        year: 2025,
        roundNumber: 1,
        homeTeamName: 'Home',
        awayTeamName: 'Away',
        homeTeamLogoUri: null,
        awayTeamLogoUri: null,
        tip: GameResult.d,
        tipSubmittedUTC: DateTime.parse('2025-03-01T09:00:00Z'),
      );
      final TipHistoryEntry finalChange = TipHistoryEntry(
        gameId: 'nrl-01-001',
        league: League.nrl,
        year: 2025,
        roundNumber: 1,
        homeTeamName: 'Home',
        awayTeamName: 'Away',
        homeTeamLogoUri: null,
        awayTeamLogoUri: null,
        tip: GameResult.b,
        tipSubmittedUTC: DateTime.fromMillisecondsSinceEpoch(
          1740823200 * 1000,
          isUtc: true,
        ),
      );

      final repository = FirestoreTipHistoryRepository(
        dauComps: <DAUComp>[dauComp],
        teamsViewModel: mockTeamsViewModel,
        database: mockDatabase,
        logSource: FakeTipHistoryLogSource(<String, List<TipHistoryEntry>>{
          'nrl-01-001': <TipHistoryEntry>[earlierChange, finalChange],
        }),
      );

      final history = await repository.fetchTipHistory(tipper);

      expect(history, hasLength(2));
      expect(history.first.tipSubmittedUTC, finalChange.tipSubmittedUTC);
      expect(history.last.tipSubmittedUTC, earlierChange.tipSubmittedUTC);
      expect(history.first.tip, GameResult.b);
      expect(history.last.tip, GameResult.d);
    });
  });
}
