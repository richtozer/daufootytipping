import 'dart:ui' as ui;

import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:flutter/material.dart';

/// A frosted pane that blurs whatever scrolls beneath it, shaped by [shape].
///
/// The one place the glass look is drawn, so the tab pill, the back button and
/// grouped actions cannot drift apart.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({super.key, required this.shape, required this.child});

  /// The outline. Its border side is replaced with the glass edge.
  final OutlinedBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = AppGlassStyle.of(context);
    final outline = shape.copyWith(side: BorderSide(color: style.border));
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: outline,
        shadows: [
          BoxShadow(
            color: style.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: outline),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: kGlassBlurSigma,
            sigmaY: kGlassBlurSigma,
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(color: style.fill, shape: outline),
            child: child,
          ),
        ),
      ),
    );
  }
}
