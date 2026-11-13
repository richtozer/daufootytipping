import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/repositories/daucomps_repository.dart';
import 'package:daufootytipping/services/url_health_checker.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';

class _MockGamesViewModel extends Mock implements GamesViewModel {}

class _FakeDauCompsRepository implements DauCompsRepository {
  Map<String, dynamic>? capturedUpdates;

  @override
  Stream<DatabaseEvent> streamDauComps(String daucompsPath) =>
      const Stream.empty();

  @override
  Future<void> update(Map<String, dynamic> updates) async {
    capturedUpdates = updates;
  }

  @override
  Future<String> newCompKey(String daucompsPath) async =>
      throw UnimplementedError('not exercised when saving an existing comp');
}

void main() {
  group('DAUCompsViewModel.processAndSaveDauComp', () {
    test('editing only the end date on an existing comp skips the URL health '
        'check, saves successfully, persists the new dates, and runs fixture download', () async {
      final repo = _FakeDauCompsRepository();
      DAUComp? downloadedComp;
      final vm = DAUCompsViewModel(
        null,
        true,
        skipInit: true,
        repo: repo,
        networkFixtureDownloader: (comp) async {
          downloadedComp = comp;
          return 'Fixture download succeeded';
        },
        urlHealthChecker: UrlHealthChecker(
          remoteChecker: (_) async {
            fail(
              'URL health check should be skipped when the fixture URLs '
              'are unchanged from the saved comp',
            );
          },
        ),
      );
      vm.completeInitialDAUCompLoadForTest();

      final existingComp = DAUComp(
        dbkey: 'comp-2026',
        name: 'Test Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl.json'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl.json'),
        daurounds: const [],
      );

      final result = await vm.processAndSaveDauComp(
        name: existingComp.name,
        aflFixtureJsonURL: existingComp.aflFixtureJsonURL.toString(),
        nrlFixtureJsonURL: existingComp.nrlFixtureJsonURL.toString(),
        nrlRegularCompEndDateString: '2026-08-31',
        aflRegularCompEndDateString: '2026-09-01',
        existingComp: existingComp,
        currentRounds: const [],
      );

      expect(result['success'], isTrue);
      expect(
        result['message'],
        'DAUComp record saved. Fixture download succeeded',
      );
      expect(downloadedComp, same(existingComp));

      final updates = repo.capturedUpdates;
      expect(updates, isNotNull);
      expect(
        updates!['/AllDAUComps/comp-2026/nrlRegularCompEndDateUTC'],
        DateTime.parse('2026-08-31').toIso8601String(),
      );
      expect(
        updates['/AllDAUComps/comp-2026/aflRegularCompEndDateUTC'],
        DateTime.parse('2026-09-01').toIso8601String(),
      );
    });

    test('editing only the name skips fixture download and returns save message', () async {
      final repo = _FakeDauCompsRepository();
      var downloadCalled = false;
      final vm = DAUCompsViewModel(
        null,
        true,
        skipInit: true,
        repo: repo,
        networkFixtureDownloader: (_) async {
          downloadCalled = true;
          return 'should not run';
        },
      );
      vm.completeInitialDAUCompLoadForTest();

      final existingComp = DAUComp(
        dbkey: 'comp-2026',
        name: 'Old Name',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl.json'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl.json'),
        daurounds: const [],
      );

      final result = await vm.processAndSaveDauComp(
        name: 'New Name',
        aflFixtureJsonURL: existingComp.aflFixtureJsonURL.toString(),
        nrlFixtureJsonURL: existingComp.nrlFixtureJsonURL.toString(),
        nrlRegularCompEndDateString: null,
        aflRegularCompEndDateString: null,
        existingComp: existingComp,
        currentRounds: const [],
      );

      expect(result['success'], isTrue);
      expect(result['message'], 'DAUComp record saved');
      expect(downloadCalled, isFalse);
      expect(repo.capturedUpdates?['/AllDAUComps/comp-2026/name'], 'New Name');
    });

    test('reports failed post-save fixture download separately while preserving saved updates', () async {
      final repo = _FakeDauCompsRepository();
      final vm = DAUCompsViewModel(
        null,
        true,
        skipInit: true,
        repo: repo,
        networkFixtureDownloader: (_) async {
          throw StateError('network timeout');
        },
      );
      vm.completeInitialDAUCompLoadForTest();

      final existingComp = DAUComp(
        dbkey: 'comp-2026',
        name: 'Test Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl.json'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl.json'),
        daurounds: const [],
      );

      final result = await vm.processAndSaveDauComp(
        name: existingComp.name,
        aflFixtureJsonURL: existingComp.aflFixtureJsonURL.toString(),
        nrlFixtureJsonURL: existingComp.nrlFixtureJsonURL.toString(),
        nrlRegularCompEndDateString: '2026-08-31',
        aflRegularCompEndDateString: null,
        existingComp: existingComp,
        currentRounds: const [],
      );

      expect(repo.capturedUpdates, isNotNull);
      expect(result['success'], isFalse);
      expect(
        result['message'],
        startsWith('DAUComp record saved, but fixture download failed:'),
      );
      expect(result['message'], contains('network timeout'));
    });

    test('re-validates round start and cutoff edits against in-memory games right before saving', () async {
      final repo = _FakeDauCompsRepository();
      final mockGamesVm = _MockGamesViewModel();
      var downloadCalled = false;
      final vm = DAUCompsViewModel(
        null,
        true,
        skipInit: true,
        repo: repo,
        networkFixtureDownloader: (_) async {
          downloadCalled = true;
          return 'should not run';
        },
      );
      vm.gamesViewModel = mockGamesVm;
      vm.completeInitialDAUCompLoadForTest();

      final nrlHome = Team(dbkey: 'nrl-h', name: 'H', league: League.nrl);
      final nrlAway = Team(dbkey: 'nrl-a', name: 'A', league: League.nrl);
      final unscoredGame = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: nrlHome,
        awayTeam: nrlAway,
        location: 'X',
        startTimeUTC: DateTime.utc(2026, 3, 1, 18, 0),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
      // Game was unscored when edited, then received an official score in the listener.
      final scoredGame = Game(
        dbkey: 'nrl-01-002',
        league: League.nrl,
        homeTeam: nrlHome,
        awayTeam: nrlAway,
        location: 'X',
        startTimeUTC: DateTime.utc(2026, 3, 1, 20, 0),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 2,
        scoring: Scoring(homeTeamScore: 18, awayTeamScore: 12),
      );
      when(() => mockGamesVm.getGames()).thenAnswer(
        (_) async => [unscoredGame, scoredGame],
      );

      final round1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.utc(2026, 3, 1, 17, 0),
        lastGameKickOffUTC: DateTime.utc(2026, 3, 1, 23, 0),
      );
      final round2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: DateTime.utc(2026, 3, 2, 10, 0),
        lastGameKickOffUTC: DateTime.utc(2026, 3, 2, 23, 0),
      );
      final existingComp = DAUComp(
        dbkey: 'comp-2026',
        name: 'Test Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl.json'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl.json'),
        daurounds: [round1, round2],
      );
      when(() => mockGamesVm.selectedDAUComp).thenReturn(existingComp);

      // Admin moved Round 2 start before 20:00 while nrl-01-002 was unscored.
      final editedRound2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: DateTime.utc(2026, 3, 2, 10, 0),
        lastGameKickOffUTC: DateTime.utc(2026, 3, 2, 23, 0),
        adminOverrideRoundStartDate: DateTime.utc(2026, 3, 1, 19, 0),
      );

      final startValidationFail = await vm.processAndSaveDauComp(
        name: existingComp.name,
        aflFixtureJsonURL: existingComp.aflFixtureJsonURL.toString(),
        nrlFixtureJsonURL: existingComp.nrlFixtureJsonURL.toString(),
        nrlRegularCompEndDateString: null,
        aflRegularCompEndDateString: null,
        existingComp: existingComp,
        currentRounds: [round1, editedRound2],
        initialRoundStartOverrides: const {1: null, 2: null},
      );

      expect(startValidationFail['success'], isFalse);
      expect(startValidationFail['message'], contains('scored game nrl-01-002'));
      expect(repo.capturedUpdates, isNull);
      expect(downloadCalled, isFalse);

      // Moving NRL cutoff before the scored game is also rejected before write.
      final cutoffValidationFail = await vm.processAndSaveDauComp(
        name: existingComp.name,
        aflFixtureJsonURL: existingComp.aflFixtureJsonURL.toString(),
        nrlFixtureJsonURL: existingComp.nrlFixtureJsonURL.toString(),
        nrlRegularCompEndDateString: '2026-02-28',
        aflRegularCompEndDateString: null,
        existingComp: existingComp,
        currentRounds: [round1, round2],
        initialRoundStartOverrides: const {1: null, 2: null},
      );

      expect(cutoffValidationFail['success'], isFalse);
      expect(cutoffValidationFail['message'], contains('scored game nrl-01-002'));
      expect(repo.capturedUpdates, isNull);
      expect(downloadCalled, isFalse);
    });

    test(
        'a comp with a scored finals game after its cutoff succeeds when saved '
        'with cutoff unchanged and when cutoff moves later', () async {
      final repo = _FakeDauCompsRepository();
      final mockGamesVm = _MockGamesViewModel();
      var downloadCalls = 0;
      final vm = DAUCompsViewModel(
        null,
        true,
        skipInit: true,
        repo: repo,
        networkFixtureDownloader: (_) async {
          downloadCalls++;
          return 'Download complete';
        },
      );
      vm.gamesViewModel = mockGamesVm;
      vm.completeInitialDAUCompLoadForTest();

      final nrlHome = Team(dbkey: 'nrl-h', name: 'H', league: League.nrl);
      final nrlAway = Team(dbkey: 'nrl-a', name: 'A', league: League.nrl);
      final scoredFinalsGame = Game(
        dbkey: 'nrl-27-001',
        league: League.nrl,
        homeTeam: nrlHome,
        awayTeam: nrlAway,
        location: 'Stadium',
        startTimeUTC: DateTime.utc(2026, 9, 5, 10, 0),
        fixtureRoundNumber: 27,
        fixtureMatchNumber: 1,
        scoring: Scoring(homeTeamScore: 24, awayTeamScore: 16),
      );
      when(() => mockGamesVm.getGames()).thenAnswer(
        (_) async => [scoredFinalsGame],
      );

      final round1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.utc(2026, 3, 1, 17, 0),
        lastGameKickOffUTC: DateTime.utc(2026, 3, 1, 23, 0),
      );
      final existingComp = DAUComp(
        dbkey: 'comp-2026',
        name: 'Test Comp 2026',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl.json'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl.json'),
        nrlRegularCompEndDateUTC: DateTime.parse('2026-08-31'),
        daurounds: [round1],
      );
      when(() => mockGamesVm.selectedDAUComp).thenReturn(existingComp);

      // 1) Save with cutoff unchanged (e.g. a comp rename).
      final unchangedSave = await vm.processAndSaveDauComp(
        name: 'Renamed 2026 Comp',
        aflFixtureJsonURL: existingComp.aflFixtureJsonURL.toString(),
        nrlFixtureJsonURL: existingComp.nrlFixtureJsonURL.toString(),
        nrlRegularCompEndDateString: '2026-08-31',
        aflRegularCompEndDateString: null,
        existingComp: existingComp,
        currentRounds: [round1],
        initialRoundStartOverrides: const {1: null},
      );

      expect(unchangedSave['success'], isTrue);
      expect(repo.capturedUpdates, isNotNull);
      expect(downloadCalls, 0);

      // 2) Move NRL cutoff later, even though scoredFinalsGame is after it.
      repo.capturedUpdates = null;
      final movedLaterSave = await vm.processAndSaveDauComp(
        name: existingComp.name,
        aflFixtureJsonURL: existingComp.aflFixtureJsonURL.toString(),
        nrlFixtureJsonURL: existingComp.nrlFixtureJsonURL.toString(),
        nrlRegularCompEndDateString: '2026-09-15',
        aflRegularCompEndDateString: null,
        existingComp: existingComp,
        currentRounds: [round1],
        initialRoundStartOverrides: const {1: null},
      );

      expect(movedLaterSave['success'], isTrue);
      expect(repo.capturedUpdates, isNotNull);
      expect(downloadCalls, 1);
    });
  });
}
