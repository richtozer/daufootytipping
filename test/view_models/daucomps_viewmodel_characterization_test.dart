import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/foundation.dart';

void main() {
  group('DAUCompsViewModel (characterization)', () {
    test('groupGamesIntoLeagues splits and sorts games', () {
      final vm = DAUCompsViewModel(null, false, skipInit: true);

      final nrlHome = Team(dbkey: 'nrl-home', name: 'NRL Home', league: League.nrl);
      final nrlAway = Team(dbkey: 'nrl-away', name: 'NRL Away', league: League.nrl);
      final aflHome = Team(dbkey: 'afl-home', name: 'AFL Home', league: League.afl);
      final aflAway = Team(dbkey: 'afl-away', name: 'AFL Away', league: League.afl);

      final games = <Game>[
        Game(
          dbkey: 'nrl-01-002',
          league: League.nrl,
          homeTeam: nrlHome,
          awayTeam: nrlAway,
          location: 'Suncorp',
          startTimeUTC: DateTime.parse('2025-01-01T12:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 2,
        ),
        Game(
          dbkey: 'nrl-01-001',
          league: League.nrl,
          homeTeam: nrlHome,
          awayTeam: nrlAway,
          location: 'Suncorp',
          startTimeUTC: DateTime.parse('2025-01-01T10:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        ),
        Game(
          dbkey: 'afl-01-002',
          league: League.afl,
          homeTeam: aflHome,
          awayTeam: aflAway,
          location: 'MCG',
          startTimeUTC: DateTime.parse('2025-01-02T08:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 2,
        ),
        Game(
          dbkey: 'afl-01-001',
          league: League.afl,
          homeTeam: aflHome,
          awayTeam: aflAway,
          location: 'MCG',
          startTimeUTC: DateTime.parse('2025-01-02T06:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        ),
      ];

      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2025-01-03T00:00:00Z'),
        games: games,
      );

      final grouped = vm.groupGamesIntoLeagues(round);

      expect(grouped[League.nrl]!.length, 2);
      expect(grouped[League.afl]!.length, 2);

      // Verify intra-league sorting by start time then match number
      expect(grouped[League.nrl]![0].fixtureMatchNumber, 1);
      expect(grouped[League.nrl]![1].fixtureMatchNumber, 2);
      expect(grouped[League.afl]![0].fixtureMatchNumber, 1);
      expect(grouped[League.afl]![1].fixtureMatchNumber, 2);
    });

    test('groupGamesIntoLeagues returns defensive copies for cached results', () {
      final vm = DAUCompsViewModel(null, false, skipInit: true);

      final nrlHome = Team(dbkey: 'nrl-home', name: 'NRL Home', league: League.nrl);
      final nrlAway = Team(dbkey: 'nrl-away', name: 'NRL Away', league: League.nrl);

      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2025-01-03T00:00:00Z'),
        games: [
          Game(
            dbkey: 'nrl-01-001',
            league: League.nrl,
            homeTeam: nrlHome,
            awayTeam: nrlAway,
            location: 'Suncorp',
            startTimeUTC: DateTime.parse('2025-01-01T10:00:00Z'),
            fixtureRoundNumber: 1,
            fixtureMatchNumber: 1,
          ),
        ],
      );

      final firstGrouped = vm.groupGamesIntoLeagues(round);
      firstGrouped[League.nrl]!.clear();

      final secondGrouped = vm.groupGamesIntoLeagues(round);

      expect(secondGrouped[League.nrl]!.length, 1);
    });

    test('updateRoundAttribute writes correct update path', () {
      final vm = DAUCompsViewModel(null, false, skipInit: true);

      vm.updateRoundAttribute('comp123', 2, 'roundStartDate', '2025-01-01T00:00:00Z');

      // roundNumber is 1-based; storage uses 0-based index
      final key = '/AllDAUComps/comp123/combinedRounds2/1/roundStartDate';
      expect(vm.updates.containsKey(key), isTrue);
      expect(vm.updates[key], '2025-01-01T00:00:00Z');
    });

    test('updateCompAttribute writes correct update path', () {
      final vm = DAUCompsViewModel(null, false, skipInit: true);

      vm.updateCompAttribute('comp123', 'name', 'My Comp');
      final key = '/AllDAUComps/comp123/name';
      expect(vm.updates.containsKey(key), isTrue);
      expect(vm.updates[key], 'My Comp');
    });

    test('parseCloudFunctionsBaseURLValue accepts nested map values', () {
      expect(
        DAUCompsViewModel.parseCloudFunctionsBaseURLValue({
          'value': 'https://example.com',
        }),
        'https://example.com',
      );
      expect(
        DAUCompsViewModel.parseCloudFunctionsBaseURLValue({
          '.value': 'https://example.org',
        }),
        'https://example.org',
      );
      expect(
        DAUCompsViewModel.parseCloudFunctionsBaseURLValue('  https://example.net  '),
        'https://example.net',
      );
      expect(
        DAUCompsViewModel.parseCloudFunctionsBaseURLValue({'value': null}),
        isNull,
      );
      expect(
        DAUCompsViewModel.parseCloudFunctionsBaseURLValue('1.3.9'),
        isNull,
      );
      expect(
        DAUCompsViewModel.parseCloudFunctionsBaseURLValue({
          'value': '1.3.9',
        }),
        isNull,
      );
    });

    test('resolveCloudFunctionsBaseURLValue prefers override over config', () {
      expect(
        DAUCompsViewModel.resolveCloudFunctionsBaseURLValue(
          configValue: 'https://example.com',
          overrideValue: 'http://localhost:9229',
        ),
        'http://localhost:9229',
      );
      expect(
        DAUCompsViewModel.resolveCloudFunctionsBaseURLValue(
          configValue: 'https://example.com',
          overrideValue: '1.3.9',
        ),
        'https://example.com',
      );
      expect(
        DAUCompsViewModel.resolveCloudFunctionsBaseURLValue(
          configValue: '1.3.9',
          overrideValue: null,
        ),
        isNull,
      );
    });

    test('configured cloud functions URL follows the provider value', () {
      String? configuredUrl = 'https://first.example.com';
      final vm = DAUCompsViewModel(
        null,
        false,
        skipInit: true,
        cloudFunctionsBaseURLOverride: 'not-a-url',
        cloudFunctionsBaseURLProvider: () => configuredUrl,
      );

      expect(
        vm.resolveConfiguredCloudFunctionsBaseURL(),
        'https://first.example.com',
      );

      configuredUrl = 'https://second.example.com';

      expect(
        vm.resolveConfiguredCloudFunctionsBaseURL(),
        'https://second.example.com',
      );
    });

    test('configured scoring URL follows its dedicated provider', () {
      String? configuredUrl = 'https://rescore-one.example.com';
      final vm = DAUCompsViewModel(
        null,
        false,
        skipInit: true,
        cloudFunctionsBaseURLOverride: 'not-a-url',
        adminScoringRescoreURLProvider: () => configuredUrl,
      );

      expect(
        vm.resolveConfiguredAdminScoringRescoreURL(),
        'https://rescore-one.example.com',
      );

      configuredUrl = 'https://rescore-two.example.com';

      expect(
        vm.resolveConfiguredAdminScoringRescoreURL(),
        'https://rescore-two.example.com',
      );
    });

    test('backend rescore loads a URL when the provider is not ready', () async {
      var loadCount = 0;
      final vm = DAUCompsViewModel(
        null,
        false,
        skipInit: true,
        cloudFunctionsBaseURLOverride: 'not-a-url',
        adminScoringRescoreURLProvider: () => null,
        adminScoringRescoreURLLoader: () async {
          loadCount += 1;
          return 'not-a-url';
        },
      );
      final comp = DAUComp(
        dbkey: 'comp-2026',
        name: 'Test Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: const [],
      );

      await expectLater(vm.rescoreWithBackend(comp), throwsStateError);
      expect(loadCount, 1);
    });

    test('deployed callable URL remains a complete service URL', () {
      const configuredUrl =
          'https://admin-scoring-rescore-example.as.a.run.app';

      expect(
        DAUCompsViewModel.deployedAdminCallableURL(configuredUrl),
        configuredUrl,
      );
    });

    test('resolveDefaultCloudFunctionsBaseURLOverride uses emulator host', () {
      expect(
        DAUCompsViewModel.resolveDefaultCloudFunctionsBaseURLOverride(
          useFirebaseEmulators: true,
          configuredFirebaseEmulatorHost: 'localhost',
          isDebugMode: true,
          isWeb: false,
          targetPlatform: TargetPlatform.iOS,
        ),
        'http://localhost:9229/dau-footy-tipping-f8a42/asia-southeast1',
      );
      expect(
        DAUCompsViewModel.resolveDefaultCloudFunctionsBaseURLOverride(
          useFirebaseEmulators: true,
          configuredFirebaseEmulatorHost: '',
          isDebugMode: true,
          isWeb: false,
          targetPlatform: TargetPlatform.android,
        ),
        'http://10.0.2.2:9229/dau-footy-tipping-f8a42/asia-southeast1',
      );
      expect(
        DAUCompsViewModel.resolveDefaultCloudFunctionsBaseURLOverride(
          useFirebaseEmulators: false,
          configuredFirebaseEmulatorHost: 'localhost',
          isDebugMode: true,
          isWeb: false,
          targetPlatform: TargetPlatform.iOS,
        ),
        isNull,
      );
    });

    test('cloudFunctionFixtureDownloadMessage handles response shapes', () {
      expect(
        DAUCompsViewModel.cloudFunctionFixtureDownloadMessage({
          'success': true,
          'message': 'Downloaded fixtures',
        }),
        'Downloaded fixtures',
      );
      expect(
        DAUCompsViewModel.cloudFunctionFixtureDownloadMessage({
          'success': true,
        }),
        'Successfully updated fixtures via Cloud Function',
      );
      expect(
        DAUCompsViewModel.cloudFunctionFixtureDownloadMessage(null),
        'Successfully updated fixtures via Cloud Function',
      );
    });
  });
}
