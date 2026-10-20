import 'dart:async';

import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Duration limit = Duration(milliseconds: 40);

  group('awaitAcknowledgement', () {
    test('is confirmed when the write completes within the limit', () async {
      final Future<void> write = Future<void>.delayed(
        const Duration(milliseconds: 5),
      );

      expect(
        await awaitAcknowledgement(write, limit: limit),
        WriteAcknowledgement.confirmed,
      );
    });

    test(
      'is still pending when the write has not completed by the limit',
      () async {
        final Completer<void> write = Completer<void>();

        expect(
          await awaitAcknowledgement(write.future, limit: limit),
          WriteAcknowledgement.stillPending,
        );
        write.complete();
      },
    );

    test('rethrows a rejection that arrives within the limit', () async {
      final Future<void> write = Future<void>.delayed(
        const Duration(milliseconds: 5),
        () => throw StateError('permission denied'),
      );

      await expectLater(
        awaitAcknowledgement(write, limit: limit),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'reports a rejection that arrives after the limit to onLateError',
      () async {
        final Completer<void> write = Completer<void>();
        final List<Object> lateErrors = <Object>[];

        final WriteAcknowledgement outcome = await awaitAcknowledgement(
          write.future,
          limit: limit,
          onLateError: (Object error, StackTrace stackTrace) {
            lateErrors.add(error);
          },
        );
        expect(outcome, WriteAcknowledgement.stillPending);
        expect(lateErrors, isEmpty);

        write.completeError(StateError('rejected after the limit'));
        await Future<void>.delayed(Duration.zero);

        expect(lateErrors.single, isA<StateError>());
      },
    );

    test('a write that succeeds after the limit causes no error', () async {
      final Completer<void> write = Completer<void>();
      final List<Object> lateErrors = <Object>[];

      await awaitAcknowledgement(
        write.future,
        limit: limit,
        onLateError: (Object error, StackTrace stackTrace) {
          lateErrors.add(error);
        },
      );
      write.complete();
      await Future<void>.delayed(Duration.zero);

      expect(lateErrors, isEmpty);
    });

    test(
      'a late rejection without a listener is not an unhandled error',
      () async {
        final Completer<void> write = Completer<void>();

        await awaitAcknowledgement(write.future, limit: limit);
        write.completeError(StateError('rejected after the limit'));

        // The test fails if the error escapes to the zone as unhandled.
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
    );
  });

  group('WriteNotConfirmedException', () {
    test('names what was being written and never the data', () {
      const WriteNotConfirmedException exception = WriteNotConfirmedException(
        'tip submission',
      );

      expect(exception.toString(), contains('tip submission'));
      expect(exception, isA<Exception>());
    });
  });
}
