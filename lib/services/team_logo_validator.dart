import 'dart:convert';
import 'dart:typed_data';

import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

/// Checks an uploaded team logo before it is written to `/TeamLogos`.
///
/// Returns the SVG text to store, without `<title>`, `<desc>` or `<metadata>`,
/// when the file is valid UTF-8 and an SVG document under
/// the database rules' size limit that the app's renderer draws completely:
/// it is parsed the way `flutter_svg` parses it, but with warnings treated as
/// errors, so an element the renderer would silently skip refuses the file
/// rather than leaving part of the logo missing. A logo must also draw
/// something, and may not rely on fonts (text) or embedded bitmaps.
///
/// Throws a [TeamLogoRejected] with a message for the admin otherwise.
Future<String> validateTeamLogo(Uint8List bytes) async {
  final String svg;
  try {
    svg = utf8.decode(bytes).trim();
  } on FormatException {
    throw const TeamLogoRejected('The file is not a text SVG.');
  }
  if (svg.isEmpty) {
    throw const TeamLogoRejected('The file is empty.');
  }
  if (svg.length > maxTeamLogoSvgLength) {
    throw TeamLogoRejected(
      'The logo is ${svg.length ~/ 1024} KB; the limit is '
      '${maxTeamLogoSvgLength ~/ 1024} KB. Run it through '
      '`npm run optimise:logos` first.',
    );
  }
  if (!svg.contains('<svg')) {
    throw const TeamLogoRejected('The file is not an SVG.');
  }

  final String drawable = svg.replaceAll(_nonDrawingElements, '').trim();
  final VectorInstructions drawing;
  try {
    // The optimisers are off, as in flutter_svg: they need a native library
    // the app does not ship, and they do not change what is drawn.
    drawing = parse(
      drawable,
      warningsAsErrors: true,
      enableMaskingOptimizer: false,
      enableClippingOptimizer: false,
      enableOverdrawOptimizer: false,
    );
  } on Error catch (error) {
    throw TeamLogoRejected(
      'The SVG uses something the app cannot draw ($error). '
      'Save it as a plain SVG with paths and flat colours.',
    );
  } on Exception {
    throw const TeamLogoRejected('The SVG could not be read.');
  }
  if (drawing.width <= 0 || drawing.height <= 0) {
    throw const TeamLogoRejected('The SVG has no size or viewBox.');
  }
  if (drawing.text.isNotEmpty) {
    throw const TeamLogoRejected(
      'The SVG contains text. Convert the text to outlines first.',
    );
  }
  if (drawing.images.isNotEmpty) {
    throw const TeamLogoRejected(
      'The SVG contains an embedded bitmap. Use a vector logo.',
    );
  }
  if (drawing.commands.isEmpty) {
    throw const TeamLogoRejected('The SVG does not draw anything.');
  }
  return drawable;
}

/// Elements that describe a drawing without drawing anything. Design tools add
/// them, and the strict parse refuses them, so they are removed before saving.
final RegExp _nonDrawingElements = RegExp(
  r'<(title|desc|metadata)\b[^>]*/>|<(title|desc|metadata)\b[^>]*>.*?</\2>',
  dotAll: true,
);

/// Why an uploaded logo was refused, worded for the admin.
class TeamLogoRejected implements Exception {
  /// Creates the rejection with [message].
  const TeamLogoRejected(this.message);

  /// What is wrong with the file.
  final String message;

  @override
  String toString() => message;
}
