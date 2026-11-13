import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_rounds_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpTable(WidgetTester tester, DAURound round) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditRoundsTable(
            rounds: <DAURound>[round],
            onRoundDateChanged: (_, _) {},
          ),
        ),
      ),
    );
  }

  String fieldText(WidgetTester tester, String fieldKey) {
    final field = tester.widget<DateTimePickerField>(
      find.byKey(ValueKey(fieldKey)),
    );
    return field.controller.text;
  }

  testWidgets(
    'shows the kickoff date and time when there is no override and omits end column',
    (tester) async {
      final firstKickoff = DateTime.utc(2026, 3, 5, 8, 0);
      final lastKickoff = DateTime.utc(2026, 3, 8, 6, 30);
      await pumpTable(tester, _buildRound(1, firstKickoff, lastKickoff));

      expect(fieldText(tester, 'start-1'), formatRoundDateTime(firstKickoff));
      expect(find.text('Last kickoff'), findsNothing);
      expect(find.byKey(const ValueKey('end-1')), findsNothing);
    },
  );

  testWidgets(
    'shows the admin override start date and time, not the kickoff time',
    (tester) async {
      final overrideStart = DateTime.utc(2026, 3, 4, 2, 15);
      final round = _buildRound(
        1,
        DateTime.utc(2026, 3, 5, 8, 0),
        DateTime.utc(2026, 3, 8, 6, 30),
      )..adminOverrideRoundStartDate = overrideStart;
      await pumpTable(tester, round);

      expect(fieldText(tester, 'start-1'), formatRoundDateTime(overrideStart));
    },
  );

  test('formatRoundDateTime abbreviates the meridiem', () {
    final afternoon = DateTime(2026, 3, 5, 19, 50);
    final morning = DateTime(2026, 3, 6, 9, 5);

    expect(formatRoundDateTime(afternoon), 'Thu 5/3 7:50p');
    expect(formatRoundDateTime(morning), 'Fri 6/3 9:05a');
  });
}

DAURound _buildRound(int number, DateTime start, DateTime end) {
  return DAURound(
    dAUroundNumber: number,
    firstGameKickOffUTC: start,
    lastGameKickOffUTC: end,
    games: <Game>[
      Game(
        dbkey: 'nrl-${number.toString().padLeft(2, '0')}-001',
        league: League.nrl,
        homeTeam: Team(
          dbkey: 'nrl-home-$number',
          name: 'Home $number',
          league: League.nrl,
        ),
        awayTeam: Team(
          dbkey: 'nrl-away-$number',
          name: 'Away $number',
          league: League.nrl,
        ),
        location: 'Test Stadium',
        startTimeUTC: start,
        fixtureRoundNumber: number,
        fixtureMatchNumber: 1,
      ),
    ],
  );
}
