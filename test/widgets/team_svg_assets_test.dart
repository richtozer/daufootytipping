import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/svg.dart';

void main() {
  testWidgets('team SVG assets render without unsupported element logs', (
    tester,
  ) async {
    final assetPaths = Directory('assets/teams')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('.svg'))
        .toList()
      ..sort();
    final debugMessages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        debugMessages.add(message);
      }
    };

    expect(assetPaths, isNotEmpty);

    try {
      for (final assetPath in assetPaths) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SvgPicture.asset(assetPath, width: 24, height: 24),
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
