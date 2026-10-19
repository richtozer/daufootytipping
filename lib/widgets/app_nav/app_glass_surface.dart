import 'dart:ui' as ui;

import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:flutter/material.dart';

/// A frosted pane that blurs whatever scrolls beneath it, shaped by [shape].
///
/// The one place the glass look is drawn, so the tab pill, the back button and
/// grouped actions cannot drift apart.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.shape,
    required this.child,
    this.selectedFill = false,
  });

  /// The outline.
  final OutlinedBorder shape;
  final Widget child;

  /// Draws it in the green of a selected tab, as Back and the page actions are,
  /// instead of the plain frosted fill of the tab pill.
  final bool selectedFill;

  @override
  Widget build(BuildContext context) {
    final style = AppGlassStyle.of(context);
    // The shadow is drawn only outside the shape. Under a see-through fill it
    // shows through and greys the glass, so a card and this surface of the same
    // colour came out as two different tints.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipPath(
            clipper: _OutsideShapeClipper(shape),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape,
                shadows: [
                  BoxShadow(
                    color: style.shadow,
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
        ),
        ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: kGlassBlurSigma,
              sigmaY: kGlassBlurSigma,
            ),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: selectedFill ? style.selectedFill : style.fill,
                shape: shape,
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

/// Everything around a shape and nothing inside it, with room for a shadow's
/// blur and offset.
class _OutsideShapeClipper extends CustomClipper<Path> {
  const _OutsideShapeClipper(this.shape);

  final OutlinedBorder shape;

  static const double _room = 80;

  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.difference,
    Path()..addRect(
      Rect.fromLTWH(
        -_room,
        -_room,
        size.width + 2 * _room,
        size.height + 2 * _room,
      ),
    ),
    shape.getOuterPath(Offset.zero & size),
  );

  @override
  bool shouldReclip(_OutsideShapeClipper oldClipper) =>
      oldClipper.shape != shape;
}
