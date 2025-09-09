import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/services/fixture_import_applier.dart';

void main() {
  Map<String, dynamic> game({required int round, required int match, String league = 'nrl'}) => {
        'RoundNumber': round,
        'MatchNumber': match,
        'Location': 'X',
        'DateUtc': '2025-01-01T00:00:00Z',
      };

  test('buildGameUpdates creates dbkeys and attributes for both leagues', () {
    final applier = const FixtureImportApplier();
    final nrl = [game(round: 1, match: 2)];
    final afl = [game(round: 3, match: 4, league: 'afl')];

    final ops = applier.buildGameUpdates(nrl, afl);
    expect(ops.length, 2);
    expect(ops[0].dbkey, 'nrl-01-002');
    expect(ops[0].league, 'nrl');
    expect(ops[1].dbkey, 'afl-03-004');
    expect(ops[1].league, 'afl');
    expect(ops[0].attributes['RoundNumber'], 1);
    expect(ops[1].attributes['MatchNumber'], 4);
  });

  test('tagGamesWithLeagueInPlace adds league key', () {
    final applier = const FixtureImportApplier();
    final arr = [game(round: 1, match: 1)];
    applier.tagGamesWithLeagueInPlace(arr, 'nrl');
    expect(arr.first['league'], 'nrl');
  });

  test('computeCombinedRoundsIfMissing returns null when rounds exist, list when empty', () {
    final applier = const FixtureImportApplier();
    final compWithRounds = DAUComp(
      dbkey: 'c1',
      name: 'Comp1',
      aflFixtureJsonURL: Uri.parse('https://afl'),
      nrlFixtureJsonURL: Uri.parse('https://nrl'),
      daurounds: const [],
    );

    // Initially empty -> should compute
    final computed = applier.computeCombinedRoundsIfMissing(compWithRounds, [game(round: 1, match: 1)]);
    expect(computed, isNotNull);

    // With rounds -> should return null
    final comp2 = DAUComp(
      dbkey: 'c2',
      name: 'Comp2',
      aflFixtureJsonURL: Uri.parse('https://afl'),
      nrlFixtureJsonURL: Uri.parse('https://nrl'),
      daurounds: computed!,
    );
    final none = applier.computeCombinedRoundsIfMissing(comp2, [game(round: 2, match: 2)]);
    expect(none, isNull);
  });
}

