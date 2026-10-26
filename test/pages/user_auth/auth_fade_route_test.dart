import 'package:daufootytipping/pages/user_auth/auth_fade_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fades the new page in over the old one, which stays drawn', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Text('old page')));

    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushReplacement(
          authFadeRoute<void>((context) => const Text('new page')),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('old page'), findsOneWidget);
    final FadeTransition fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('new page'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));

    await tester.pumpAndSettle();

    expect(find.text('old page'), findsNothing);
    expect(find.text('new page'), findsOneWidget);
  });
}
