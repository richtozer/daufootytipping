import 'package:dart_functions/auth_bypass_guard.dart';
import 'package:test/test.dart';

void main() {
  const bypass = '{"skipTokenVerification":true}';

  group('assertNoDebugFeaturesOutsideEmulator', () {
    test('a deployed function with no debug features starts', () {
      assertNoDebugFeaturesOutsideEmulator(<String, String>{
        'K_SERVICE': 'link-or-create-tipper',
      });
      assertNoDebugFeaturesOutsideEmulator(const <String, String>{});
      assertNoDebugFeaturesOutsideEmulator(<String, String>{
        'FIREBASE_DEBUG_FEATURES': '  ',
      });
    });

    test('the switch outside the emulator is refused', () {
      expect(
        () => assertNoDebugFeaturesOutsideEmulator(<String, String>{
          'FIREBASE_DEBUG_FEATURES': bypass,
        }),
        throwsStateError,
      );
    });

    test(
      'any debug feature outside the emulator is refused, not just that one',
      () {
        for (final value in <String>[
          '{"enableCors":true}',
          '{"skipTokenVerification":false}',
          'not json',
          '{}',
        ]) {
          expect(
            () => assertNoDebugFeaturesOutsideEmulator(<String, String>{
              'FIREBASE_DEBUG_FEATURES': value,
            }),
            throwsStateError,
            reason: value,
          );
        }
      },
    );

    test(
      'the switch on a deployed service is refused even if it claims to be the emulator',
      () {
        expect(
          () => assertNoDebugFeaturesOutsideEmulator(<String, String>{
            'FIREBASE_DEBUG_FEATURES': bypass,
            'FUNCTIONS_EMULATOR': 'true',
            'K_SERVICE': 'link-or-create-tipper',
          }),
          throwsStateError,
          reason: 'Cloud Run sets K_SERVICE; the emulator does not',
        );
      },
    );

    test('the switch inside the emulator is allowed', () {
      assertNoDebugFeaturesOutsideEmulator(<String, String>{
        'FIREBASE_DEBUG_FEATURES': bypass,
        'FUNCTIONS_EMULATOR': 'true',
      });
    });

    test('the message names the variable and says what to remove', () {
      expect(
        () => assertNoDebugFeaturesOutsideEmulator(<String, String>{
          'FIREBASE_DEBUG_FEATURES': bypass,
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('FIREBASE_DEBUG_FEATURES'), contains('Remove')),
          ),
        ),
      );
    });
  });
}
