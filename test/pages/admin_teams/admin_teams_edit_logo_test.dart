import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_edit.dart';
import 'package:daufootytipping/widgets/team_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const String _newLogo =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect width="10" height="10" fill="#6A0F38"/></svg>';

final Team _team = Team(
  dbkey: 'nrl-Perth Bears',
  name: 'Perth Bears',
  league: League.nrl,
);

/// Opens the dialog from a button and records what it returned.
Future<List<bool>> _openDialog(WidgetTester tester) async {
  final results = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await confirmTeamLogoReplacement(
              context: context,
              team: _team,
              svg: _newLogo,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('shows the current and the new logo at two sizes', (
    tester,
  ) async {
    await _openDialog(tester);

    expect(find.text('Replace the Perth Bears logo?'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    // No logo is stored yet, so the current one is the initials badge.
    expect(find.byType(TeamLogo), findsNWidgets(2));
    expect(find.text('PB'), findsNWidgets(2));
    expect(find.byType(SvgPicture), findsNWidgets(2));
  });

  testWidgets('returns true only when Replace logo is chosen', (tester) async {
    final results = await _openDialog(tester);
    await tester.tap(find.text('Replace logo'));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('returns false on Cancel or when dismissed', (tester) async {
    final cancelled = await _openDialog(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancelled, [false]);

    final dismissed = await _openDialog(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(dismissed, [false]);
  });
}
