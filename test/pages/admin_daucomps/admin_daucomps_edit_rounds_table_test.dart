import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_datetimepickerfield.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_rounds_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpTable(
    WidgetTester tester,
    DAURound round, {
    void Function(DAURound round, DateTime newDate)? onRoundDateChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditRoundsTable(
            rounds: <DAURound>[round],
            onRoundDateChanged: onRoundDateChanged ?? (_, _) {},
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
    'shows the UTC start date without time, uses Round Start (UTC) heading, and omits end column',
    (tester) async {
      final firstKickoff = DateTime.utc(2026, 3, 5, 8, 0);
      final lastKickoff = DateTime.utc(2026, 3, 8, 6, 30);
      await pumpTable(tester, _buildRound(1, firstKickoff, lastKickoff));

      expect(find.text('Round Start (UTC)'), findsOneWidget);
      expect(find.text('First Kickoff (UTC)'), findsNothing);
      expect(fieldText(tester, 'start-1'), 'Thu 5/3');
      expect(find.text('Last kickoff'), findsNothing);
      expect(find.byKey(const ValueKey('end-1')), findsNothing);
    },
  );

  testWidgets(
    'shows the admin override start date without time, not the kickoff date',
    (tester) async {
      final overrideStart = DateTime.utc(2026, 3, 4, 2, 15);
      final round = _buildRound(
        1,
        DateTime.utc(2026, 3, 5, 8, 0),
        DateTime.utc(2026, 3, 8, 6, 30),
      )..adminOverrideRoundStartDate = overrideStart;
      await pumpTable(tester, round);

      expect(fieldText(tester, 'start-1'), 'Wed 4/3');
    },
  );

  testWidgets('picking a date calls onRoundDateChanged with 0:00 UTC', (
    tester,
  ) async {
    DateTime? reportedDate;
    final round = _buildRound(
      1,
      DateTime.utc(2026, 3, 5, 8, 0),
      DateTime.utc(2026, 3, 8, 6, 30),
    );
    await pumpTable(
      tester,
      round,
      onRoundDateChanged: (_, newDate) => reportedDate = newDate,
    );

    await tester.tap(find.byKey(const ValueKey('start-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(reportedDate, DateTime.utc(2026, 3, 6));
    expect(reportedDate?.isUtc, isTrue);
  });

  testWidgets('picking the date a round already starts on changes nothing', (
    tester,
  ) async {
    var calls = 0;
    final round = _buildRound(
      1,
      DateTime.utc(2026, 3, 5, 8, 0),
      DateTime.utc(2026, 3, 8, 6, 30),
    );
    await pumpTable(tester, round, onRoundDateChanged: (_, _) => calls++);

    await tester.tap(find.byKey(const ValueKey('start-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(fieldText(tester, 'start-1'), 'Thu 5/3');
  });

  testWidgets('shows a round with no games so it can still be edited', (
    tester,
  ) async {
    final emptyRound = DAURound(
      dAUroundNumber: 2,
      firstGameKickOffUTC: DateTime.utc(2026, 3, 12),
      lastGameKickOffUTC: DateTime.utc(2026, 3, 12),
    );
    await pumpTable(tester, emptyRound);

    expect(find.byKey(const ValueKey('start-2')), findsOneWidget);
    expect(fieldText(tester, 'start-2'), 'Thu 12/3');
  });

  test('formatRoundDateTime formats the UTC date without time', () {
    final thursdayUtc = DateTime.utc(2026, 11, 12, 23, 50);
    final fridayUtc = DateTime.utc(2026, 3, 6, 0, 5);
    final localConvertedToUtc = DateTime.fromMillisecondsSinceEpoch(
      DateTime.utc(2026, 3, 5, 19, 50).millisecondsSinceEpoch,
      isUtc: false,
    );

    expect(formatRoundDateTime(thursdayUtc), 'Thu 12/11');
    expect(formatRoundDateTime(fridayUtc), 'Fri 6/3');
    expect(formatRoundDateTime(localConvertedToUtc), 'Thu 5/3');
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
