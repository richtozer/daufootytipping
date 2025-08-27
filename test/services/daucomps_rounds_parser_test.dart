import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/services/daucomps_rounds_parser.dart';

void main() {
  group('DaucompsRoundsParser', () {
    final parser = DaucompsRoundsParser();

    test('parseRounds builds rounds from JSON array', () {
      final json = {
        'combinedRounds2': [
          {'roundStartDate': '2025-01-01T00:00:00Z', 'roundEndDate': '2025-01-02T00:00:00Z'},
          {'roundStartDate': '2025-01-08T00:00:00Z', 'roundEndDate': '2025-01-09T00:00:00Z'},
        ]
      };
      final rounds = parser.parseRounds(json);
      expect(rounds.length, 2);
      expect(rounds.first.dAUroundNumber, 1);
      expect(rounds.last.dAUroundNumber, 2);
    });

    test('computeGreaterEndDate returns later of AFL/NRL cutoff', () {
      final comp = DAUComp(
        dbkey: 'c',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: <DAURound>[],
        aflRegularCompEndDateUTC: DateTime.parse('2025-08-10T00:00:00Z'),
        nrlRegularCompEndDateUTC: DateTime.parse('2025-08-12T00:00:00Z'),
      );
      final d = parser.computeGreaterEndDate(comp);
      expect(d, DateTime.parse('2025-08-12T00:00:00Z'));
    });

    test('applyCutoffFilter removes rounds after cutoff', () {
      final rounds = <DAURound>[
        DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.parse('2025-08-01T00:00:00Z'),
          lastGameKickOffUTC: DateTime.parse('2025-08-01T12:00:00Z'),
        ),
        DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.parse('2025-09-01T00:00:00Z'),
          lastGameKickOffUTC: DateTime.parse('2025-09-01T12:00:00Z'),
        ),
      ];
      final comp = DAUComp(
        dbkey: 'c',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: rounds,
        aflRegularCompEndDateUTC: DateTime.parse('2025-08-15T00:00:00Z'),
      );
      parser.applyCutoffFilter(comp);
      expect(comp.daurounds.length, 1);
      expect(comp.daurounds.first.dAUroundNumber, 1);
    });
  });
}

