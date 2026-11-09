import 'package:dart_functions/auth_bypass_guard.dart';
import 'package:test/test.dart';

void main() {
  const bypass = '{"skipTokenVerification":true}';

  group('assertNoDebugFeaturesOutsideEmulator', () {
    test('a deployed function with no debug features starts', () {
      assertNoDebugFeaturesOutsideEmulator(<String, String>{
        'K_SERVICE': 'link-or-create-tipper',
        'K_REVISION': 'link-or-create-tipper-00012-abc',
        'K_CONFIGURATION': 'link-or-create-tipper',
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
            'K_REVISION': 'link-or-create-tipper-00012-abc',
            'K_CONFIGURATION': 'link-or-create-tipper',
          }),
          throwsStateError,
          reason: 'Cloud Run sets K_CONFIGURATION; the emulator does not',
        );
      },
    );

    test('the switch inside the emulator is allowed', () {
      assertNoDebugFeaturesOutsideEmulator(<String, String>{
        'FIREBASE_DEBUG_FEATURES': bypass,
        'FUNCTIONS_EMULATOR': 'true',
      });
    });

    test(
      'the switch inside the emulator is allowed as the Firebase CLI really sets it',
      () {
        // Firebase CLI 15: the emulator gives every function a K_SERVICE (its
        // name) and a K_REVISION of "1", but no K_CONFIGURATION. The first
        // version of this guard required K_SERVICE to be absent and so refused
        // to start the worker in the local emulator.
        assertNoDebugFeaturesOutsideEmulator(<String, String>{
          'FIREBASE_DEBUG_FEATURES':
              '{"skipTokenVerification":true,"enableCors":true}',
          'FIREBASE_DEBUG_MODE': 'true',
          'FUNCTIONS_EMULATOR': 'true',
          'K_SERVICE': 'backend-scoring-command',
          'K_REVISION': '1',
        });
      },
    );

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
