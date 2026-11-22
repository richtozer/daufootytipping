import 'package:dart_functions/identity/handler_deadline.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:test/test.dart';

import '../support/identity_helpers.dart';

void main() {
  group('HandlerDeadline', () {
    test('lets a handler carry on until its time is up', () async {
      var now = 1000;
      final deadline = HandlerDeadline(
        limit: const Duration(seconds: 50),
        nowMs: () => now,
      );
      await deadline.check('first');
      now += 49999;
      await deadline.check('almost');
      expect(deadline.expired, isFalse);
    });

    test('stops it at the next step once the time is up', () async {
      var now = 1000;
      final deadline = HandlerDeadline(
        limit: const Duration(seconds: 50),
        nowMs: () => now,
      );
      now += 50000;
      expect(deadline.expired, isTrue);
      await expectLater(deadline.check('next'), refusedAs('unavailable'));
    });

    test('is shorter than the callable timeout the drain assumes', () {
      expect(handlerSoftDeadline, lessThan(mutatingCallableTimeout));
    });
  });
}
