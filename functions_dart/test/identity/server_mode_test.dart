import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:test/test.dart';

/// The reason carried in an error's `details`, as the client will see it.
String? _reasonOf(Object error) {
  final details = (error as dynamic).details as List<Map<String, Object?>>?;
  return details?.single['reason'] as String?;
}

void main() {
  group('reading the stored mode', () {
    test('only an exact known mode is believed; everything else is off', () {
      for (final bad in [
        null,
        '',
        'OFF',
        'Coexist',
        'on',
        'final ',
        7,
        true,
        {},
      ]) {
        expect(
          ServerModeConfig.parse(mode: bad).mode,
          IdentityMode.off,
          reason: '$bad',
        );
      }
      expect(ServerModeConfig.parse(mode: 'off').mode, IdentityMode.off);
      expect(ServerModeConfig.parse(mode: 'pilot').mode, IdentityMode.pilot);
      expect(
        ServerModeConfig.parse(mode: 'coexist').mode,
        IdentityMode.coexist,
      );
      expect(ServerModeConfig.parse(mode: 'freeze').mode, IdentityMode.freeze);
      expect(
        ServerModeConfig.parse(mode: 'final').mode,
        IdentityMode.finalShape,
      );
    });

    test(
      'pilot uids come from a list or a map and ignore anything that is not a uid',
      () {
        expect(
          ServerModeConfig.parse(
            mode: 'pilot',
            pilotUids: ['a', 'b', '', 3, null],
          ).pilotUids,
          {'a', 'b'},
        );
        expect(
          ServerModeConfig.parse(
            mode: 'pilot',
            pilotUids: {'0': 'a', '1': 'b'},
          ).pilotUids,
          {'a', 'b'},
        );
        expect(
          ServerModeConfig.parse(mode: 'pilot', pilotUids: 'a').pilotUids,
          isEmpty,
        );
      },
    );

    test(
      'which modes write the legacy public shape and which need a drain',
      () {
        expect(IdentityMode.pilot.writesLegacyPublicShape, true);
        expect(IdentityMode.coexist.writesLegacyPublicShape, true);
        expect(IdentityMode.finalShape.writesLegacyPublicShape, false);
        expect(IdentityMode.off.writesLegacyPublicShape, false);
        expect(
          [
            for (final mode in IdentityMode.values)
              if (mode.needsDrain) mode,
          ],
          [IdentityMode.off, IdentityMode.freeze, IdentityMode.finalShape],
        );
      },
    );

    test(
      'the stored strings are the contract with the owner tool and the plan',
      () {
        expect(
          [for (final mode in IdentityMode.values) mode.wire],
          ['off', 'pilot', 'coexist', 'freeze', 'final'],
        );
        expect(identityModePath, '/ServerConfig/identity');
        expect(inflightPath, '/ServerConfig/identity/inflight');
      },
    );
  });

  group('admission by mode', () {
    const pilot = ServerModeConfig(
      mode: IdentityMode.pilot,
      pilotUids: {'tester'},
    );

    test('off refuses everyone, as not available', () {
      expect(
        () => checkAdmission(
          const ServerModeConfig(mode: IdentityMode.off),
          'anyone',
        ),
        throwsA(
          isA<FailedPreconditionError>().having(
            _reasonOf,
            'reason',
            identityReasonNotAvailable,
          ),
        ),
      );
    });

    test('pilot admits only the pilot users', () {
      checkAdmission(pilot, 'tester');
      expect(
        () => checkAdmission(pilot, 'someone-else'),
        throwsA(
          isA<FailedPreconditionError>().having(
            _reasonOf,
            'reason',
            identityReasonNotAvailable,
          ),
        ),
      );
    });

    test('pilot with nobody listed admits nobody', () {
      expect(
        () => checkAdmission(
          const ServerModeConfig(mode: IdentityMode.pilot),
          'tester',
        ),
        throwsA(isA<FailedPreconditionError>()),
      );
    });

    test('coexist and final admit everyone', () {
      checkAdmission(
        const ServerModeConfig(mode: IdentityMode.coexist),
        'anyone',
      );
      checkAdmission(
        const ServerModeConfig(mode: IdentityMode.finalShape),
        'anyone',
      );
    });

    test('freeze refuses with try-again-shortly', () {
      expect(
        () => checkAdmission(
          const ServerModeConfig(mode: IdentityMode.freeze),
          'anyone',
        ),
        throwsA(
          isA<UnavailableError>().having(
            _reasonOf,
            'reason',
            identityReasonUnavailable,
          ),
        ),
      );
    });

    test('a refusal reaches the client as a structured ErrorInfo detail', () {
      try {
        checkAdmission(const ServerModeConfig.off(), 'anyone');
        fail('expected a refusal');
      } on FailedPreconditionError catch (error) {
        expect(error.statusCode, 400);
        expect(error.status, 'FAILED_PRECONDITION');
        expect(
          error.toJson()['error'],
          containsPair('details', [
            {
              '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
              'reason': 'not_available',
              'domain': identityErrorDomain,
            },
          ]),
        );
      }
    });
  });

  test('the timing constants agree: hard timeout, margin and stale age', () {
    expect(mutatingCallableTimeout + staleMarkerMargin, staleMarkerAfter);
    expect(staleMarkerAfter, const Duration(seconds: 90));
  });
}
