import 'package:daufootytipping/widgets/ladder_empty_state_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the ladder empty-state message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LadderEmptyStateCard(
            message: 'Standings will appear once Round 1 is complete.',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.leaderboard_outlined), findsNothing);
    expect(find.text('Ladder coming soon'), findsOneWidget);
    expect(
      find.text('Standings will appear once Round 1 is complete.'),
      findsOneWidget,
    );
  });
}
