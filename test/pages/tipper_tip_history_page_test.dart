import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/tip_history_entry.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/tipper_tip_history_page.dart';
import 'package:daufootytipping/repositories/tip_history_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

class FakeTipHistoryRepository implements TipHistoryRepository {
  final List<TipHistoryEntry> entries;

  FakeTipHistoryRepository(this.entries);

  @override
  Future<List<TipHistoryEntry>> fetchCurrentTipHistory(Tipper tipper) async {
    return List<TipHistoryEntry>.from(entries);
  }

  @override
  Future<List<TipHistoryEntry>> fetchTipHistory(Tipper tipper) async {
    return List<TipHistoryEntry>.from(entries);
  }
}

void main() {
  final DateFormat submittedFormat = DateFormat('dd MMM yy HH:mm');

  testWidgets(
    'shows note and renders tip history in reverse chronological order',
    (WidgetTester tester) async {
      final Tipper tipper = Tipper(
        dbkey: 'tipper-1',
        authuid: 'auth-1',
        email: 'tipper@example.com',
        logon: 'tipper@example.com',
        name: 'Tipper',
        tipperRole: TipperRole.tipper,
        compsPaidFor: const [],
      );

      final TipHistoryEntry olderEntry = TipHistoryEntry(
        gameId: 'afl-01-001',
        league: League.afl,
        year: 2024,
        roundNumber: 1,
        homeTeamName: 'Older Home',
        awayTeamName: 'Older Away',
        homeTeamLogoUri: null,
        awayTeamLogoUri: null,
        tip: GameResult.b,
        tipSubmittedUTC: DateTime.utc(2024, 3, 2, 8, 30),
      );
      final TipHistoryEntry newerEntry = TipHistoryEntry(
        gameId: 'nrl-02-001',
        league: League.nrl,
        year: 2025,
        roundNumber: 2,
        homeTeamName: 'Newer Home',
        awayTeamName: 'Newer Away',
        homeTeamLogoUri: null,
        awayTeamLogoUri: null,
        tip: GameResult.d,
        tipSubmittedUTC: DateTime.utc(2025, 3, 4, 10, 15),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TipperTipHistoryPage(
            tipper: tipper,
            repository: FakeTipHistoryRepository(<TipHistoryEntry>[
              olderEntry,
              newerEntry,
            ]),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      final String olderLabel = submittedFormat.format(
        olderEntry.tipSubmittedUTC.toLocal(),
      );
      final String newerLabel = submittedFormat.format(
        newerEntry.tipSubmittedUTC.toLocal(),
      );

      expect(
        find.text(
          'Default [Away] tips are not shown in this list, only actual tips.',
        ),
        findsOneWidget,
      );
      expect(find.text(newerLabel), findsOneWidget);
      expect(find.text(olderLabel), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(newerLabel)).dy,
        lessThan(tester.getTopLeft(find.text(olderLabel)).dy),
      );
    },
  );
}
