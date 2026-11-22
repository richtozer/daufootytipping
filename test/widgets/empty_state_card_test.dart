import 'package:daufootytipping/widgets/empty_state_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows its title and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateCard(
            title: 'Ladder coming soon',
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

  testWidgets('keeps to the height of its message when its slot is taller, '
      'as the ladder page\'s table slot is', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: EmptyStateCard(
              title: 'Ladder coming soon',
              message: 'Standings will appear once Round 1 is complete.',
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(Card)).height, lessThan(150));
  });
}
