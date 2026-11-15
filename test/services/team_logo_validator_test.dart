import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daufootytipping/services/team_logo_validator.dart';
import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String> rejection(Uint8List bytes) async {
    try {
      await validateTeamLogo(bytes);
    } on TeamLogoRejected catch (error) {
      return error.message;
    }
    fail('expected the logo to be rejected');
  }

  test('accepts a seed logo and returns its trimmed text', () async {
    final text = File('team_logos/afl-Fremantle.svg').readAsStringSync();
    expect(await validateTeamLogo(_bytes('\n$text\n')), text.trim());
  });

  test('rejects empty, non-SVG and non-UTF-8 files', () async {
    expect(await rejection(_bytes('   ')), contains('empty'));
    expect(await rejection(_bytes('<html></html>')), contains('not an SVG'));
    expect(
      await rejection(Uint8List.fromList([0xff, 0xfe, 0x00])),
      contains('not a text SVG'),
    );
  });

  test('rejects a logo over the database size limit', () async {
    final padding = ' ' * maxTeamLogoSvgLength;
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">'
        '<desc>$padding</desc></svg>';
    expect(await rejection(_bytes(svg)), contains('limit'));
  });

  test('rejects an SVG that cannot be drawn', () async {
    expect(
      await rejection(_bytes('<svg xmlns="http://www.w3.org/2000/svg"><g>')),
      contains('could not be drawn'),
    );
  });
}
