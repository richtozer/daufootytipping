import 'dart:convert';
import 'dart:io';

import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seed logos in `team_logos/` are what `scripts/seed_team_logos.mjs`
/// uploads to `/TeamLogos`, one file per team named by its database key.
void main() {
  final List<File> logoFiles =
      Directory('team_logos')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.svg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final Set<String> logoTeamKeys = {
    for (final file in logoFiles)
      file.uri.pathSegments.last.replaceFirst(RegExp(r'\.svg$'), ''),
  };

  test('every logo file is named by an AFL or NRL team key', () {
    expect(logoTeamKeys, isNotEmpty);
    for (final teamKey in logoTeamKeys) {
      expect(teamKey, matches(RegExp(r'^(afl|nrl)-.+$')));
    }
  });

  test('every team in the 2022-2026 fixtures has a logo file', () {
    Iterable<String> teamKeysIn(String path) {
      final data = jsonDecode(File(path).readAsStringSync()) as Map;
      return (data['teams'] as Map).keys.cast<String>();
    }

    final Set<String> fixtureTeamKeys = {
      ...teamKeysIn('demo/history.json'),
      ...teamKeysIn('demo/fixtures-2026.json'),
    };
    expect(fixtureTeamKeys, hasLength(greaterThanOrEqualTo(35)));
    expect(fixtureTeamKeys.difference(logoTeamKeys), isEmpty);
  });

  test('every logo fits under the database rules size limit', () {
    for (final file in logoFiles) {
      final svg = file.readAsStringSync();
      expect(
        svg.length,
        lessThanOrEqualTo(maxTeamLogoSvgLength),
        reason: file.path,
      );
      expect(svg.trimLeft(), startsWith('<svg'), reason: file.path);
    }
  });

  testWidgets('every logo renders without unsupported element logs', (
    tester,
  ) async {
    final debugMessages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        debugMessages.add(message);
      }
    };

    try {
      for (final file in logoFiles) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SvgPicture.string(
                file.readAsStringSync(),
                width: 24,
                height: 24,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(
      debugMessages.where((message) => message.contains('unhandled element')),
      isEmpty,
    );
  });
}
