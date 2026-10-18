import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every kind of button takes the card corner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: withCardCornerButtons(ThemeData()),
        home: Scaffold(
          body: Column(
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('elevated')),
              FilledButton(onPressed: () {}, child: const Text('filled')),
              OutlinedButton(onPressed: () {}, child: const Text('outlined')),
              TextButton(onPressed: () {}, child: const Text('text')),
            ],
          ),
        ),
      ),
    );

    for (final label in ['elevated', 'filled', 'outlined', 'text']) {
      final material = tester.widget<Material>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first,
      );
      // Compared by corner alone: an outlined button's shape also carries its
      // outline.
      expect(
        (material.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(kCardCornerRadius),
        reason: '$label button',
      );
    }
  });

  testWidgets('a button that sets its own shape keeps it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: withCardCornerButtons(ThemeData()),
        home: Scaffold(
          body: ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: const RoundedRectangleBorder(),
            ),
            onPressed: () {},
            child: const Text('keypad'),
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('keypad'), matching: find.byType(Material))
          .first,
    );
    expect(material.shape, const RoundedRectangleBorder());
  });

  testWidgets('the shared panel colour is far more transparent in dark mode', (
    tester,
  ) async {
    late Color light;
    late Color dark;
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: Builder(
            builder: (context) {
              final colour = appPanelColor(context);
              if (brightness == Brightness.light) {
                light = colour;
              } else {
                dark = colour;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }

    expect(light, kPanelLightColor);
    expect(dark, kPanelDarkColor);
    expect(dark.a, lessThan(light.a / 2));
  });

  testWidgets('text on the see-through panel is light in dark mode only', (
    tester,
  ) async {
    Future<Color?> panelTextColour(Brightness brightness) async {
      Color? colour;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                colour = appPanelTextTheme(context).titleMedium?.color;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return colour;
    }

    final light = await panelTextColour(Brightness.light);
    final dark = await panelTextColour(Brightness.dark);

    expect(dark, Colors.white);
    expect(light, isNot(Colors.white), reason: 'the theme keeps its own text');
  });

  testWidgets('inner panels are dark in dark mode and untouched in light', (
    tester,
  ) async {
    Future<Color?> innerColour(Brightness brightness) async {
      Color? colour;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: Builder(
            builder: (context) {
              colour = appInnerPanelColor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return colour;
    }

    expect(await innerColour(Brightness.light), isNull);
    expect(await innerColour(Brightness.dark), kInnerPanelDarkColor);
  });
}
