import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pushed pages leave Back and actions to the floating controls', () {
    // The host draws Back, and any actions a page declares, for every pushed
    // page, so a page that adds its own floating button or app bar shows two.
    final offenders =
        [
              'lib/pages/user_home',
              'lib/pages/admin_daucomps',
              'lib/pages/admin_teams',
              'lib/pages/admin_tippers',
            ]
            .expand((path) => Directory(path).listSync(recursive: true))
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .where((file) {
              final source = file.readAsStringSync();
              return source.contains('FloatingActionButton') ||
                  (source.contains('AppBar(') &&
                      !file.path.endsWith('user_home_resume_diagnostics.dart'));
            })
            .map((file) => file.path)
            .toList();

    expect(offenders, isEmpty);
  });
}
