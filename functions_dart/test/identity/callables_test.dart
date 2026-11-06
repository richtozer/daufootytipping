// The four identity callables, driven through the real callable pipeline.
//
// Nothing here calls a handler function directly. Each request goes through
// firebase_functions' own request handling (ID token check, App Check check,
// error serialisation), against the registered callables, so what is proved is
// what a client would meet: a request without App Check is refused whatever the
// mode, a signed-in caller in a mode that forbids the call is refused with the
// documented reason, and the tipper acted on is the caller's, never one named in
// the request.
import 'dart:convert';

import 'package:dart_functions/identity/callables.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/handler_deadline.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:firebase_functions/testing.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/identity_helpers.dart';
import '../support/identity_invariants.dart';
import '../support/mock_firebase_auth.dart';

const String _uidA = 'uidA00000000000000000000001';
const String _uidB = 'uidB00000000000000000000002';
const String _stranger = 'uidZ00000000000000000000009';
const String _token = 'dXYZ:APA91bExample-0001_aaaaaaaaaaaaaaaa';

/// Every identity callable and a request body that is valid for it.
final Map<String, Object?> _validBodies = <String, Object?>{
  linkOrCreateTipperEndpoint: <String, Object?>{},
  updateTipperAliasEndpoint: <String, Object?>{'alias': 'Patricia'},
  registerDeviceTokenEndpoint: <String, Object?>{'token': _token},
  unregisterDeviceTokenEndpoint: <String, Object?>{'token': _token},
};

/// What came back: the HTTP status and, for an error, its `error` object.
class _Reply {
  _Reply(this.status, this.body);

  final int status;
  final Map<String, Object?> body;

  Map<String, Object?> get result =>
      Map<String, Object?>.from(body['result'] as Map);
  Map<String, Object?> get error =>
      Map<String, Object?>.from(body['error'] as Map);
  String get errorStatus => '${error['status']}';

  /// The identity reason carried in the error's ErrorInfo detail, if any.
  String? get reason {
    final details = error['details'];
    if (details is! List || details.isEmpty) {
      return null;
    }
    final first = details.first as Map;
    expect(first['@type'], 'type.googleapis.com/google.rpc.ErrorInfo');
    expect(first['domain'], identityErrorDomain);
    return first['reason'] as String?;
  }
}

void main() {
  final skip = emulatorSkipReason;

  late FirebaseApp app;
  late FunctionsTestClient client;
  final opened = <RestDatabase>[];
  var openerFails = false;

  /// The registered callables, with a database opener that notes every handle
  /// it hands out (or fails, to prove the handler is reached).
  Future<void> register({Duration? deadline}) async {
    client = await runFunctionsTest(
      adminApp: app,
      (firebase) => registerIdentityCallables(
        firebase,
        openDatabase: () async {
          if (openerFails) {
            throw StateError('the database cannot be opened in this test');
          }
          final database = openEmulatorDatabase();
          opened.add(database);
          return database;
        },
        handlerDeadline: deadline ?? handlerSoftDeadline,
      ),
    );
  }

  setUp(() async {
    app = createMockFirebaseApp();
    opened.clear();
    openerFails = false;
    await register();
  });

  tearDown(() async {
    client.dispose();
    await FirebaseApp.deleteApp(app);
  });

  /// One call, as a client makes it. [appCheck] defaults to a valid token and
  /// null sends none.
  Future<_Reply> call(
    String endpoint, {
    Object? data = const <String, Object?>{},
    String? idToken,
    String? appCheck = '',
  }) => withMockAppCheckKeys(() async {
    final response = await client.call(
      endpoint,
      data: data,
      idToken: idToken,
      extraHeaders: <String, String>{
        if (appCheck != null)
          'x-firebase-appcheck': appCheck.isEmpty
              ? mintAppCheckToken()
              : appCheck,
      },
    );
    return _Reply(
      response.statusCode,
      Map<String, Object?>.from(
        jsonDecode(await response.readAsString()) as Map,
      ),
    );
  });

  String idTokenFor(String uid, {String? email, bool verified = true}) =>
      mintIdToken(uid: uid, email: email, emailVerified: verified);

  group('withSignInProvider', () {
    String tokenWith(Object? payload) {
      String part(Object? value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      return '${part({'alg': 'RS256'})}.${part(payload)}.signature';
    }

    test('adds the firebase claim the runtime leaves out', () {
      final claims = withSignInProvider(
        <String, dynamic>{'email': 'pat@example.com'},
        tokenWith({
          'firebase': {'sign_in_provider': 'anonymous'},
        }),
      );
      expect(claims?['email'], 'pat@example.com');
      expect(
        CallerToken.fromClaims(_uidA, claims).isAnonymous,
        isTrue,
        reason: 'the provider reaches the caller',
      );
    });

    test('leaves a claim that is already there alone', () {
      final claims = withSignInProvider(
        <String, dynamic>{
          'firebase': {'sign_in_provider': 'password'},
        },
        tokenWith({
          'firebase': {'sign_in_provider': 'anonymous'},
        }),
      );
      expect(CallerToken.fromClaims(_uidA, claims).isAnonymous, isFalse);
    });

    test('changes nothing when the token cannot be read', () {
      for (final raw in <String?>[null, '', 'abc', 'a.b.c', 'a.!!.c']) {
        final claims = <String, dynamic>{'email': 'pat@example.com'};
        expect(withSignInProvider(claims, raw), claims, reason: '$raw');
      }
      expect(withSignInProvider(<String, dynamic>{'x': 1}, tokenWith('text')), {
        'x': 1,
      }, reason: 'a payload that is not an object');
      expect(withSignInProvider(null, tokenWith({})), isNull);
    });
  });

  group('a request the runtime refuses never reaches the handler', () {
    for (final endpoint in _validBodies.keys) {
      group(endpoint, () {
        test('without an App Check token', () async {
          final reply = await call(
            endpoint,
            data: _validBodies[endpoint],
            idToken: idTokenFor(_uidA, email: 'pat@example.com'),
            appCheck: null,
          );
          expect(reply.status, 401);
          expect(opened, isEmpty);
        });

        test('with an App Check token that is garbage', () async {
          final reply = await call(
            endpoint,
            data: _validBodies[endpoint],
            idToken: idTokenFor(_uidA, email: 'pat@example.com'),
            appCheck: 'not-a-token',
          );
          expect(reply.status, 401);
          expect(opened, isEmpty);
        });

        test('with an App Check token signed by the wrong key', () async {
          final reply = await call(
            endpoint,
            data: _validBodies[endpoint],
            idToken: idTokenFor(_uidA, email: 'pat@example.com'),
            appCheck: tamperToken(mintAppCheckToken()),
          );
          expect(reply.status, 401);
          expect(opened, isEmpty);
        });

        test('with an expired App Check token', () async {
          final reply = await call(
            endpoint,
            data: _validBodies[endpoint],
            idToken: idTokenFor(_uidA, email: 'pat@example.com'),
            appCheck: mintAppCheckToken(
              exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600,
            ),
          );
          expect(reply.status, 401);
          expect(opened, isEmpty);
        });

        test('with a tampered ID token', () async {
          final reply = await call(
            endpoint,
            data: _validBodies[endpoint],
            idToken: tamperToken(idTokenFor(_uidA, email: 'pat@example.com')),
          );
          expect(reply.status, 401);
          expect(opened, isEmpty);
        });

        test('with an expired ID token', () async {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final reply = await call(
            endpoint,
            data: _validBodies[endpoint],
            idToken: mintIdToken(
              uid: _uidA,
              email: 'pat@example.com',
              exp: now - 3600,
              iat: now - 7200,
            ),
          );
          expect(reply.status, 401);
          expect(opened, isEmpty);
        });

        test('with an ID token for another project', () async {
          final reply = await call(
            endpoint,
            data: _validBodies[endpoint],
            idToken: mintIdToken(
              uid: _uidA,
              email: 'pat@example.com',
              projectId: 'some-other-project',
            ),
          );
          expect(reply.status, 401);
          expect(opened, isEmpty);
        });
      });
    }
  });

  group('a caller who is not signed in', () {
    for (final endpoint in _validBodies.keys) {
      test(
        '$endpoint: refused as unauthenticated, database untouched',
        () async {
          final reply = await call(endpoint, data: _validBodies[endpoint]);
          expect(reply.status, 401);
          expect(reply.errorStatus, 'UNAUTHENTICATED');
          expect(opened, isEmpty, reason: 'no database is opened for them');
        },
      );
    }
  });

  group('a signed-in caller with App Check reaches the handler', () {
    for (final endpoint in _validBodies.keys) {
      test(
        '$endpoint: and is told to try again when the database fails',
        () async {
          openerFails = true;
          final reply = await call(
            endpoint,
            data: _validBodies[endpoint],
            idToken: idTokenFor(_uidA, email: 'pat@example.com'),
          );
          expect(reply.status, 503);
          expect(reply.errorStatus, 'UNAVAILABLE');
          expect(reply.reason, 'unavailable');
        },
      );
    }
  });

  group('a malformed request is refused before the database is opened', () {
    Future<_Reply> bad(String endpoint, Object? data) => call(
      endpoint,
      data: data,
      idToken: idTokenFor(_uidA, email: 'pat@example.com'),
    );

    test('update-tipper-alias without an alias', () async {
      final reply = await bad(updateTipperAliasEndpoint, <String, Object?>{});
      expect(reply.status, 400);
      expect(reply.errorStatus, 'INVALID_ARGUMENT');
      expect(reply.reason, 'invalid_alias');
      expect(opened, isEmpty);
    });

    test('link-or-create-tipper with an alias that is not text', () async {
      final reply = await bad(linkOrCreateTipperEndpoint, <String, Object?>{
        'alias': 42,
      });
      expect(reply.status, 400);
      expect(reply.errorStatus, 'INVALID_ARGUMENT');
      expect(opened, isEmpty);
    });

    for (final endpoint in <String>[
      registerDeviceTokenEndpoint,
      unregisterDeviceTokenEndpoint,
    ]) {
      test('$endpoint with no token', () async {
        final reply = await bad(endpoint, <String, Object?>{});
        expect(reply.errorStatus, 'INVALID_ARGUMENT');
        expect(reply.reason, 'invalid_token');
        expect(opened, isEmpty);
      });

      test('$endpoint with a token too long to be one', () async {
        final reply = await bad(endpoint, <String, Object?>{
          'token': 'x' * (maxDeviceTokenLength + 1),
        });
        expect(reply.errorStatus, 'INVALID_ARGUMENT');
        expect(reply.reason, 'invalid_token');
        expect(opened, isEmpty);
      });
    }
  });

  group('against the database', () {
    late final RestDatabase db = openEmulatorDatabase();

    IdentitySeed baseline() => IdentitySeed()
      ..tipper(
        't1',
        name: 'Pat',
        authuid: _uidA,
        logon: 'pat@example.com',
        indexAccount: true,
      )
      ..tipper(
        't2',
        name: 'Sam',
        authuid: _uidB,
        logon: 'sam@example.com',
        indexAccount: true,
      );

    late Map<String, Object?> seeded;

    setUp(() async {
      await clearEmulatorDatabase(db);
      seeded = baseline().data;
      await db.ref('/').set(seeded);
    });

    Future<void> setMode(String mode, {List<String>? pilotUids}) => db
        .ref(identityModePath)
        .update(<String, Object?>{'mode': mode, 'pilotUids': ?pilotUids});

    Future<_Reply> asPat(String endpoint, [Object? data]) => call(
      endpoint,
      data: data ?? _validBodies[endpoint],
      idToken: idTokenFor(_uidA, email: 'pat@example.com'),
    );

    group('the server mode is honoured', () {
      for (final endpoint in _validBodies.keys) {
        test('$endpoint is refused in mode off, and writes nothing', () async {
          // No mode stored at all means off.
          final before = canonical(await readRoot(db));
          final reply = await asPat(endpoint);
          expect(reply.status, 400);
          expect(reply.errorStatus, 'FAILED_PRECONDITION');
          expect(reply.reason, 'not_available');
          expect(
            canonical(await readRoot(db)),
            before,
            reason: 'even the in-flight marker is cleared again',
          );
        });

        test('$endpoint is refused in pilot for a caller not in it', () async {
          await setMode('pilot', pilotUids: <String>[_stranger]);
          final before = canonical(await readRoot(db));
          final reply = await asPat(endpoint);
          expect(reply.errorStatus, 'FAILED_PRECONDITION');
          expect(reply.reason, 'not_available');
          expect(canonical(await readRoot(db)), before);
        });

        test('$endpoint is told to retry in freeze', () async {
          await setMode('freeze');
          final before = canonical(await readRoot(db));
          final reply = await asPat(endpoint);
          expect(reply.status, 503);
          expect(reply.errorStatus, 'UNAVAILABLE');
          expect(reply.reason, 'unavailable');
          expect(canonical(await readRoot(db)), before);
        });
      }

      test('a pilot caller is let through in pilot', () async {
        await setMode('pilot', pilotUids: <String>[_uidA]);
        final reply = await asPat(updateTipperAliasEndpoint);
        expect(reply.status, 200, reason: '${reply.body}');
        expect(reply.result['alias'], 'Patricia');
      });

      test('a refusal leaves no in-flight marker behind', () async {
        await asPat(linkOrCreateTipperEndpoint);
        final root = await readRoot(db);
        final inflight =
            ((root['ServerConfig'] as Map?)?['identity'] as Map?)?['inflight'];
        expect(inflight, isNull);
      });
    });

    group('in coexist mode', () {
      setUp(() => setMode('coexist'));

      test('link-or-create-tipper refreshes a linked account', () async {
        final reply = await asPat(linkOrCreateTipperEndpoint);
        expect(reply.status, 200, reason: '${reply.body}');
        expect(reply.result, <String, Object?>{
          'tipperId': 't1',
          'outcome': 'existing',
        });
        expectIdentityConsistent(await readRoot(db));
      });

      test('link-or-create-tipper refuses an unverified address', () async {
        final reply = await call(
          linkOrCreateTipperEndpoint,
          idToken: idTokenFor(
            _stranger,
            email: 'new@example.com',
            verified: false,
          ),
        );
        expect(reply.errorStatus, 'PERMISSION_DENIED');
        expect(reply.reason, 'unverified_email');
      });

      test('link-or-create-tipper refuses an anonymous sign-in', () async {
        final reply = await call(
          linkOrCreateTipperEndpoint,
          idToken: mintIdToken(uid: _stranger, provider: 'anonymous'),
        );
        expect(reply.errorStatus, 'PERMISSION_DENIED');
        expect(reply.reason, 'not_linked');
      });

      test(
        'link-or-create-tipper creates a record for a new account',
        () async {
          final reply = await call(
            linkOrCreateTipperEndpoint,
            data: <String, Object?>{'alias': 'Newcomer'},
            idToken: idTokenFor(_stranger, email: 'new@example.com'),
          );
          expect(reply.status, 200, reason: '${reply.body}');
          expect(reply.result['outcome'], 'created');
          final root = await readRoot(db);
          expect(
            rowAt(root, 'AllTippers', '${reply.result['tipperId']}')['name'],
            'Newcomer',
          );
          expectIdentityConsistent(root);
        },
      );

      test(
        'update-tipper-alias renames the caller, whatever the request names',
        () async {
          final reply = await asPat(
            updateTipperAliasEndpoint,
            <String, Object?>{
              'alias': 'Patricia',
              'tipperId': 't2',
              'uid': _uidB,
            },
          );
          expect(reply.status, 200, reason: '${reply.body}');
          expect(reply.result, <String, Object?>{
            'tipperId': 't1',
            'alias': 'Patricia',
          });
          final root = await readRoot(db);
          expect(rowAt(root, 'AllTippers', 't1')['name'], 'Patricia');
          expect(rowAt(root, 'AllTippers', 't2')['name'], 'Sam');
          expectIdentityConsistent(root);
        },
      );

      test('update-tipper-alias says when the alias is taken', () async {
        final reply = await asPat(updateTipperAliasEndpoint, <String, Object?>{
          'alias': 'sam',
        });
        expect(reply.errorStatus, 'FAILED_PRECONDITION');
        expect(reply.reason, 'alias_taken');
        expect(rowAt(await readRoot(db), 'AllTippers', 't1')['name'], 'Pat');
      });

      test('update-tipper-alias refuses an account with no tipper', () async {
        final reply = await call(
          updateTipperAliasEndpoint,
          data: <String, Object?>{'alias': 'Nobody'},
          idToken: idTokenFor(_stranger, email: 'new@example.com'),
        );
        expect(reply.reason, 'not_linked');
      });

      test('register-device-token and unregister-device-token', () async {
        final registered = await asPat(registerDeviceTokenEndpoint);
        expect(registered.status, 200, reason: '${registered.body}');
        expect(registered.result, <String, Object?>{'tipperId': 't1'});
        var root = await readRoot(db);
        expect(
          ((root['AllTippersTokens'] as Map)['t1'] as Map).keys,
          contains(_token),
        );
        expectTokensConsistent(root);

        final removed = await asPat(unregisterDeviceTokenEndpoint);
        expect(removed.status, 200, reason: '${removed.body}');
        expect(removed.result, <String, Object?>{'removed': true});
        root = await readRoot(db);
        expect(
          ((root['AllTippersTokens'] as Map?)?['t1'] as Map?)?.keys ??
              const <Object?>[],
          isNot(contains(_token)),
        );
        expectTokensConsistent(root);
      });

      test('a token moves to whoever registered it last', () async {
        await asPat(registerDeviceTokenEndpoint);
        final moved = await call(
          registerDeviceTokenEndpoint,
          data: <String, Object?>{'token': _token},
          idToken: idTokenFor(_uidB, email: 'sam@example.com'),
        );
        expect(moved.result, <String, Object?>{'tipperId': 't2'});
        final root = await readRoot(db);
        final tokens = root['AllTippersTokens'] as Map;
        expect(
          (tokens['t1'] as Map?)?.keys ?? const <Object?>[],
          isNot(contains(_token)),
        );
        expect((tokens['t2'] as Map).keys, contains(_token));
        expectTokensConsistent(root);
      });
    });

    group('requests and their database handles', () {
      setUp(() => setMode('coexist'));

      test('each request gets a handle of its own', () async {
        await asPat(registerDeviceTokenEndpoint);
        await asPat(unregisterDeviceTokenEndpoint);
        await asPat(linkOrCreateTipperEndpoint);
        expect(opened, hasLength(3));
        expect(
          opened.toSet(),
          hasLength(3),
          reason:
              'the writes a request waits for before clearing its marker '
              'must be its own',
        );
      });

      test('a handler past its deadline stops at its next step', () async {
        client.dispose();
        await register(deadline: Duration.zero);
        final reply = await asPat(updateTipperAliasEndpoint);
        expect(reply.status, 503);
        expect(reply.errorStatus, 'UNAVAILABLE');
        expect(reply.reason, 'unavailable');
        final root = await readRoot(db);
        expect(
          ((root['ServerConfig'] as Map)['identity'] as Map)['inflight'],
          isNull,
          reason: 'the marker is cleared even when the handler gave up',
        );
        expect(root['IdentityLocks'], isNull, reason: 'and the lease released');
        // The move it had journalled is left for the next call to finish, as
        // after a crash.
        expectIdentityConsistent(root, allowPending: true);

        // And the same request succeeds when there is time.
        client.dispose();
        await register();
        final retry = await asPat(updateTipperAliasEndpoint);
        expect(retry.status, 200, reason: '${retry.body}');
        expectIdentityConsistent(await readRoot(db));
      });
    });
  }, skip: skip);
}
