import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The public tipper list, the teams and the competitions need a session under
/// the R2 rules, and a listener attached before one exists is cancelled for good
/// (DESIGN-database-rules-phase4.md, D10). The three that the app opens at start-up,
/// before anyone has signed in, must therefore go through `authAwareStream`. The
/// stream itself is tested in `auth_aware_stream_test.dart`; this keeps the three
/// call sites from quietly reverting to a bare database listener.
void main() {
  String source(String path) => File(path).readAsStringSync();

  final guarded = <String, String>{
    'lib/view_models/tippers_viewmodel.dart': 'p.tippersPath',
    'lib/view_models/teams_viewmodel.dart': 'p.teamsPathRoot',
    'lib/repositories/daucomps_repository.dart': 'daucompsPath',
  };

  for (final entry in guarded.entries) {
    test('${entry.key} opens its listener through authAwareStream', () {
      final text = source(entry.key);
      expect(text, contains('authAwareStream<DatabaseEvent>('));
      // The tipper list takes the sign-in stream as a seam (for tests) that
      // defaults to Firebase's; the others use Firebase's directly.
      expect(
        text,
        anyOf(
          contains('signedIn: firebaseSignedInStream'),
          allOf(
            contains('signedIn: _signedIn'),
            contains('?? firebaseSignedInStream'),
          ),
        ),
      );
      // No bare listener on the guarded path.
      final bare = RegExp(
        r"child\(\s*" +
            RegExp.escape(entry.value) +
            r"\s*\)\s*\.onValue\s*\.listen",
      );
      expect(
        bare.hasMatch(text),
        false,
        reason: 'a bare ${entry.value} listener',
      );
    });
  }

  test('the administrators\' private records listener also goes through authAwareStream', () {
    final text = source('lib/view_models/tippers_viewmodel.dart');
    final bare = RegExp(
      r"child\(\s*p\.tipperPrivatePath\s*\)\s*\.onValue\s*\.listen",
    );
    expect(text, contains('p.tipperPrivatePath'));
    expect(bare.hasMatch(text), isFalse);
    expect(
      RegExp(
        r"authAwareStream<DatabaseEvent>\([^;]*?tipperPrivatePath",
        dotAll: true,
      ).hasMatch(text),
      isTrue,
    );
  });
}
