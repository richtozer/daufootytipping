import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_functions/firebase_functions.dart' hide DataSnapshot;
import 'package:firebase_dart/database.dart';
import 'package:firebase_dart/standalone_database.dart';
import 'package:dau_shared/dau_shared.dart';
import '../bin/server.dart';

class MockDatabase extends Mock {
  DatabaseReference ref([String? path]) => noSuchMethod(
        Invocation.method(#ref, [path]),
      ) as DatabaseReference;
}
class MockDatabaseReference extends Mock implements DatabaseReference {}
class MockQuery extends Mock implements Query {}
class MockDataSnapshot extends Mock implements DataSnapshot {}
class MockTransactionResult extends Mock implements TransactionResult {}

void main() {
  late MockDatabase mockDb;
  late MockDataSnapshot mockRoleSnapshot;

  setUp(() {
    mockDb = MockDatabase();
    mockRoleSnapshot = MockDataSnapshot();
  });

  group('configuration resolution', () {
    test('resolveDatabaseUrl uses RTDB emulator host with default namespace', () {
      expect(
        resolveDatabaseUrl(
          environment: {
            'FIREBASE_DATABASE_EMULATOR_HOST': '127.0.0.1:8000',
            'GCLOUD_PROJECT': 'dau-footy-tipping-f8a42',
          },
        ),
        'http://127.0.0.1:8000/?ns=dau-footy-tipping-f8a42-default-rtdb',
      );
    });

    test('resolveDatabaseUrl uses namespace override for RTDB emulator', () {
      expect(
        resolveDatabaseUrl(
          environment: {
            'FIREBASE_DATABASE_EMULATOR_HOST': '127.0.0.1:8000',
            'FIREBASE_DATABASE_EMULATOR_NAMESPACE': 'custom-ns',
          },
        ),
        'http://127.0.0.1:8000/?ns=custom-ns',
      );
    });

    test('resolveDatabaseUrl uses FIREBASE_CONFIG databaseURL', () {
      expect(
        resolveDatabaseUrl(
          environment: {
            'FIREBASE_CONFIG':
                '{"databaseURL":"https://example.firebaseio.com"}',
          },
        ),
        'https://example.firebaseio.com',
      );
    });

    test('resolveDatabaseUrl falls back to regional production database', () {
      expect(
        resolveDatabaseUrl(environment: {}),
        'https://dau-footy-tipping-f8a42-default-rtdb.asia-southeast1.firebasedatabase.app',
      );
    });

    test('resolveBackendScoringCommandSecret uses configured env keys', () {
      expect(
        resolveBackendScoringCommandSecret(environment: {
          'BACKEND_SCORING_COMMAND_SECRET': 'secret-123',
        }),
        'secret-123',
      );
      expect(
        resolveBackendScoringCommandSecret(environment: {
          'DART_BACKEND_SCORING_COMMAND_SECRET': 'secret-456',
        }),
        'secret-456',
      );
    });

    test('isBackendScoringCommandAuthorized matches the shared secret', () {
      expect(
        isBackendScoringCommandAuthorized(
          {
            'X-Backend-Scoring-Secret': 'secret-123',
          },
          expectedSecret: 'secret-123',
        ),
        isTrue,
      );
      expect(
        isBackendScoringCommandAuthorized(
          {
            'x-backend-scoring-secret': 'wrong',
          },
          expectedSecret: 'secret-123',
        ),
        isFalse,
      );
    });
  });

  group('executeFixtureDownload tests', () {
    test('non-admin role throws PermissionDeniedError', () async {
      final mockTippersRef = MockDatabaseReference();
      final mockQuery = MockDatabaseReference();

      when(() => mockDb.ref('/AllTippers')).thenReturn(mockTippersRef);
      when(() => mockTippersRef.orderByChild('authuid')).thenReturn(mockQuery);
      when(() => mockQuery.equalTo('user123')).thenReturn(mockQuery);
      when(() => mockQuery.once()).thenAnswer((_) async => mockRoleSnapshot);
      when(() => mockRoleSnapshot.value).thenReturn({
        'tipper123': {
          'authuid': 'user123',
          'tipperRole': 'user', // Not admin
        }
      });

      expect(
        executeFixtureDownload(
          authUid: 'user123',
          compKey: 'comp2026',
          db: mockDb,
          fetchFixtureJson: (_) async => [],
          now: DateTime.now().toUtc(),
        ),
        throwsA(isA<PermissionDeniedError>()),
      );
    });

    test('missing DAUComp config throws NotFoundError', () async {
      final mockTippersRef = MockDatabaseReference();
      final mockQuery = MockDatabaseReference();

      when(() => mockDb.ref('/AllTippers')).thenReturn(mockTippersRef);
      when(() => mockTippersRef.orderByChild('authuid')).thenReturn(mockQuery);
      when(() => mockQuery.equalTo('user123')).thenReturn(mockQuery);
      when(() => mockQuery.once()).thenAnswer((_) async => mockRoleSnapshot);
      when(() => mockRoleSnapshot.value).thenReturn({
        'tipper123': {
          'authuid': 'user123',
          'tipperRole': 'admin',
        }
      });

      final mockCompRef = MockDatabaseReference();
      final mockCompSnapshot = MockDataSnapshot();
      when(() => mockDb.ref('/AllDAUComps/comp2026')).thenReturn(mockCompRef);
      when(() => mockCompRef.once()).thenAnswer((_) async => mockCompSnapshot);
      when(() => mockCompSnapshot.value).thenReturn(null); // Missing comp

      expect(
        executeFixtureDownload(
          authUid: 'user123',
          compKey: 'comp2026',
          db: mockDb,
          fetchFixtureJson: (_) async => [],
          now: DateTime.now().toUtc(),
        ),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('active lock throws AbortedError', () async {
      final mockTippersRef = MockDatabaseReference();
      final mockQuery = MockDatabaseReference();

      when(() => mockDb.ref('/AllTippers')).thenReturn(mockTippersRef);
      when(() => mockTippersRef.orderByChild('authuid')).thenReturn(mockQuery);
      when(() => mockQuery.equalTo('user123')).thenReturn(mockQuery);
      when(() => mockQuery.once()).thenAnswer((_) async => mockRoleSnapshot);
      when(() => mockRoleSnapshot.value).thenReturn({
        'tipper123': {
          'authuid': 'user123',
          'tipperRole': 'admin',
        }
      });

      final mockCompRef = MockDatabaseReference();
      final mockCompSnapshot = MockDataSnapshot();
      when(() => mockDb.ref('/AllDAUComps/comp2026')).thenReturn(mockCompRef);
      when(() => mockCompRef.once()).thenAnswer((_) async => mockCompSnapshot);
      when(() => mockCompSnapshot.value).thenReturn({
        'name': 'Comp 2026',
        'aflFixtureJsonURL': 'https://afl.example.com',
        'nrlFixtureJsonURL': 'https://nrl.example.com',
      });

      final mockLockRef = MockDatabaseReference();
      when(() => mockDb.ref('/AllDAUComps/comp2026/downloadLock')).thenReturn(mockLockRef);
      
      final lockTime = DateTime.now().toUtc();
      final mockTransactionResult = MockTransactionResult();
      when(() => mockTransactionResult.committed).thenReturn(false);

      when(() => mockLockRef.runTransaction(any())).thenAnswer((invocation) async {
        final handler = invocation.positionalArguments[0] as TransactionHandler;
        final mutableData = MutableData('downloadLock', lockTime.toIso8601String());
        final result = await handler(mutableData);
        if (result == null) {
          return mockTransactionResult;
        }
        final successResult = MockTransactionResult();
        when(() => successResult.committed).thenReturn(true);
        return successResult;
      });

      expect(
        executeFixtureDownload(
          authUid: 'user123',
          compKey: 'comp2026',
          db: mockDb,
          fetchFixtureJson: (_) async => [],
          now: lockTime.add(const Duration(minutes: 5)),
        ),
        throwsA(isA<AbortedError>()),
      );
    });

    test('successful fixture update workflow', () async {
      final mockTippersRef = MockDatabaseReference();
      final mockQuery = MockDatabaseReference();

      when(() => mockDb.ref('/AllTippers')).thenReturn(mockTippersRef);
      when(() => mockTippersRef.orderByChild('authuid')).thenReturn(mockQuery);
      when(() => mockQuery.equalTo('user123')).thenReturn(mockQuery);
      when(() => mockQuery.once()).thenAnswer((_) async => mockRoleSnapshot);
      when(() => mockRoleSnapshot.value).thenReturn({
        'tipper123': {
          'authuid': 'user123',
          'tipperRole': 'admin',
        }
      });

      final mockCompRef = MockDatabaseReference();
      final mockCompSnapshot = MockDataSnapshot();
      when(() => mockDb.ref('/AllDAUComps/comp2026')).thenReturn(mockCompRef);
      when(() => mockCompRef.once()).thenAnswer((_) async => mockCompSnapshot);
      when(() => mockCompSnapshot.value).thenReturn({
        'name': 'Comp 2026',
        'aflFixtureJsonURL': 'https://afl.example.com',
        'nrlFixtureJsonURL': 'https://nrl.example.com',
      });

      final mockLockRef = MockDatabaseReference();
      when(() => mockDb.ref('/AllDAUComps/comp2026/downloadLock')).thenReturn(mockLockRef);
      final mockTransactionResult = MockTransactionResult();
      when(() => mockTransactionResult.committed).thenReturn(true);
      when(() => mockLockRef.runTransaction(any())).thenAnswer((invocation) async {
        final handler = invocation.positionalArguments[0] as TransactionHandler;
        final mutableData = MutableData('downloadLock', null);
        final result = await handler(mutableData);
        if (result == null) {
          final abortResult = MockTransactionResult();
          when(() => abortResult.committed).thenReturn(false);
          return abortResult;
        }
        return mockTransactionResult;
      });
      when(() => mockLockRef.set(any(), priority: any(named: 'priority'))).thenAnswer((_) async {});

      final mockStatusRef = MockDatabaseReference();
      when(() => mockDb.ref('/Stats/comp2026/scoring_status')).thenReturn(mockStatusRef);
      when(() => mockStatusRef.set(any(), priority: any(named: 'priority'))).thenAnswer((_) async {});

      final mockRootRef = MockDatabaseReference();
      when(() => mockDb.ref('/')).thenReturn(mockRootRef);
      when(() => mockRootRef.update(any())).thenAnswer((_) async {});

      // Stub teams lookup
      final mockTeamsRef = MockDatabaseReference();
      final mockTeamsSnapshot = MockDataSnapshot();
      when(() => mockDb.ref('/Teams')).thenReturn(mockTeamsRef);
      when(() => mockTeamsRef.once()).thenAnswer((_) async => mockTeamsSnapshot);
      when(() => mockTeamsSnapshot.value).thenReturn({
        'nrl-broncos': {
          'name': 'Broncos',
          'league': 'nrl',
        },
        'afl-collingwood': {
          'name': 'Collingwood',
          'league': 'afl',
        }
      });

      final mockAflGames = [
        {
          'RoundNumber': 1,
          'MatchNumber': 1,
          'HomeTeam': 'Collingwood',
          'AwayTeam': 'Richmond',
          'HomeTeamScore': 80,
          'AwayTeamScore': 70,
          'KickOffTime': '2026-06-01T19:00:00Z',
          'DateUtc': '2026-06-01T19:00:00Z',
        }
      ];
      final mockNrlGames = [
        {
          'RoundNumber': 1,
          'MatchNumber': 1,
          'HomeTeam': 'Broncos',
          'AwayTeam': 'Roosters',
          'HomeTeamScore': 24,
          'AwayTeamScore': 18,
          'KickOffTime': '2026-06-02T19:00:00Z',
          'DateUtc': '2026-06-02T19:00:00Z',
        }
      ];

      final resultMsg = await executeFixtureDownload(
        authUid: 'user123',
        compKey: 'comp2026',
        db: mockDb,
        fetchFixtureJson: (url) async {
          if (url.toString().contains('afl')) return mockAflGames;
          return mockNrlGames;
        },
        now: DateTime.parse('2026-05-25T12:00:00Z'),
      );

      expect(resultMsg, contains('Found 1 NRL games and 1 AFL games'));

      // Verify that lock was acquired and then released
      verify(() => mockLockRef.runTransaction(any())).called(1);
      verify(() => mockLockRef.set(null, priority: any(named: 'priority'))).called(1);

      // Verify status transitions
      verify(() => mockStatusRef.set(any(that: isA<Map>()), priority: any(named: 'priority'))).called(3);

      // Verify updates were written to root database reference
      final capturedUpdates = verify(() => mockRootRef.update(captureAny())).captured.single as Map<String, dynamic>;
      expect(capturedUpdates, contains('/AllDAUComps/comp2026/lastFixtureUTC'));
      expect(capturedUpdates, contains('/DAUCompsGames/comp2026/nrl-01-001/HomeTeamScore'));
      expect(capturedUpdates, contains('/DAUCompsGames/comp2026/afl-01-001/HomeTeamScore'));
    });

    test('normalizes team keys when fixture team names contain whitespace', () async {
      final mockRoleQuery = MockQuery();
      final mockRoleSnapshot = MockDataSnapshot();
      final mockTippersRef = MockDatabaseReference();
      when(() => mockDb.ref('/AllTippers')).thenReturn(mockTippersRef);
      when(() => mockTippersRef.orderByChild('authuid')).thenReturn(mockRoleQuery);
      when(() => mockRoleQuery.equalTo('user123')).thenReturn(mockRoleQuery);
      when(() => mockRoleQuery.once()).thenAnswer((_) async => mockRoleSnapshot);
      when(() => mockRoleSnapshot.value).thenReturn({
        'adminTipper': {'tipperRole': 'admin'}
      });

      final mockCompRef = MockDatabaseReference();
      final mockCompSnapshot = MockDataSnapshot();
      when(() => mockDb.ref('/AllDAUComps/comp2026')).thenReturn(mockCompRef);
      when(() => mockCompRef.once()).thenAnswer((_) async => mockCompSnapshot);
      when(() => mockCompSnapshot.value).thenReturn({
        'name': 'Comp 2026',
        'aflFixtureJsonURL': 'https://afl.example.com',
        'nrlFixtureJsonURL': 'https://nrl.example.com',
      });

      final mockLockRef = MockDatabaseReference();
      when(() => mockDb.ref('/AllDAUComps/comp2026/downloadLock')).thenReturn(mockLockRef);
      final mockTransactionResult = MockTransactionResult();
      when(() => mockTransactionResult.committed).thenReturn(true);
      when(() => mockLockRef.runTransaction(any())).thenAnswer((invocation) async {
        final handler = invocation.positionalArguments[0] as TransactionHandler;
        final mutableData = MutableData('downloadLock', null);
        final result = await handler(mutableData);
        if (result == null) {
          final abortResult = MockTransactionResult();
          when(() => abortResult.committed).thenReturn(false);
          return abortResult;
        }
        return mockTransactionResult;
      });
      when(() => mockLockRef.set(any(), priority: any(named: 'priority'))).thenAnswer((_) async {});

      final mockStatusRef = MockDatabaseReference();
      when(() => mockDb.ref('/Stats/comp2026/scoring_status')).thenReturn(mockStatusRef);
      when(() => mockStatusRef.set(any(), priority: any(named: 'priority'))).thenAnswer((_) async {});

      final mockRootRef = MockDatabaseReference();
      when(() => mockDb.ref('/')).thenReturn(mockRootRef);
      when(() => mockRootRef.update(any())).thenAnswer((_) async {});

      final mockTeamsRef = MockDatabaseReference();
      final mockTeamsSnapshot = MockDataSnapshot();
      when(() => mockDb.ref('/Teams')).thenReturn(mockTeamsRef);
      when(() => mockTeamsRef.once()).thenAnswer((_) async => mockTeamsSnapshot);
      when(() => mockTeamsSnapshot.value).thenReturn({});

      final mockNrlGames = [
        {
          'RoundNumber': 1,
          'MatchNumber': 1,
          'HomeTeam': ' Broncos ',
          'AwayTeam': ' Roosters ',
          'HomeTeamScore': 24,
          'AwayTeamScore': 18,
          'KickOffTime': '2026-06-02T19:00:00Z',
          'DateUtc': '2026-06-02T19:00:00Z',
        }
      ];

      await executeFixtureDownload(
        authUid: 'user123',
        compKey: 'comp2026',
        db: mockDb,
        fetchFixtureJson: (url) async {
          if (url.toString().contains('afl')) return [];
          return mockNrlGames;
        },
        now: DateTime.parse('2026-05-25T12:00:00Z'),
      );

      final capturedUpdates = verify(
        () => mockRootRef.update(captureAny()),
      ).captured.single as Map<String, dynamic>;
      expect(capturedUpdates, contains('/Teams/nrl-broncos'));
      expect(capturedUpdates, contains('/Teams/nrl-roosters'));
      expect(capturedUpdates, isNot(contains('/Teams/nrl- broncos ')));
      expect(
        Map<String, dynamic>.from(capturedUpdates['/Teams/nrl-broncos'] as Map),
        containsPair('name', 'Broncos'),
      );
    });
  });

  group('backend scoring command tests', () {
    test('parses a tipWritten command payload', () {
      final command = BackendScoringCommand.fromJson({
        'commandType': 'tipWritten',
        'compKey': 'comp2026',
        'tipperId': 'tipper-1',
        'gameKey': 'nrl-01-001',
        'sourceEventId': 'event-123',
        'sourcePath': '/AllTips/comp2026/tipper-1/nrl-01-001',
        'scopeKey': 'comp:comp2026/game:nrl-01-001/tipper:tipper-1',
        'commandId': 'event-123',
      });

      expect(command.commandType, BackendScoringCommandType.tipWritten);
      expect(command.compKey, 'comp2026');
      expect(command.roundNumber, isNull);
      expect(command.tipperId, 'tipper-1');
      expect(command.gameKey, 'nrl-01-001');
    });

    test('rejects incomplete tipWritten command payloads', () {
      expect(
        () => BackendScoringCommand.fromJson({
          'commandType': 'tipWritten',
          'compKey': 'comp2026',
          'tipperId': 'tipper-1',
          'sourceEventId': 'event-123',
          'sourcePath': '/AllTips/comp2026/tipper-1/nrl-01-001',
          'scopeKey': 'comp:comp2026/game:nrl-01-001/tipper:tipper-1',
          'commandId': 'event-123',
        }),
        throwsArgumentError,
      );
    });

    test('parses an adminRescore command payload', () {
      final command = BackendScoringCommand.fromJson({
        'commandType': 'adminRescore',
        'compKey': 'comp2026',
        'roundNumber': 13,
        'sourceEventId': 'admin-13',
        'sourcePath': '/admin/backendScoring/adminRescore',
        'scopeKey': 'comp:comp2026/round:13/all_tippers',
        'commandId': 'admin-13',
      });

      expect(command.commandType, BackendScoringCommandType.adminRescore);
      expect(command.compKey, 'comp2026');
      expect(command.roundNumber, 13);
      expect(command.tipperId, isNull);
      expect(command.gameKey, isNull);
    });

    test('rejects adminRescore command payloads without a round', () {
      expect(
        () => BackendScoringCommand.fromJson({
          'commandType': 'adminRescore',
          'compKey': 'comp2026',
          'sourceEventId': 'admin-13',
          'sourcePath': '/admin/backendScoring/adminRescore',
          'scopeKey': 'comp:comp2026/round:13/all_tippers',
          'commandId': 'admin-13',
        }),
        throwsArgumentError,
      );
    });

    test('skips replayed completed commands without recalculating', () async {
      final mockDb = MockDatabase();
      final mockIdempotencyRef = MockDatabaseReference();
      final mockSnapshot = MockDataSnapshot();
      final mockTransactionResult = MockTransactionResult();
      final command = BackendScoringCommand(
        commandType: BackendScoringCommandType.tipWritten,
        compKey: 'comp2026',
        roundNumber: null,
        tipperId: 'tipper-1',
        gameKey: 'nrl-01-001',
        sourceEventId: 'event-123',
        sourcePath: '/AllTips/comp2026/tipper-1/nrl-01-001',
        scopeKey: 'comp:comp2026/game:nrl-01-001/tipper:tipper-1',
        commandId: 'event-123',
      );

      when(() => mockDb.ref('/Stats/comp2026/scoring_idempotency_backend_v1/event-123'))
          .thenReturn(mockIdempotencyRef);
      when(() => mockTransactionResult.committed).thenReturn(false);
      when(() => mockIdempotencyRef.runTransaction(any())).thenAnswer((invocation) async {
        final handler = invocation.positionalArguments[0] as TransactionHandler;
        final mutableData = MutableData(
          'event-123',
          BackendScoringIdempotencyRecord(
            status: BackendScoringIdempotencyStatus.completed,
            commandId: 'event-123',
            commandType: 'tipWritten',
            compKey: 'comp2026',
            sourceEventId: 'event-123',
            sourcePath: '/AllTips/comp2026/tipper-1/nrl-01-001',
            scopeKey: 'round:1/tipper:tipper-1',
            startedAt: '2026-06-03T12:00:00Z',
            completedAt: '2026-06-03T12:00:01Z',
            expiresAt: '2026-06-04T12:00:00Z',
          ).toJson(),
        );
        final result = await handler(mutableData);
        if (result == null) {
          return mockTransactionResult;
        }
        final committedResult = MockTransactionResult();
        when(() => committedResult.committed).thenReturn(true);
        return committedResult;
      });
      when(() => mockIdempotencyRef.once()).thenAnswer((_) async => mockSnapshot);
      when(() => mockSnapshot.value).thenReturn({
        'status': 'completed',
        'commandId': 'event-123',
        'commandType': 'tipWritten',
        'compKey': 'comp2026',
        'sourceEventId': 'event-123',
        'sourcePath': '/AllTips/comp2026/tipper-1/nrl-01-001',
        'scopeKey': 'comp:comp2026/game:nrl-01-001/tipper:tipper-1',
        'startedAt': '2026-06-03T12:00:00Z',
        'completedAt': '2026-06-03T12:00:01Z',
        'expiresAt': '2026-06-04T12:00:00Z',
      });

      final result = await executeBackendScoringCommand(
        db: mockDb,
        command: command,
        now: DateTime.parse('2026-06-03T12:30:00Z'),
      );

      expect(result.skipped, isTrue);
      expect(result.status, 'completed');
      verifyNever(() => mockIdempotencyRef.set(any()));
      verify(() => mockIdempotencyRef.runTransaction(any())).called(1);
    });

    test('skips in-progress commands after a transaction retry', () async {
      final mockDb = MockDatabase();
      final mockIdempotencyRef = MockDatabaseReference();
      final mockSnapshot = MockDataSnapshot();
      final mockTransactionResult = MockTransactionResult();
      final command = BackendScoringCommand(
        commandType: BackendScoringCommandType.tipWritten,
        compKey: 'comp2026',
        roundNumber: null,
        tipperId: 'tipper-1',
        gameKey: 'nrl-01-001',
        sourceEventId: 'event-124',
        sourcePath: '/AllTips/comp2026/tipper-1/nrl-01-001',
        scopeKey: 'comp:comp2026/game:nrl-01-001/tipper:tipper-1',
        commandId: 'event-124',
      );

      when(() => mockDb.ref('/Stats/comp2026/scoring_idempotency_backend_v1/event-124'))
          .thenReturn(mockIdempotencyRef);
      when(() => mockTransactionResult.committed).thenReturn(false);
      when(() => mockIdempotencyRef.runTransaction(any())).thenAnswer((invocation) async {
        final handler = invocation.positionalArguments[0] as TransactionHandler;
        final mutableData = MutableData(
          'event-124',
          null,
        );
        final result = await handler(mutableData);
        if (result == null) {
          return mockTransactionResult;
        }
        final retryMutableData = MutableData(
          'event-124',
          BackendScoringIdempotencyRecord(
            status: BackendScoringIdempotencyStatus.started,
            commandId: 'event-124',
            commandType: 'tipWritten',
            compKey: 'comp2026',
            sourceEventId: 'event-124',
            sourcePath: '/AllTips/comp2026/tipper-1/nrl-01-001',
            scopeKey: 'comp:comp2026/game:nrl-01-001/tipper:tipper-1',
            startedAt: '2026-06-03T12:00:00Z',
            expiresAt: '2026-06-04T12:00:00Z',
          ).toJson(),
        );
        await handler(retryMutableData);
        return mockTransactionResult;
      });
      when(() => mockIdempotencyRef.once()).thenAnswer((_) async => mockSnapshot);
      when(() => mockSnapshot.value).thenReturn({
        'status': 'started',
        'commandId': 'event-124',
        'commandType': 'tipWritten',
        'compKey': 'comp2026',
        'sourceEventId': 'event-124',
        'sourcePath': '/AllTips/comp2026/tipper-1/nrl-01-001',
        'scopeKey': 'comp:comp2026/game:nrl-01-001/tipper:tipper-1',
        'startedAt': '2026-06-03T12:00:00Z',
        'expiresAt': '2026-06-04T12:00:00Z',
      });

      final result = await executeBackendScoringCommand(
        db: mockDb,
        command: command,
        now: DateTime.parse('2026-06-03T12:30:00Z'),
      );

      expect(result.skipped, isTrue);
      expect(result.status, 'started');
      verify(() => mockIdempotencyRef.runTransaction(any())).called(1);
      verify(() => mockIdempotencyRef.once()).called(1);
      verifyNever(() => mockDb.ref('/Stats/comp2026/round_stats_backend_v1/1/tipper-1'));
    });

    test('writes only the target round and tipper for tipWritten commands', () async {
      final mockDb = MockDatabase();
      final mockCompRef = MockDatabaseReference();
      final mockCompSnapshot = MockDataSnapshot();
      final mockTeamsRef = MockDatabaseReference();
      final mockTeamsSnapshot = MockDataSnapshot();
      final mockGamesRef = MockDatabaseReference();
      final mockGamesSnapshot = MockDataSnapshot();
      final mockTipsRef = MockDatabaseReference();
      final mockTipsSnapshot = MockDataSnapshot();
      final mockLiveScoresRef = MockDatabaseReference();
      final mockLiveScoresSnapshot = MockDataSnapshot();
      final mockTipperRef = MockDatabaseReference();
      final mockTipperSnapshot = MockDataSnapshot();
      final mockIdempotencyRef = MockDatabaseReference();
      final mockRoundStatsRef = MockDatabaseReference();
      final mockOtherRoundStatsRef = MockDatabaseReference();
      final mockStatusRef = MockDatabaseReference();
      final mockTransactionResult = MockTransactionResult();
      Map<String, dynamic>? capturedStartedIdempotencyRecord;

      final command = BackendScoringCommand(
        commandType: BackendScoringCommandType.tipWritten,
        compKey: 'comp2026',
        roundNumber: null,
        tipperId: 'tipper-1',
        gameKey: 'nrl-01-001',
        sourceEventId: 'event-456',
        sourcePath: '/AllTips/comp2026/tipper-1/nrl-01-001',
        scopeKey: 'comp:comp2026/game:nrl-01-001/tipper:tipper-1',
        commandId: 'event-456',
      );

      when(() => mockDb.ref('/AllDAUComps/comp2026')).thenReturn(mockCompRef);
      when(() => mockCompRef.once()).thenAnswer((_) async => mockCompSnapshot);
      when(() => mockCompSnapshot.value).thenReturn({
        'name': 'Comp 2026',
        'aflFixtureJsonURL': 'https://example.com/afl.json',
        'nrlFixtureJsonURL': 'https://example.com/nrl.json',
        'combinedRounds2': [
          {
            'roundStartDate': '2026-01-01T00:00:00Z',
            'roundEndDate': '2026-01-07T23:59:59Z',
          },
          {
            'roundStartDate': '2026-01-08T00:00:00Z',
            'roundEndDate': '2026-01-14T23:59:59Z',
          },
        ],
      });

      when(() => mockDb.ref('/AllTippers/tipper-1')).thenReturn(mockTipperRef);
      when(() => mockTipperRef.once()).thenAnswer((_) async => mockTipperSnapshot);
      when(() => mockTipperSnapshot.value).thenReturn({
        'authuid': 'auth-1',
        'email': 'alice@example.com',
        'name': 'Alice',
        'tipperRole': 'tipper',
        'isAnonymous': false,
      });

      when(() => mockDb.ref('/Teams')).thenReturn(mockTeamsRef);
      when(() => mockTeamsRef.once()).thenAnswer((_) async => mockTeamsSnapshot);
      when(() => mockTeamsSnapshot.value).thenReturn({
        'nrl-broncos': {'name': 'Broncos', 'league': 'nrl'},
        'nrl-roosters': {'name': 'Roosters', 'league': 'nrl'},
      });

      when(() => mockDb.ref('/DAUCompsGames/comp2026')).thenReturn(mockGamesRef);
      when(() => mockGamesRef.once()).thenAnswer((_) async => mockGamesSnapshot);
      when(() => mockGamesSnapshot.value).thenReturn({
        'nrl-01-001': {
          'RoundNumber': 1,
          'MatchNumber': 1,
          'HomeTeam': 'Broncos',
          'AwayTeam': 'Roosters',
          'Location': 'Stadium One',
          'DateUtc': '2026-01-03T10:00:00Z',
          'HomeTeamScore': 30,
          'AwayTeamScore': 10,
        },
        'nrl-02-001': {
          'RoundNumber': 2,
          'MatchNumber': 1,
          'HomeTeam': 'Broncos',
          'AwayTeam': 'Roosters',
          'Location': 'Stadium Two',
          'DateUtc': '2026-01-10T10:00:00Z',
          'HomeTeamScore': 20,
          'AwayTeamScore': 16,
        },
      });

      when(() => mockDb.ref('/Stats/comp2026/live_scores_v3'))
          .thenReturn(mockLiveScoresRef);
      when(() => mockLiveScoresRef.once()).thenAnswer((_) async => mockLiveScoresSnapshot);
      when(() => mockLiveScoresSnapshot.value).thenReturn(null);

      when(() => mockDb.ref('/AllTips/comp2026/tipper-1'))
          .thenReturn(mockTipsRef);
      when(() => mockTipsRef.once()).thenAnswer((_) async => mockTipsSnapshot);
      when(() => mockTipsSnapshot.value).thenReturn({
        'nrl-01-001': {'r': 'a', 't': 1760000000},
        'nrl-02-001': {'r': 'd', 't': 1760000000},
      });

      when(() => mockDb.ref('/Stats/comp2026/scoring_idempotency_backend_v1/event-456'))
          .thenReturn(mockIdempotencyRef);
      when(() => mockTransactionResult.committed).thenReturn(true);
      when(() => mockIdempotencyRef.runTransaction(any())).thenAnswer((invocation) async {
        final handler = invocation.positionalArguments[0] as TransactionHandler;
        final mutableData = MutableData('event-456', null);
        final result = await handler(mutableData);
        if (result == null) {
          final abortedResult = MockTransactionResult();
          when(() => abortedResult.committed).thenReturn(false);
          return abortedResult;
        }
        capturedStartedIdempotencyRecord =
            Map<String, dynamic>.from(mutableData.value as Map);
        return mockTransactionResult;
      });
      when(() => mockIdempotencyRef.set(any())).thenAnswer((_) async {});

      when(() => mockDb.ref('/Stats/comp2026/round_stats_backend_v1/1/tipper-1'))
          .thenReturn(mockRoundStatsRef);
      when(() => mockRoundStatsRef.set(any())).thenAnswer((_) async {});
      when(() => mockDb.ref('/Stats/comp2026/round_stats_backend_v1/2/tipper-1'))
          .thenReturn(mockOtherRoundStatsRef);
      when(() => mockOtherRoundStatsRef.set(any())).thenAnswer((_) async {});

      when(() => mockDb.ref('/Stats/comp2026/scoring_status')).thenReturn(mockStatusRef);
      when(() => mockStatusRef.set(any())).thenAnswer((_) async {});

      final result = await executeBackendScoringCommand(
        db: mockDb,
        command: command,
        now: DateTime.parse('2026-01-03T12:00:00Z'),
      );

      expect(result.skipped, isFalse);
      expect(result.status, 'completed');
      verify(() => mockIdempotencyRef.runTransaction(any())).called(1);

      final captured = verify(() => mockRoundStatsRef.set(captureAny())).captured.single;
      expect(captured, isA<Map>());
      expect(captured, containsPair('nS', 4));
      expect(captured, containsPair('nMs', 4));
      expect(captured, containsPair('aTo', 0));
      expect(captured, containsPair('nTo', 0));
      expect(capturedStartedIdempotencyRecord, isNotNull);
      expect(capturedStartedIdempotencyRecord!['status'], 'started');
      expect(
        DateTime.parse(capturedStartedIdempotencyRecord!['expiresAt'] as String).toUtc(),
        DateTime.parse('2026-01-04T12:00:00Z'),
      );

      verifyNever(() => mockOtherRoundStatsRef.set(any()));
      verify(() => mockIdempotencyRef.set(any())).called(1);
      verify(() => mockStatusRef.set(any())).called(1);
    });

    test(
      'official score commands batch round stats and split paid and free cohorts',
      () async {
        final mockDb = MockDatabase();
        final mockCompRef = MockDatabaseReference();
        final mockCompSnapshot = MockDataSnapshot();
        final mockTeamsRef = MockDatabaseReference();
        final mockTeamsSnapshot = MockDataSnapshot();
        final mockGamesRef = MockDatabaseReference();
        final mockGamesSnapshot = MockDataSnapshot();
        final mockLiveScoresRef = MockDatabaseReference();
        final mockLiveScoresSnapshot = MockDataSnapshot();
        final mockAllTippersRef = MockDatabaseReference();
        final mockAllTippersSnapshot = MockDataSnapshot();
        final mockAllTipsRef = MockDatabaseReference();
        final mockAllTipsSnapshot = MockDataSnapshot();
        final mockPaidTipperTipsRef = MockDatabaseReference();
        final mockFreeTipperTipsRef = MockDatabaseReference();
        final mockIdempotencyRef = MockDatabaseReference();
        final mockRoundStatsRootRef = MockDatabaseReference();
        final mockPaidRoundStatsRef = MockDatabaseReference();
        final mockFreeRoundStatsRef = MockDatabaseReference();
        final mockGameStatsRootRef = MockDatabaseReference();
        final mockStatusRef = MockDatabaseReference();
        final mockTransactionResult = MockTransactionResult();
        Map<String, dynamic>? capturedStartedIdempotencyRecord;

        final command = BackendScoringCommand(
          commandType: BackendScoringCommandType.officialScoreWritten,
          compKey: 'comp2026',
          roundNumber: null,
          tipperId: null,
          gameKey: 'nrl-01-001',
          sourceEventId: 'event-789',
          sourcePath: '/DAUCompsGames/comp2026/nrl-01-001',
          scopeKey: 'comp:comp2026/game:nrl-01-001',
          commandId: 'event-789',
        );

        when(() => mockDb.ref('/AllDAUComps/comp2026'))
            .thenReturn(mockCompRef);
        when(() => mockCompRef.once()).thenAnswer((_) async => mockCompSnapshot);
        when(() => mockCompSnapshot.value).thenReturn({
          'name': 'Comp 2026',
          'aflFixtureJsonURL': 'https://example.com/afl.json',
          'nrlFixtureJsonURL': 'https://example.com/nrl.json',
          'combinedRounds2': [
            {
              'roundStartDate': '2026-01-01T00:00:00Z',
              'roundEndDate': '2026-01-07T23:59:59Z',
            },
          ],
        });

        when(() => mockDb.ref('/Teams')).thenReturn(mockTeamsRef);
        when(() => mockTeamsRef.once()).thenAnswer((_) async => mockTeamsSnapshot);
        when(() => mockTeamsSnapshot.value).thenReturn({
          'nrl-broncos': {'name': 'Broncos', 'league': 'nrl'},
          'nrl-roosters': {'name': 'Roosters', 'league': 'nrl'},
        });

        when(() => mockDb.ref('/DAUCompsGames/comp2026'))
            .thenReturn(mockGamesRef);
        when(() => mockGamesRef.once()).thenAnswer((_) async => mockGamesSnapshot);
        when(() => mockGamesSnapshot.value).thenReturn({
          'nrl-01-001': {
            'RoundNumber': 1,
            'MatchNumber': 1,
            'HomeTeam': 'Broncos',
            'AwayTeam': 'Roosters',
            'Location': 'Stadium One',
            'DateUtc': '2026-01-03T10:00:00Z',
            'HomeTeamScore': 10,
            'AwayTeamScore': 30,
          },
        });

        when(() => mockDb.ref('/Stats/comp2026/live_scores_v3'))
            .thenReturn(mockLiveScoresRef);
        when(() => mockLiveScoresRef.once())
            .thenAnswer((_) async => mockLiveScoresSnapshot);
        when(() => mockLiveScoresSnapshot.value).thenReturn(null);

        when(() => mockDb.ref('/AllTippers')).thenReturn(mockAllTippersRef);
        when(() => mockAllTippersRef.once())
            .thenAnswer((_) async => mockAllTippersSnapshot);
        when(() => mockAllTippersSnapshot.value).thenReturn({
          'paid-tipper': {
            'authuid': 'auth-paid',
            'email': 'paid@example.com',
            'name': 'Paid',
            'tipperRole': 'tipper',
            'compsParticipatedIn': {1: 'comp2026'},
            'isAnonymous': false,
          },
          'free-tipper': {
            'authuid': 'auth-free',
            'email': 'free@example.com',
            'name': 'Free',
            'tipperRole': 'tipper',
            'isAnonymous': false,
          },
        });

        when(() => mockDb.ref('/AllTips/comp2026')).thenReturn(mockAllTipsRef);
        when(() => mockAllTipsRef.once())
            .thenAnswer((_) async => mockAllTipsSnapshot);
        when(() => mockAllTipsSnapshot.value).thenReturn({
          'paid-tipper': {
            // No submitted tip for this started game; backend should synthesize
            // the legacy default away tip.
          },
          'free-tipper': {
            'nrl-01-001': {'r': 'b', 't': 1760000001},
          },
        });
        when(() => mockDb.ref('/AllTips/comp2026/paid-tipper'))
            .thenReturn(mockPaidTipperTipsRef);
        when(() => mockPaidTipperTipsRef.once())
            .thenAnswer((_) async => mockAllTipsSnapshot);
        when(() => mockDb.ref('/AllTips/comp2026/free-tipper'))
            .thenReturn(mockFreeTipperTipsRef);
        when(() => mockFreeTipperTipsRef.once())
            .thenAnswer((_) async => mockAllTipsSnapshot);

        when(() => mockDb.ref(
              '/Stats/comp2026/scoring_idempotency_backend_v1/event-789',
            )).thenReturn(mockIdempotencyRef);
        when(() => mockTransactionResult.committed).thenReturn(true);
        when(() => mockIdempotencyRef.runTransaction(any())).thenAnswer((
          invocation,
        ) async {
          final handler = invocation.positionalArguments[0] as TransactionHandler;
          final mutableData = MutableData('event-789', null);
          final result = await handler(mutableData);
          if (result == null) {
            final abortedResult = MockTransactionResult();
            when(() => abortedResult.committed).thenReturn(false);
            return abortedResult;
          }
          capturedStartedIdempotencyRecord =
              Map<String, dynamic>.from(mutableData.value as Map);
          return mockTransactionResult;
        });
        when(() => mockIdempotencyRef.set(any())).thenAnswer((_) async {});

        when(() => mockDb.ref('/Stats/comp2026/round_stats_backend_v1/1'))
            .thenReturn(mockRoundStatsRootRef);
        when(() => mockRoundStatsRootRef.update(any()))
            .thenAnswer((_) async {});
        when(() => mockDb.ref('/Stats/comp2026/round_stats_backend_v1/1/paid-tipper'))
            .thenReturn(mockPaidRoundStatsRef);
        when(() => mockPaidRoundStatsRef.set(any())).thenAnswer((_) async {});
        when(() => mockDb.ref('/Stats/comp2026/round_stats_backend_v1/1/free-tipper'))
            .thenReturn(mockFreeRoundStatsRef);
        when(() => mockFreeRoundStatsRef.set(any())).thenAnswer((_) async {});

        when(() => mockDb.ref('/Stats/comp2026/game_stats_backend_v1'))
            .thenReturn(mockGameStatsRootRef);
        when(() => mockGameStatsRootRef.update(any()))
            .thenAnswer((_) async {});

        when(() => mockDb.ref('/Stats/comp2026/scoring_status'))
            .thenReturn(mockStatusRef);
        when(() => mockStatusRef.set(any())).thenAnswer((_) async {});

        final result = await executeBackendScoringCommand(
          db: mockDb,
          command: command,
          now: DateTime.parse('2026-01-03T12:00:00Z'),
        );

        expect(result.skipped, isFalse);
        expect(result.status, 'completed');
        verify(() => mockDb.ref('/AllTips/comp2026')).called(1);
        verifyNever(() => mockDb.ref('/AllTips/comp2026/paid-tipper'));
        verifyNever(() => mockDb.ref('/AllTips/comp2026/free-tipper'));

        final roundUpdates = verify(
          () => mockRoundStatsRootRef.update(captureAny()),
        ).captured.single as Map<String, dynamic>;
        expect(roundUpdates, containsPair('paid-tipper', isA<Map>()));
        expect(roundUpdates, containsPair('free-tipper', isA<Map>()));
        verifyNever(() => mockPaidRoundStatsRef.set(any()));
        verifyNever(() => mockFreeRoundStatsRef.set(any()));

        final gameUpdates = verify(
          () => mockGameStatsRootRef.update(captureAny()),
        ).captured.single as Map<String, dynamic>;
        final paidGameStats = Map<String, dynamic>.from(
          gameUpdates['paid/nrl-01-001'] as Map,
        );
        final freeGameStats = Map<String, dynamic>.from(
          gameUpdates['free/nrl-01-001'] as Map,
        );
        expect(paidGameStats['avgScoreTipCount'], 1);
        expect(paidGameStats['pctTipD'], 1.0);
        expect(paidGameStats['pctTipB'], 0.0);
        expect(roundUpdates['paid-tipper'], isA<Map>());
        expect(
          Map<String, dynamic>.from(roundUpdates['paid-tipper'] as Map)['nS'],
          2,
        );
        expect(freeGameStats['avgScoreTipCount'], 1);
        expect(freeGameStats['pctTipB'], 1.0);
        expect(freeGameStats['pctTipD'], 0.0);
        expect(roundUpdates['free-tipper'], isA<Map>());
        expect(
          Map<String, dynamic>.from(roundUpdates['free-tipper'] as Map)['nS'],
          0,
        );
        expect(capturedStartedIdempotencyRecord, isNotNull);
        expect(capturedStartedIdempotencyRecord!['status'], 'started');
        verify(() => mockIdempotencyRef.set(any())).called(1);
        verify(() => mockStatusRef.set(any())).called(1);
      },
    );

    test(
      'admin rescore rebuilds the requested backend round for all tippers',
      () async {
        final mockDb = MockDatabase();
        final mockCompRef = MockDatabaseReference();
        final mockCompSnapshot = MockDataSnapshot();
        final mockTeamsRef = MockDatabaseReference();
        final mockTeamsSnapshot = MockDataSnapshot();
        final mockGamesRef = MockDatabaseReference();
        final mockGamesSnapshot = MockDataSnapshot();
        final mockLiveScoresRef = MockDatabaseReference();
        final mockLiveScoresSnapshot = MockDataSnapshot();
        final mockAllTippersRef = MockDatabaseReference();
        final mockAllTippersSnapshot = MockDataSnapshot();
        final mockAllTipsRef = MockDatabaseReference();
        final mockAllTipsSnapshot = MockDataSnapshot();
        final mockIdempotencyRef = MockDatabaseReference();
        final mockRoundStatsRootRef = MockDatabaseReference();
        final mockGameStatsRootRef = MockDatabaseReference();
        final mockStatusRef = MockDatabaseReference();
        final mockTransactionResult = MockTransactionResult();

        final command = BackendScoringCommand(
          commandType: BackendScoringCommandType.adminRescore,
          compKey: 'comp2026',
          roundNumber: 1,
          tipperId: null,
          gameKey: null,
          sourceEventId: 'admin-rescore-1',
          sourcePath: '/admin/backendScoring/adminRescore',
          scopeKey: 'comp:comp2026/round:1/all_tippers',
          commandId: 'admin-rescore-1',
        );

        when(() => mockDb.ref('/Stats/comp2026/scoring_idempotency_backend_v1/admin-rescore-1'))
            .thenReturn(mockIdempotencyRef);
        when(() => mockTransactionResult.committed).thenReturn(true);
        when(() => mockIdempotencyRef.runTransaction(any())).thenAnswer((
          invocation,
        ) async {
          final handler = invocation.positionalArguments[0] as TransactionHandler;
          final mutableData = MutableData('admin-rescore-1', null);
          final result = await handler(mutableData);
          if (result == null) {
            final abortedResult = MockTransactionResult();
            when(() => abortedResult.committed).thenReturn(false);
            return abortedResult;
          }
          return mockTransactionResult;
        });
        when(() => mockIdempotencyRef.set(any())).thenAnswer((_) async {});

        when(() => mockDb.ref('/AllDAUComps/comp2026'))
            .thenReturn(mockCompRef);
        when(() => mockCompRef.once()).thenAnswer((_) async => mockCompSnapshot);
        when(() => mockCompSnapshot.value).thenReturn({
          'name': 'Comp 2026',
          'aflFixtureJsonURL': 'https://example.com/afl.json',
          'nrlFixtureJsonURL': 'https://example.com/nrl.json',
          'combinedRounds2': [
            {
              'roundStartDate': '2026-01-01T00:00:00Z',
              'roundEndDate': '2026-01-07T23:59:59Z',
            },
            {
              'roundStartDate': '2026-01-08T00:00:00Z',
              'roundEndDate': '2026-01-14T23:59:59Z',
            },
          ],
        });

        when(() => mockDb.ref('/Teams')).thenReturn(mockTeamsRef);
        when(() => mockTeamsRef.once()).thenAnswer((_) async => mockTeamsSnapshot);
        when(() => mockTeamsSnapshot.value).thenReturn({
          'nrl-broncos': {'name': 'Broncos', 'league': 'nrl'},
          'nrl-roosters': {'name': 'Roosters', 'league': 'nrl'},
        });

        when(() => mockDb.ref('/Stats/comp2026/live_scores_v3'))
            .thenReturn(mockLiveScoresRef);
        when(() => mockLiveScoresRef.once())
            .thenAnswer((_) async => mockLiveScoresSnapshot);
        when(() => mockLiveScoresSnapshot.value).thenReturn(null);

        when(() => mockDb.ref('/DAUCompsGames/comp2026'))
            .thenReturn(mockGamesRef);
        when(() => mockGamesRef.once()).thenAnswer((_) async => mockGamesSnapshot);
        when(() => mockGamesSnapshot.value).thenReturn({
          'nrl-01-001': {
            'RoundNumber': 1,
            'MatchNumber': 1,
            'HomeTeam': 'Broncos',
            'AwayTeam': 'Roosters',
            'Location': 'Stadium One',
            'DateUtc': '2026-01-03T10:00:00Z',
            'HomeTeamScore': 10,
            'AwayTeamScore': 30,
          },
          'nrl-02-001': {
            'RoundNumber': 2,
            'MatchNumber': 1,
            'HomeTeam': 'Broncos',
            'AwayTeam': 'Roosters',
            'Location': 'Stadium Two',
            'DateUtc': '2026-01-10T10:00:00Z',
            'HomeTeamScore': 30,
            'AwayTeamScore': 10,
          },
        });

        when(() => mockDb.ref('/AllTippers')).thenReturn(mockAllTippersRef);
        when(() => mockAllTippersRef.once())
            .thenAnswer((_) async => mockAllTippersSnapshot);
        when(() => mockAllTippersSnapshot.value).thenReturn({
          'paid-tipper': {
            'authuid': 'auth-paid',
            'email': 'paid@example.com',
            'name': 'Paid',
            'tipperRole': 'tipper',
            'compsParticipatedIn': ['comp2026'],
            'isAnonymous': false,
          },
          'free-tipper': {
            'authuid': 'auth-free',
            'email': 'free@example.com',
            'name': 'Free',
            'tipperRole': 'tipper',
            'isAnonymous': false,
          },
        });

        when(() => mockDb.ref('/AllTips/comp2026')).thenReturn(mockAllTipsRef);
        when(() => mockAllTipsRef.once())
            .thenAnswer((_) async => mockAllTipsSnapshot);
        when(() => mockAllTipsSnapshot.value).thenReturn({
          'paid-tipper': {},
          'free-tipper': {
            'nrl-01-001': {'r': 'b', 't': 1760000001},
            'nrl-02-001': {'r': 'a', 't': 1760000002},
          },
        });

        when(() => mockDb.ref('/Stats/comp2026/round_stats_backend_v1/1'))
            .thenReturn(mockRoundStatsRootRef);
        when(() => mockRoundStatsRootRef.update(any()))
            .thenAnswer((_) async {});
        when(() => mockDb.ref('/Stats/comp2026/game_stats_backend_v1'))
            .thenReturn(mockGameStatsRootRef);
        when(() => mockGameStatsRootRef.update(any()))
            .thenAnswer((_) async {});
        when(() => mockDb.ref('/Stats/comp2026/scoring_status'))
            .thenReturn(mockStatusRef);
        when(() => mockStatusRef.set(any())).thenAnswer((_) async {});

        final result = await executeBackendScoringCommand(
          db: mockDb,
          command: command,
          now: DateTime.parse('2026-01-03T12:00:00Z'),
        );

        expect(result.skipped, isFalse);
        expect(result.status, 'completed');
        expect(result.message, contains('Admin rescore completed for round 1'));

        final roundUpdates = verify(
          () => mockRoundStatsRootRef.update(captureAny()),
        ).captured.single as Map<String, dynamic>;
        expect(roundUpdates.keys, containsAll(['paid-tipper', 'free-tipper']));
        expect(
          Map<String, dynamic>.from(roundUpdates['paid-tipper'] as Map)['nS'],
          2,
        );
        expect(
          Map<String, dynamic>.from(roundUpdates['free-tipper'] as Map)['nS'],
          0,
        );

        final gameUpdates = verify(
          () => mockGameStatsRootRef.update(captureAny()),
        ).captured.single as Map<String, dynamic>;
        expect(gameUpdates.keys, containsAll([
          'paid/nrl-01-001',
          'free/nrl-01-001',
        ]));
        final paidGameStats = Map<String, dynamic>.from(
          gameUpdates['paid/nrl-01-001'] as Map,
        );
        expect(paidGameStats['pctTipD'], 1.0);
        expect(paidGameStats['avgScoreTipCount'], 1);
        verify(() => mockDb.ref('/AllTips/comp2026')).called(1);
        verify(() => mockIdempotencyRef.set(any())).called(1);
        verify(() => mockStatusRef.set(any())).called(1);
      },
    );
  });
}
