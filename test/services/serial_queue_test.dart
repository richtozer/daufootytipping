import 'dart:async';

import 'package:daufootytipping/services/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs actions one at a time, in the order asked for', () async {
    final queue = SerialQueue();
    final events = <String>[];
    final firstDone = Completer<void>();

    final first = queue.run(() async {
      events.add('first starts');
      await firstDone.future;
      events.add('first ends');
    });
    final second = queue.run(() async => events.add('second runs'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events, ['first starts'], reason: 'second waits for first');

    firstDone.complete();
    await Future.wait([first, second]);

    expect(events, ['first starts', 'first ends', 'second runs']);
  });

  test('gives each caller its own result', () async {
    final queue = SerialQueue();

    final results = await Future.wait([
      queue.run(() async => 1),
      queue.run(() async => 'two'),
    ]);

    expect(results, [1, 'two']);
  });

  test('a failure goes to its own caller and does not stop the next', () async {
    final queue = SerialQueue();

    final failing = queue.run<void>(() async => throw StateError('boom'));
    final next = queue.run(() async => 'still runs');

    await expectLater(failing, throwsStateError);
    expect(await next, 'still runs');
  });
}
