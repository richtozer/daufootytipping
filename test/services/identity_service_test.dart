import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:daufootytipping/services/functions_identity_invoker.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recorded call, and what the fake answers.
class _FakeInvoker implements IdentityCallableInvoker {
  final List<(String, Map<String, Object?>)> calls = [];
  Object? answer;
  Object? failWith;

  @override
  Future<Object?> call(
    String endpoint,
    Map<String, Object?> data, {
    Duration timeout = const Duration(seconds: 65),
  }) async {
    calls.add((endpoint, data));
    if (failWith != null) {
      throw failWith!;
    }
    return answer;
  }
}

/// The plugin's error type, whose constructor is protected.
class _PluginError extends FirebaseFunctionsException {
  _PluginError(String code, String message, [Object? details])
    : super(code: code, message: message, details: details);
}

List<Map<String, Object?>> _info(String reason) => <Map<String, Object?>>[
  <String, Object?>{
    '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
    'reason': reason,
    'domain': identityErrorDomain,
  },
];

/// Checks the one call the fake recorded: the endpoint, and the data by content.
void _expectSingleCall(
  _FakeInvoker invoker,
  String endpoint,
  Map<String, Object?> data,
) {
  expect(invoker.calls, hasLength(1));
  expect(invoker.calls.single.$1, endpoint);
  expect(invoker.calls.single.$2, equals(data));
}

void main() {
  group('IdentityEndpoints', () {
    test('the deployed addresses are the Cloud Run ones', () {
      final endpoints = IdentityEndpoints();
      expect(
        endpoints.urlFor(linkOrCreateTipperEndpoint),
        'https://link-or-create-tipper-rjp4ue2oxa-as.a.run.app',
      );
      expect(
        endpoints.urlFor(unlinkMyAccountEndpoint),
        'https://unlink-my-account-rjp4ue2oxa-as.a.run.app',
      );
      expect(
        endpoints.urlFor(adminMergeTippersEndpoint),
        'https://admin-merge-tippers-rjp4ue2oxa-as.a.run.app',
      );
    });

    test(
      'every identity endpoint gets a distinct address of the same shape',
      () {
        final endpoints = IdentityEndpoints();
        final urls = <String>{
          for (final name in <String>[
            linkOrCreateTipperEndpoint,
            updateTipperAliasEndpoint,
            registerDeviceTokenEndpoint,
            unregisterDeviceTokenEndpoint,
            unlinkMyAccountEndpoint,
            adminUpdateTipperEndpoint,
            adminMergeTippersEndpoint,
          ])
            endpoints.urlFor(name),
        };
        expect(urls, hasLength(7));
        for (final url in urls) {
          expect(url, matches(r'^https://[a-z-]+-rjp4ue2oxa-as\.a\.run\.app$'));
        }
      },
    );

    test('a replacement pattern from configuration is used', () {
      final endpoints = IdentityEndpoints(
        pattern: 'https://example.test/fn/{name}',
      );
      expect(endpoints.urlFor('x'), 'https://example.test/fn/x');
    });

    test('a pattern that is not an address, or has no {name}, is refused', () {
      for (final bad in <String>[
        '',
        'not a url',
        'https://example.test/fixed',
        'ftp://{name}.test',
        '/{name}',
      ]) {
        expect(
          () => IdentityEndpoints(pattern: bad),
          throwsArgumentError,
          reason: bad,
        );
      }
    });
  });

  group('IdentityFailure from a callable error', () {
    IdentityFailure failure(String code, {String? message, Object? details}) =>
        IdentityFailure.fromFunctionsError(
          code: code,
          message: message,
          details: details,
        );

    test('reads the server\'s reason from the ErrorInfo list', () {
      final f = failure(
        'failed-precondition',
        message: 'Not yet',
        details: _info(identityReasonClaimed),
      );
      expect(f.reason, identityReasonClaimed);
      expect(f.kind, IdentityFailureKind.refused);
      expect(f.message, 'Not yet');
      expect(f.isRetryable, false);
    });

    test('busy and unavailable are transient however they are coded', () {
      for (final reason in <String>[
        identityReasonBusy,
        identityReasonUnavailable,
      ]) {
        for (final code in <String>[
          'unavailable',
          'aborted',
          'failed-precondition',
        ]) {
          final f = failure(code, details: _info(reason));
          expect(
            f.kind,
            IdentityFailureKind.transient,
            reason: '$code $reason',
          );
          expect(f.isRetryable, true);
        }
      }
      expect(
        failure('aborted', details: _info(identityReasonBusy)).isBusy,
        true,
      );
    });

    test('switched off is a refusal the caller can tell from the rest', () {
      final f = failure(
        'failed-precondition',
        details: _info(identityReasonNotAvailable),
      );
      expect(f.isNotAvailable, true);
      expect(f.kind, IdentityFailureKind.refused);
      expect(f.isRetryable, false);
    });

    test('each refusal reason is a refusal', () {
      for (final reason in <String>[
        identityReasonUnverifiedEmail,
        identityReasonAmbiguous,
        identityReasonClaimed,
        identityReasonNeedsAudit,
        identityReasonAliasTaken,
        identityReasonInvalidAlias,
        identityReasonCreationDisabled,
        identityReasonNotLinked,
        identityReasonInvalidToken,
        identityReasonNotAdmin,
        identityReasonInvalidEmail,
        identityReasonLastAdmin,
      ]) {
        expect(
          failure('invalid-argument', details: _info(reason)).kind,
          IdentityFailureKind.refused,
          reason: reason,
        );
        expect(
          failure('invalid-argument', details: _info(reason)).reason,
          reason,
        );
      }
    });

    test('codes with no reason', () {
      expect(
        failure('unauthenticated').kind,
        IdentityFailureKind.unauthenticated,
      );
      expect(failure('unavailable').kind, IdentityFailureKind.transient);
      expect(failure('deadline-exceeded').kind, IdentityFailureKind.transient);
      expect(failure('invalid-argument').kind, IdentityFailureKind.refused);
      expect(failure('permission-denied').kind, IdentityFailureKind.refused);
      expect(failure('internal').kind, IdentityFailureKind.unexpected);
      expect(failure('unknown').kind, IdentityFailureKind.unexpected);
    });

    test(
      'details of another domain, or of no sensible shape, give no reason',
      () {
        expect(
          failure(
            'failed-precondition',
            details: <Object?>[
              <String, Object?>{'reason': 'busy', 'domain': 'elsewhere'},
            ],
          ).reason,
          isNull,
        );
        for (final junk in <Object?>[
          null,
          'text',
          3,
          <Object?>[],
          <Object?>['x'],
          <String, Object?>{'reason': 5},
        ]) {
          expect(
            failure('failed-precondition', details: junk).reason,
            isNull,
            reason: '$junk',
          );
        }
      },
    );

    test('a single map of details is read as well as a list', () {
      final f = failure(
        'failed-precondition',
        details: <String, Object?>{
          'reason': identityReasonAmbiguous,
          'domain': identityErrorDomain,
        },
      );
      expect(f.reason, identityReasonAmbiguous);
    });

    test('an empty message falls back to the code', () {
      expect(failure('unavailable', message: '').message, 'unavailable');
      expect(failure('unavailable').message, 'unavailable');
    });

    test('the plugin\'s exception maps the same way', () {
      final f = identityFailureFromFunctionsException(
        _PluginError(
          'failed-precondition',
          'Another change is in progress',
          _info(identityReasonBusy),
        ),
      );
      expect(f.kind, IdentityFailureKind.transient);
      expect(f.isBusy, true);
      expect(f.message, 'Another change is in progress');
    });

    test('a failure before any answer is transient and says so', () {
      final f = IdentityFailure.network(TimeoutException('slow'));
      expect(f.kind, IdentityFailureKind.transient);
      expect(f.code, 'network');
      expect(f.isRetryable, true);
    });
  });

  group('IdentityService', () {
    late _FakeInvoker invoker;
    late IdentityService service;
    setUp(() {
      invoker = _FakeInvoker();
      service = IdentityService(invoker);
    });

    test('linkOrCreateTipper without an alias sends an empty request and reads the result', () async {
      invoker.answer = <String, Object?>{'tipperId': 't1', 'outcome': 'linked'};
      final result = await service.linkOrCreateTipper();
      _expectSingleCall(
        invoker,
        linkOrCreateTipperEndpoint,
        <String, Object?>{},
      );
      expect(result.tipperId, 't1');
      expect(result.outcome, LinkOutcome.linked);
    });

    test('linkOrCreateTipper with an alias sends it', () async {
      invoker.answer = <String, Object?>{
        'tipperId': 't2',
        'outcome': 'created',
      };
      final result = await service.linkOrCreateTipper(alias: 'The Oracle');
      _expectSingleCall(invoker, linkOrCreateTipperEndpoint, <String, Object?>{
        'alias': 'The Oracle',
      });
      expect(result.outcome, LinkOutcome.created);
    });

    test('updateTipperAlias', () async {
      invoker.answer = <String, Object?>{'tipperId': 't1', 'alias': 'New'};
      final result = await service.updateTipperAlias('New');
      _expectSingleCall(invoker, updateTipperAliasEndpoint, <String, Object?>{
        'alias': 'New',
      });
      expect(result.alias, 'New');
    });

    test('registering and unregistering a device token', () async {
      invoker.answer = <String, Object?>{'tipperId': 't1'};
      expect((await service.registerDeviceToken('tok')).tipperId, 't1');
      invoker.answer = <String, Object?>{'removed': true};
      expect((await service.unregisterDeviceToken('tok')).removed, true);
      expect(invoker.calls.map((c) => c.$1), [
        registerDeviceTokenEndpoint,
        unregisterDeviceTokenEndpoint,
      ]);
      expect(
        invoker.calls.every((c) => c.$2.length == 1 && c.$2['token'] == 'tok'),
        true,
      );
    });

    test('unlinkMyAccount', () async {
      invoker.answer = <String, Object?>{'unlinked': true};
      expect((await service.unlinkMyAccount()).unlinked, true);
      _expectSingleCall(invoker, unlinkMyAccountEndpoint, <String, Object?>{});
    });

    test('adminUpdateTipper sends only what is given', () async {
      invoker.answer = <String, Object?>{
        'tipperId': 't1',
        'changed': <String>['role'],
      };
      final result = await service.adminUpdateTipper(
        tipperId: 't1',
        role: TipperRole.admin,
      );
      _expectSingleCall(invoker, adminUpdateTipperEndpoint, <String, Object?>{
        'tipperId': 't1',
        'role': 'admin',
      });
      expect(result.changed, ['role']);
    });

    test('adminMergeTippers sends every option', () async {
      invoker.answer = <String, Object?>{
        'targetId': 't2',
        'tipsMoved': 3,
        'tipsReplaced': 1,
        'loginMoved': true,
        'accountMoved': false,
        'dryRun': true,
      };
      final result = await service.adminMergeTippers(
        originalId: 't1',
        targetId: 't2',
        mergeTips: true,
        dryRun: true,
      );
      _expectSingleCall(invoker, adminMergeTippersEndpoint, <String, Object?>{
        'originalId': 't1',
        'targetId': 't2',
        'mergeTips': true,
        'mergeLogon': false,
        'dryRun': true,
      });
      expect(result.tipsMoved, 3);
      expect(result.dryRun, true);
    });

    test(
      'an answer of the wrong shape is an unexpected failure, not a crash',
      () async {
        for (final bad in <Object?>[
          null,
          'text',
          <String, Object?>{},
          <String, Object?>{'tipperId': 't1', 'outcome': 'teleported'},
          <Object?>[],
        ]) {
          invoker.answer = bad;
          await expectLater(
            service.linkOrCreateTipper(),
            throwsA(
              isA<IdentityFailure>().having(
                (f) => f.kind,
                'kind',
                IdentityFailureKind.unexpected,
              ),
            ),
            reason: '$bad',
          );
        }
      },
    );

    test('a failure from the invoker reaches the caller unchanged', () async {
      final failure = IdentityFailure.fromFunctionsError(
        code: 'failed-precondition',
        message: 'Taken',
        details: _info(identityReasonAliasTaken),
      );
      invoker.failWith = failure;
      await expectLater(service.updateTipperAlias('x'), throwsA(same(failure)));
    });

    test('a timeout from the invoker is a transient network failure', () async {
      invoker.failWith = TimeoutException('slow');
      await expectLater(
        service.unlinkMyAccount(),
        throwsA(
          isA<IdentityFailure>()
              .having((f) => f.isRetryable, 'retryable', true)
              .having((f) => f.code, 'code', 'network'),
        ),
      );
    });

    test('every call is given the same generous timeout', () {
      expect(
        IdentityService.callTimeout,
        greaterThan(const Duration(seconds: 60)),
      );
    });
  });
}
