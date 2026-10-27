import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_pill.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_destination.dart';

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/load_tips_fonts.dart';

const _destinations = [
  AppNavDestination(
    icon: Icon(Icons.sports_rugby_outlined),
    shortLabel: 'TIPS',
  ),
  AppNavDestination(icon: Icon(Icons.auto_graph), shortLabel: 'STATS'),
  AppNavDestination(
    icon: Icon(Icons.person),
    shortLabel: 'PROFILE',
    enabled: false,
  ),
];

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MediaQuery(
    data: MediaQueryData(platformBrightness: brightness),
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  setUpAll(loadTipsFonts);

  group('AppGlassPill', () {
    testWidgets('shows every destination label', (tester) async {
      await tester.pumpWidget(
        _host(
          AppGlassPill(
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.text('TIPS'), findsOneWidget);
      expect(find.text('STATS'), findsOneWidget);
      expect(find.text('PROFILE'), findsOneWidget);
    });

    testWidgets('reports the tapped destination', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        _host(
          AppGlassPill(
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (index) => tapped = index,
          ),
        ),
      );
      await tester.tap(find.text('STATS'));
      expect(tapped, 1);
    });

    testWidgets('does not report a disabled destination', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        _host(
          AppGlassPill(
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (index) => tapped = index,
          ),
        ),
      );
      await tester.tap(find.text('PROFILE'));
      expect(tapped, isNull);
    });

    testWidgets('marks only the selected destination as selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppGlassPill(
            destinations: _destinations,
            selectedIndex: 1,
            onSelected: (_) {},
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('STATS')),
        isSemantics(
          label: 'STATS',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('TIPS'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      handle.dispose();
    });

    testWidgets('the longest label fits the slim side chip', (tester) async {
      // In the app's own font: the default test font is far wider than Roboto.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            body: Center(
              child: AppGlassPill(
                destinations: const [
                  AppNavDestination(
                    icon: Icon(Icons.person),
                    shortLabel: 'PROFILE',
                  ),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
                axis: Axis.vertical,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.text('PROFILE')).width,
        lessThanOrEqualTo(kGlassSideItemWidth),
      );
    });

    testWidgets('spaces the letters of the longest label inside the chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            body: Center(
              child: AppGlassPill(
                destinations: const [
                  AppNavDestination(
                    icon: Icon(Icons.person),
                    shortLabel: 'PROFILE',
                  ),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('PROFILE'));
      expect(text.style!.letterSpacing, kGlassHorizontalLabelSpacing);
      final label = tester.getSize(find.text('PROFILE')).width;
      expect(label, lessThanOrEqualTo(kGlassHorizontalTabWidth));
    });

    for (final axis in Axis.values) {
      for (final scale in [1.0, 1.35, 2.0, 3.0]) {
        testWidgets('holds its labels at text scale $scale ($axis)', (
          tester,
        ) async {
          // An overflow in the tab would fail the test on its own.
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: AppGlassPill(
                    destinations: _destinations,
                    selectedIndex: 0,
                    onSelected: (_) {},
                    axis: axis,
                  ),
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          final tab = tester.getSize(
            find.ancestor(
              of: find.text('TIPS'),
              matching: find.byType(AnimatedContainer),
            ),
          );
          expect(tab.height, kGlassItemExtent);
        });
      }
    }

    testWidgets('lines labels up whatever size each icon is', (tester) async {
      await tester.pumpWidget(
        _host(
          AppGlassPill(
            destinations: const [
              AppNavDestination(
                icon: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(child: Icon(Icons.sports_rugby_outlined)),
                ),
                shortLabel: 'TIPS',
              ),
              AppNavDestination(
                icon: Icon(Icons.auto_graph),
                shortLabel: 'STATS',
              ),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('TIPS')).dy,
        tester.getTopLeft(find.text('STATS')).dy,
      );
    });

    testWidgets('is as thick as a glass control across its short axis', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppGlassPill(
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      );
      final horizontal = tester.getSize(find.byType(AppGlassPill));
      expect(horizontal.height, kGlassHorizontalThickness);
      expect(
        horizontal.width,
        kGlassHorizontalTabWidth * _destinations.length + 2 * kGlassPadding,
      );

      await tester.pumpWidget(
        _host(
          AppGlassPill(
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
            axis: Axis.vertical,
          ),
        ),
      );
      final vertical = tester.getSize(find.byType(AppGlassPill));
      expect(vertical.width, kGlassSideThickness);
      expect(
        vertical.height,
        kGlassItemExtent * _destinations.length + 2 * kGlassPadding,
      );
    });

    testWidgets('selection takes the scheme it is drawn in', (tester) async {
      Color? chipColor() {
        final chip = tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .first;
        return (chip.decoration! as ShapeDecoration).color;
      }

      for (final (brightness, style) in [
        (Brightness.light, AppGlassStyle.light),
        (Brightness.dark, AppGlassStyle.dark),
      ]) {
        await tester.pumpWidget(
          _host(
            AppGlassPill(
              destinations: _destinations,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
            brightness: brightness,
          ),
        );
        expect(chipColor(), style.selectedFill);
      }
    });
  });

  group('AppGlassButton and AppGlassGroup', () {
    testWidgets('buttons are the green of a selected tab, the pill is not', (
      tester,
    ) async {
      Color? surfaceColour(Finder within) => tester
          .widgetList<DecoratedBox>(
            find.descendant(of: within, matching: find.byType(DecoratedBox)),
          )
          .map((box) => box.decoration)
          .whereType<ShapeDecoration>()
          .firstWhere((decoration) => decoration.color != null)
          .color;

      for (final (brightness, style) in [
        (Brightness.light, AppGlassStyle.light),
        (Brightness.dark, AppGlassStyle.dark),
      ]) {
        await tester.pumpWidget(
          _host(
            AppGlassButton(
              action: AppGlassAction(
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: () {},
              ),
            ),
            brightness: brightness,
          ),
        );
        expect(surfaceColour(find.byType(AppGlassButton)), style.selectedFill);

        await tester.pumpWidget(
          _host(
            AppGlassGroup(
              actions: [
                AppGlassAction(icon: Icons.add, label: 'Add', onPressed: () {}),
                AppGlassAction(
                  icon: Icons.arrow_back,
                  label: 'Back',
                  onPressed: () {},
                ),
              ],
            ),
            brightness: brightness,
          ),
        );
        expect(surfaceColour(find.byType(AppGlassGroup)), style.selectedFill);

        await tester.pumpWidget(
          _host(
            AppGlassPill(
              destinations: _destinations,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
            brightness: brightness,
          ),
        );
        expect(surfaceColour(find.byType(AppGlassPill)), style.fill);
      }
    });

    testWidgets('a disabled button is not green, so it reads as disabled', (
      tester,
    ) async {
      Color? surfaceColour(Finder within) => tester
          .widgetList<DecoratedBox>(
            find.descendant(of: within, matching: find.byType(DecoratedBox)),
          )
          .map((box) => box.decoration)
          .whereType<ShapeDecoration>()
          .firstWhere((decoration) => decoration.color != null)
          .color;

      for (final (brightness, style) in [
        (Brightness.light, AppGlassStyle.light),
        (Brightness.dark, AppGlassStyle.dark),
      ]) {
        await tester.pumpWidget(
          _host(
            AppGlassGroup(
              actions: [
                AppGlassAction(icon: Icons.add, label: 'Add', onPressed: () {}),
                const AppGlassAction(
                  icon: Icons.save,
                  label: 'Save',
                  onPressed: null,
                ),
              ],
            ),
            brightness: brightness,
          ),
        );

        expect(
          surfaceColour(find.byType(AppGlassButton).at(0)),
          style.selectedFill,
          reason: 'an enabled button stays green',
        );
        expect(
          surfaceColour(find.byType(AppGlassButton).at(1)),
          style.fill,
          reason:
              'a disabled button takes the plain frosted fill, not the green',
        );
      }
    });

    testWidgets('a button names itself and reports a tap', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          AppGlassButton(
            action: AppGlassAction(
              icon: Icons.arrow_back,
              label: 'Back',
              onPressed: () => pressed++,
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(pressed, 1);
      expect(
        tester.getSize(find.byType(AppGlassButton)),
        const Size.square(kGlassHorizontalThickness),
      );
    });

    testWidgets(
      'a text button shows its label a word to a line, at the same size',
      (tester) async {
        var pressed = 0;
        await tester.pumpWidget(
          _host(
            AppGlassButton(
              action: AppGlassAction.text(
                label: 'Exit God Mode',
                onPressed: () => pressed++,
              ),
            ),
          ),
        );
        expect(find.bySemanticsLabel('Exit God Mode'), findsOneWidget);
        await tester.tap(find.text('Exit\nGod\nMode'));
        expect(pressed, 1);
        expect(
          tester.getSize(find.byType(AppGlassButton)),
          const Size.square(kGlassHorizontalThickness),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a group routes each tap to its own action', (tester) async {
      final pressed = <String>[];
      AppGlassAction action(IconData icon, String label) => AppGlassAction(
        icon: icon,
        label: label,
        onPressed: () => pressed.add(label),
      );
      await tester.pumpWidget(
        _host(
          AppGlassGroup(
            actions: [
              action(Icons.add, 'Add'),
              action(Icons.arrow_back, 'Back'),
            ],
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(pressed, ['Add', 'Back']);
      expect(
        tester.getSize(find.byType(AppGlassGroup)).height,
        kGlassHorizontalThickness,
      );
    });

    testWidgets('a group is separate buttons with the backdrop between', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppGlassGroup(
            axis: Axis.vertical,
            actions: [
              AppGlassAction(icon: Icons.add, label: 'Add', onPressed: () {}),
              AppGlassAction(
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      final buttons = find.byType(AppGlassButton);
      expect(buttons, findsNWidgets(2));
      final upper = tester.getRect(buttons.at(0));
      final lower = tester.getRect(buttons.at(1));
      expect(lower.top - upper.bottom, kGlassButtonGap);
      expect(upper.width, kGlassSideThickness);
    });

    testWidgets('a vertical group is as thick as the side pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppGlassGroup(
            axis: Axis.vertical,
            actions: [
              AppGlassAction(icon: Icons.add, label: 'Add', onPressed: () {}),
              AppGlassAction(
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(AppGlassGroup)).width,
        kGlassSideThickness,
      );
    });
  });
}
