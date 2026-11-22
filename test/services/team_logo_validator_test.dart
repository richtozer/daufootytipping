import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daufootytipping/services/team_logo_validator.dart';
import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

String _svg(String body) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">$body</svg>';

void main() {
  Future<String> rejection(Uint8List bytes) async {
    try {
      await validateTeamLogo(bytes);
    } on TeamLogoRejected catch (error) {
      return error.message;
    }
    fail('expected the logo to be rejected');
  }

  test('accepts every seed logo and returns its trimmed text', () async {
    final files = Directory('team_logos')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.svg'));
    expect(files, isNotEmpty);
    for (final file in files) {
      final text = file.readAsStringSync();
      expect(
        await validateTeamLogo(_bytes('\n$text\n')),
        text.trim(),
        reason: file.path,
      );
    }
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
    expect(
      await rejection(_bytes(_svg('<desc>$padding</desc>'))),
      contains('limit'),
    );
  });

  test('rejects an SVG that draws nothing', () async {
    expect(await rejection(_bytes(_svg(''))), contains('does not draw'));
    expect(
      await rejection(_bytes(_svg('<g><desc>empty group</desc></g>'))),
      contains('does not draw'),
    );
  });

  test('rejects an element the renderer would silently skip', () async {
    const body =
        '<rect width="10" height="10" fill="red"/>'
        '<foreignObject width="10" height="10"/>';
    expect(await rejection(_bytes(_svg(body))), contains('cannot draw'));
  });

  test('rejects text and embedded bitmaps', () async {
    expect(
      await rejection(_bytes(_svg('<text x="1" y="9">BRI</text>'))),
      contains('text'),
    );
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
    expect(
      await rejection(
        _bytes(
          _svg(
            '<image width="10" height="10" '
            'href="data:image/png;base64,$png"/>',
          ),
        ),
      ),
      contains('bitmap'),
    );
  });

  test('rejects an SVG with no size', () async {
    expect(
      await rejection(
        _bytes(
          '<svg xmlns="http://www.w3.org/2000/svg">'
          '<rect width="10" height="10"/></svg>',
        ),
      ),
      anyOf(contains('no size'), contains('cannot draw')),
    );
  });

  test('strips title, desc and metadata, which design tools add', () async {
    const rect = '<rect width="10" height="10" fill="#123456"/>';
    final svg = _svg(
      '<title>Broncos</title><desc lang="en">jumper</desc>'
      '<metadata><rdf/></metadata><desc/>$rect',
    );
    expect(await validateTeamLogo(_bytes(svg)), _svg(rect));
  });

  test('accepts a minimal valid logo', () async {
    final svg = _svg('<rect width="10" height="10" fill="#123456"/>');
    expect(await validateTeamLogo(_bytes(svg)), svg);
  });
}
