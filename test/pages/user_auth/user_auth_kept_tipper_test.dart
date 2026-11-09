import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// On the web Firebase Auth reports no user for a moment at every start-up, before
/// the saved session is restored. The sign-in page used to clear the tipper kept on
/// the device whenever it saw no user, so on the web it was cleared on every load
/// and a reload was never quicker than the first load. It is forgotten only when the
/// user signs out or deletes their account. The page cannot be built without Firebase,
/// so this keeps that from quietly changing back.
void main() {
  final source = File('lib/pages/user_auth/user_auth.dart').readAsStringSync();

  /// The text of the method that starts with [signature], up to its closing brace.
  String body(String signature) {
    final start = source.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: 'no $signature');
    final open = source.indexOf('{', start);
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(open, i + 1);
        }
      }
    }
    fail('unbalanced braces after $signature');
  }

  test('seeing no user does not forget the kept tipper', () {
    expect(body('void _resetAuthFlowFutures()'), isNot(contains('forget')));
  });

  test('signing out forgets it, before the account is signed out', () {
    final signOut = body('Future<void> signOut()');
    expect(signOut, contains('_forgetKeptTipper()'));
    expect(
      signOut.indexOf('_forgetKeptTipper()'),
      lessThan(signOut.indexOf('FirebaseAuth.instance.signOut()')),
    );
  });

  test('deleting the account forgets it', () {
    final exit = body('Future<void> _startExitActionIfNeeded()');
    expect(exit, contains('_forgetKeptTipper()'));
  });

  test('the one place it is forgotten asks the service', () {
    expect(body('Future<void> _forgetKeptTipper()'), contains('.forget()'));
  });
}
