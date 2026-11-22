import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The blurred grass backdrop behind every screen.
///
/// It keeps its own proportions and fills the space by zooming and cropping, so
/// it is never stretched. The picture is tall and narrow, so a wide display such
/// as a browser window shows a band of it.
///
/// Where it has to crop, the part shown is picked at random. A new part is
/// picked at launch and again whenever the screen's proportions change by a
/// good amount, such as turning the phone or folding a Duo, so each shape of
/// screen gets its own view. A small change, such as dragging a browser window
/// a little, or the keyboard opening, keeps the same crop and does not jump.
/// Every screen draws the same crop, so moving between them does not either.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  static const String asset = 'assets/grass_background_blurred.webp';

  /// How much the screen's width over height must change, as a fraction of the
  /// aspect the current crop was picked for, before a new crop is picked.
  static const double repickChange = 0.25;

  /// Where randomness comes from. Tests replace it to get a known sequence.
  @visibleForTesting
  static math.Random random = math.Random();

  static double? _pickedAspect;
  static Alignment _viewport = _randomViewport(random);

  /// Which part of the picture shows when it has to be cropped: -1 is the
  /// left or top edge and 1 the right or bottom.
  static Alignment get viewport => _viewport;

  /// Fixes the crop, so a test draws the same picture every time.
  @visibleForTesting
  static set viewport(Alignment value) => _viewport = value;

  /// Forgets the screen shape the crop was picked for, as at a fresh launch.
  @visibleForTesting
  static void reset() => _pickedAspect = null;

  static Alignment _randomViewport(math.Random source) =>
      Alignment(source.nextDouble() * 2 - 1, source.nextDouble() * 2 - 1);

  @visibleForTesting
  static Alignment randomViewport(math.Random source) =>
      _randomViewport(source);

  /// The crop for a screen of [size], picking a new one if its proportions have
  /// moved far enough from the ones the current crop was picked for.
  static Alignment viewportFor(Size size) {
    if (size.isEmpty) return _viewport;
    final aspect = size.width / size.height;
    final picked = _pickedAspect;
    if (picked == null) {
      _pickedAspect = aspect;
    } else if ((aspect / picked - 1).abs() > repickChange) {
      _pickedAspect = aspect;
      _viewport = _randomViewport(random);
    }
    return _viewport;
  }

  @override
  Widget build(BuildContext context) {
    final viewport = viewportFor(MediaQuery.sizeOf(context));
    return SizedBox.expand(
      // A wide display zooms the small picture a long way, so it is resampled
      // smoothly rather than left to show its pixels.
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: viewport,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
