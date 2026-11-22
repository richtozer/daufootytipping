import 'dart:ui' as ui;

import 'package:daufootytipping/widgets/app_nav/app_glass_pill.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_destination.dart';
import 'package:daufootytipping/widgets/app_panel_card.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The navigation pill and a panel card are the same tint over the same
/// backdrop: they used to differ, the pill by a grey shadow drawn under its
/// see-through fill and by the surface tint only the cards carried.
void main() {
  for (final (brightness, backdrop) in [
    (Brightness.light, const Color(0xFFB9C998)),
    (Brightness.dark, const Color(0xFF1E2A1A)),
  ]) {
    testWidgets('the pill matches a card over one backdrop, $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.dark
              ? FlexThemeData.dark(scheme: FlexScheme.green)
              : FlexThemeData.light(scheme: FlexScheme.green),
          home: MediaQuery(
            data: MediaQueryData(platformBrightness: brightness),
            child: RepaintBoundary(
              key: const Key('picture'),
              child: Container(
                color: backdrop,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    const SizedBox(
                      width: 140,
                      height: 120,
                      child: AppPanelCard(child: SizedBox.expand()),
                    ),
                    AppGlassPill(
                      selectedIndex: 0,
                      onSelected: (_) {},
                      destinations: const [
                        AppNavDestination(
                          icon: Icon(Icons.sports_rugby),
                          shortLabel: 'TIPS',
                        ),
                        AppNavDestination(
                          icon: Icon(Icons.auto_graph),
                          shortLabel: 'STATS',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = tester.getRect(find.byType(AppPanelCard));
      final pill = tester.getRect(find.byType(AppGlassPill));
      late Color cardColour;
      late Color pillColour;
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('picture')),
        );
        final image = await boundary.toImage();
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        Color at(Offset point) {
          final index = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
          return Color.fromARGB(
            255,
            data.getUint8(index),
            data.getUint8(index + 1),
            data.getUint8(index + 2),
          );
        }

        cardColour = at(card.center);
        // Just inside the pill's top edge, clear of the tab chip and labels.
        pillColour = at(Offset(pill.center.dx, pill.top + 8));
      });

      int channel(double value) => (value * 255).round();
      expect(
        (channel(pillColour.r) - channel(cardColour.r)).abs(),
        lessThanOrEqualTo(3),
      );
      expect(
        (channel(pillColour.g) - channel(cardColour.g)).abs(),
        lessThanOrEqualTo(3),
      );
      expect(
        (channel(pillColour.b) - channel(cardColour.b)).abs(),
        lessThanOrEqualTo(3),
      );
    });
  }
}
