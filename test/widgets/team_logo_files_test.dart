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

  test('there is one logo for every AFL and NRL team key', () {
    final names = logoFiles.map((file) => file.uri.pathSegments.last).toList();
    expect(names, isNotEmpty);
    for (final name in names) {
      expect(name, matches(RegExp(r'^(afl|nrl)-[^/]+\.svg$')));
    }
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
