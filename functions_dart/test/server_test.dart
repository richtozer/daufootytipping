import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_functions/firebase_functions.dart' hide DataSnapshot;
import 'package:firebase_dart/database.dart';
import 'package:firebase_dart/standalone_database.dart';
import '../bin/server.dart';

class MockDatabase extends Mock {
  DatabaseReference ref([String? path]) => noSuchMethod(
        Invocation.method(#ref, [path]),
      ) as DatabaseReference;
}
class MockDatabaseReference extends Mock implements DatabaseReference {}
class MockDataSnapshot extends Mock implements DataSnapshot {}
class MockTransactionResult extends Mock implements TransactionResult {}

void main() {
  late MockDatabase mockDb;
  late MockDataSnapshot mockRoleSnapshot;

  setUp(() {
    mockDb = MockDatabase();
    mockRoleSnapshot = MockDataSnapshot();
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
  });
}
