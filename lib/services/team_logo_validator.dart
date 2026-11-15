import 'dart:convert';
import 'dart:typed_data';

import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Checks an uploaded team logo before it is written to `/TeamLogos`.
///
/// Returns the SVG text when the file is valid UTF-8, is an SVG document, fits
/// under the database rules' size limit and can be drawn by `flutter_svg`.
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
  try {
    final PictureInfo picture = await vg.loadPicture(
      SvgStringLoader(svg),
      null,
    );
    final bool hasSize = !picture.size.isEmpty;
    picture.picture.dispose();
    if (!hasSize) {
      throw const TeamLogoRejected('The SVG has no size or viewBox.');
    }
  } on TeamLogoRejected {
    rethrow;
  } on Object {
    throw const TeamLogoRejected('The SVG could not be drawn.');
  }
  return svg;
}

/// Why an uploaded logo was refused, worded for the admin.
class TeamLogoRejected implements Exception {
  /// Creates the rejection with [message].
  const TeamLogoRejected(this.message);

  /// What is wrong with the file.
  final String message;

  @override
  String toString() => message;
}
