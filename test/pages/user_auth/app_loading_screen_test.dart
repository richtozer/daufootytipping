import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_auth/app_loading_screen.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpLoader(WidgetTester tester, Brightness brightness) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(platformBrightness: brightness),
        child: const MaterialApp(home: AppLoadingScreen()),
      ),
    );
  }

  Color veilColour(WidgetTester tester) => tester
      .widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(UserAuthBackground),
              matching: find.byType(ColoredBox),
            )
            .first,
      )
      .color;

  // The home page veils the backdrop with these, so the loader and sign-in
  // screens must too, or the background jumps when moving between them.
  testWidgets('veils the backdrop as the home page does in light mode', (
    tester,
  ) async {
    await pumpLoader(tester, Brightness.light);

    expect(veilColour(tester), Colors.white54);
  });

  testWidgets('veils the backdrop as the home page does in dark mode', (
    tester,
  ) async {
    await pumpLoader(tester, Brightness.dark);

    expect(veilColour(tester), Colors.black54);
  });

  testWidgets('spins in the AFL red', (tester) async {
    await pumpLoader(tester, Brightness.light);

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      League.afl.colour,
    );
  });
}
