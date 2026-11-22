import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';

void main() {
  group('DAUComp model helpers', () {
    test('latestsCompletedRoundNumber uses +6h past threshold', () {
      final now = DateTime.now().toUtc();
      final r1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(days: 3)),
        lastGameKickOffUTC: now.subtract(const Duration(days: 2)),
      );
      final r2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: now.subtract(const Duration(days: 1)),
        lastGameKickOffUTC: now.subtract(
          const Duration(hours: 7),
        ), // +6h => past
      );
      final r3 = DAURound(
        dAUroundNumber: 3,
        firstGameKickOffUTC: now.subtract(const Duration(hours: 2)),
        lastGameKickOffUTC: now.subtract(
          const Duration(hours: 1),
        ), // +6h => future
      );
      final comp = DAUComp(
        name: 'c',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [r1, r2, r3],
      );

      expect(comp.latestsCompletedRoundNumber(), 2);
    });

    test(
      'latestRoundWithGamesCompletedOrUnderway prioritizes started over ended',
      () {
        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.now().toUtc(),
          lastGameKickOffUTC: DateTime.now().toUtc(),
        )..roundState = RoundState.allGamesEnded;
        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.now().toUtc(),
          lastGameKickOffUTC: DateTime.now().toUtc(),
        )..roundState = RoundState.started;
        final r3 = DAURound(
          dAUroundNumber: 3,
          firstGameKickOffUTC: DateTime.now().toUtc(),
          lastGameKickOffUTC: DateTime.now().toUtc(),
        )..roundState = RoundState.notStarted;

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1, r2, r3],
        );

        expect(comp.latestRoundWithGamesCompletedOrUnderway(), 2);
      },
    );

    test(
      'firstNotEndedRoundNumber finds first not-started/started from end',
      () {
        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.now().toUtc(),
          lastGameKickOffUTC: DateTime.now().toUtc(),
        )..roundState = RoundState.allGamesEnded;
        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.now().toUtc(),
          lastGameKickOffUTC: DateTime.now().toUtc(),
        )..roundState = RoundState.started;
        final r3 = DAURound(
          dAUroundNumber: 3,
          firstGameKickOffUTC: DateTime.now().toUtc(),
          lastGameKickOffUTC: DateTime.now().toUtc(),
        )..roundState = RoundState.notStarted;
        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1, r2, r3],
        );

        expect(comp.firstNotEndedRoundNumber(), 2);
      },
    );
  });

  test('a cutoff saved without a time zone, as older comps were, is read as '
      'UTC, the same instant the backend uses', () {
    final comp = DAUComp.fromJson(
      {
        'name': 'DAU 2026',
        'aflFixtureJsonURL': 'https://afl',
        'nrlFixtureJsonURL': 'https://nrl',
        'nrlRegularCompEndDateUTC': '2026-09-07T00:00:00.000',
        'aflRegularCompEndDateUTC': '2026-09-02T00:00:00.000Z',
      },
      'comp-2026',
      [],
    );

    expect(comp.nrlRegularCompEndDateUTC, DateTime.utc(2026, 9, 7));
    expect(comp.aflRegularCompEndDateUTC, DateTime.utc(2026, 9, 2));
  });
}
