import 'dart:async';

import 'package:dau_shared/constants/identity_reasons.dart' as reasons;
import 'package:dau_shared/dau_shared.dart'
    show RegisterDeviceTokenResult, UnregisterDeviceTokenResult;
import 'package:daufootytipping/services/device_token_registrar.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockIdentityService extends Mock implements IdentityService {}

void main() {
  late _MockIdentityService identity;
  late List<Duration> waits;
  late DeviceTokenRegistrar registrar;

  IdentityFailure transient() =>
      IdentityFailure.network(Exception('no connection'));

  IdentityFailure refused(String reason) => IdentityFailure(
    kind: IdentityFailureKind.refused,
    code: 'failed-precondition',
    message: 'server words',
    reason: reason,
  );

  const registered = RegisterDeviceTokenResult(tipperId: 'tipper-1');
  const removed = UnregisterDeviceTokenResult(removed: true);

  setUp(() {
    identity = _MockIdentityService();
    waits = <Duration>[];
    registrar = DeviceTokenRegistrar(
      identity: identity,
      retryDelays: const [Duration(seconds: 5), Duration(seconds: 30)],
      wait: (delay) async => waits.add(delay),
    );
  });

  group('registering a token', () {
    test('asks the server once and says it worked', () async {
      when(() => identity.registerDeviceToken('token-1'))
          .thenAnswer((_) async => registered);

      expect(await registrar.register('token-1'), isTrue);

      verify(() => identity.registerDeviceToken('token-1')).called(1);
      expect(waits, isEmpty);
    });

    test(
      'tries again after each delay when the server cannot be reached',
      () async {
        var calls = 0;
        when(() => identity.registerDeviceToken('token-1'))
            .thenAnswer((_) async {
              calls++;
              if (calls < 3) {
                throw transient();
              }
              return registered;
            });

        expect(await registrar.register('token-1'), isTrue);

        expect(calls, 3);
        expect(waits, [
          const Duration(seconds: 5),
          const Duration(seconds: 30),
        ]);
      },
    );

    test('gives up when the delays run out, without throwing', () async {
      when(() => identity.registerDeviceToken('token-1'))
          .thenAnswer((_) async => throw transient());

      expect(await registrar.register('token-1'), isFalse);

      verify(() => identity.registerDeviceToken('token-1')).called(3);
    });

    test('does not retry a refusal', () async {
      when(
        () => identity.registerDeviceToken('token-1'),
      ).thenAnswer((_) async => throw refused(reasons.identityReasonNotLinked));

      expect(await registrar.register('token-1'), isFalse);

      verify(() => identity.registerDeviceToken('token-1')).called(1);
      expect(waits, isEmpty);
    });
  });

  group('removing a token', () {
    test('asks the server', () async {
      when(() => identity.unregisterDeviceToken('token-1'))
          .thenAnswer((_) async => removed);

      await registrar.unregister('token-1');

      verify(() => identity.unregisterDeviceToken('token-1')).called(1);
    });

    test('passes a failure on, so deletion can stop', () async {
      when(() => identity.unregisterDeviceToken('token-1'))
          .thenAnswer((_) async => throw transient());

      await expectLater(
        registrar.unregister('token-1'),
        throwsA(isA<IdentityFailure>()),
      );
    });
  });

  group('calls for a token go to the server in the order asked', () {
    test('a removal asked for during a registration waits for it', () async {
      final registering = Completer<RegisterDeviceTokenResult>();
      final events = <String>[];
      when(() => identity.registerDeviceToken('token-1')).thenAnswer((_) {
        events.add('register starts');
        return registering.future;
      });
      when(() => identity.unregisterDeviceToken('token-1'))
          .thenAnswer((_) async {
            events.add('unregister runs');
            return removed;
          });

      final register = registrar.register('token-1');
      final unregister = registrar.unregister('token-1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events, ['register starts']);

      registering.complete(registered);
      await Future.wait([register, unregister]);

      expect(events, ['register starts', 'unregister runs']);
    });

    test('a wait before a retry does not hold up a removal', () async {
      final waiting = Completer<void>();
      final slowRegistrar = DeviceTokenRegistrar(
        identity: identity,
        retryDelays: const [Duration(seconds: 5)],
        wait: (_) => waiting.future,
      );
      when(() => identity.registerDeviceToken('token-1'))
          .thenAnswer((_) async => throw transient());
      when(() => identity.unregisterDeviceToken('token-1'))
          .thenAnswer((_) async => removed);

      final register = slowRegistrar.register('token-1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await slowRegistrar.unregister('token-1');

      verify(() => identity.unregisterDeviceToken('token-1')).called(1);
      waiting.complete();
      await register;
    });
  });
}
