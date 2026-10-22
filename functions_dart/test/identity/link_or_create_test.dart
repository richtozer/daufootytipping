import 'dart:async';
import 'dart:math';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/caller.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/link_or_create.dart';
import 'package:dart_functions/identity/operation_id.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/identity/tipper_shapes.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:firebase_functions/firebase_functions.dart'
    show HttpResponseException;
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/identity_invariants.dart';

const int _t0 = 1700000000000;
int _seed = 1;
const String _uidA = 'uidA00000000000000000000001';
const String _uidB = 'uidB00000000000000000000002';

/// Builds the database a test starts from.
class _Seed {
  final Map<String, Object?> data = <String, Object?>{
    'AppConfig': {'createLinkedTipper': true},
  };

  Map<String, Object?> _root(String key) =>
      (data[key] ??= <String, Object?>{}) as Map<String, Object?>;

  /// A tipper. By default fully audited: public and private records, and the
  /// alias and login claims. [indexAccount] also links [authuid] in `/AuthIndex`.
  void tipper(
    String id, {
    String? name,
    String? authuid,
    String? logon,
    String? email,
    bool hasPublic = true,
    bool hasPrivate = true,
    bool claimAlias = true,
    bool claimLogon = true,
    bool indexAccount = false,
    String? placeholder,
    bool legacyPublic = true,
  }) {
    if (hasPublic) {
      _root('AllTippers')[id] = <String, Object?>{
        'name': ?name,
        if (legacyPublic) ...<String, Object?>{
          'authuid': ?authuid,
          'logon': ?logon,
          'email': ?email,
          'tipperRole': 'tipper',
          'isAnonymous': false,
        },
      };
    }
    if (hasPrivate) {
      _root('TipperPrivate')[id] = <String, Object?>{
        'authuid': ?authuid,
        'logon': ?logon,
        'email': ?email,
        'tipperRole': 'tipper',
        'isAnonymous': false,
        'acctCreatedUTC': '2025-02-01 03:04:05.000Z',
      };
    }
    if (claimAlias && name != null) {
      _root('AliasIndex')[aliasIndexKey(name)] = id;
    }
    if (claimLogon && logon != null && hasPrivate) {
      _root('LogonIndex')[logonIndexKey(logon)] = id;
    }
    if (indexAccount && authuid != null) {
      _root('AuthIndex')[authuid] = id;
    }
    if (placeholder != null) {
      _root('Placeholders')[id] = placeholder;
    }
  }
}

CallerToken _caller(
  String uid,
  String? email, {
  bool verified = true,
  String provider = 'password',
  String? picture,
}) => CallerToken(
  uid: uid,
  email: email,
  emailVerified: verified,
  signInProvider: provider,
  pictureUrl: picture,
);

Admission _admission({IdentityMode mode = IdentityMode.coexist}) => Admission(
  operationId: newOperationId(),
  config: ServerModeConfig(mode: mode),
);

/// A checkpoint that makes the operation "crash" right after [step].
Checkpoint _crashAfter(String step) =>
    (reached) async => reached == step ? throw SimulatedCrash(step) : null;

String? _reasonOf(Object error) {
  if (error is! HttpResponseException) {
    return null;
  }
  final details = error.details;
  return details == null || details.isEmpty
      ? null
      : details.first['reason'] as String?;
}

/// Matches a refusal with this reason.
Matcher _refusedAs(String reason) => throwsA(
  predicate<Object>(
    (error) => _reasonOf(error) == reason,
    'refused with reason $reason',
  ),
);

Map<String, Object?> _at(Map<String, Object?> root, String node, String id) {
  final value = (root[node] as Map?)?[id];
  return value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
}

void main() {
  final skip = emulatorSkipReason;

  group('linkOrCreateTipper', () {
    late final RestDatabase db = openEmulatorDatabase();

    Future<void> seed(_Seed seed) async {
      await clearEmulatorDatabase(db);
      await db.ref('/').set(seed.data);
    }

    Future<LinkOrCreateTipperResult> call(
      CallerToken caller, {
      String? alias,
      IdentityMode mode = IdentityMode.coexist,
      int at = _t0,
      Checkpoint? checkpoint,
      RestDatabase? on,
    }) => linkOrCreateTipper(
      database: on ?? db,
      caller: caller,
      request: LinkOrCreateTipperRequest(alias: alias),
      admission: _admission(mode: mode),
      nowMs: () => at,
      checkpoint: checkpoint,
      random: Random(_seed++),
    );

    /// Runs [action] and proves it changed nothing in the database.
    Future<void> refusedWithoutWriting(
      Future<Object?> Function() action,
      String reason,
    ) async {
      final before = canonical(await readRoot(db));
      await expectLater(action(), _refusedAs(reason));
      expect(
        canonical(await readRoot(db)),
        before,
        reason: 'a refused request must not write',
      );
    }

    group('who may call', () {
      setUp(() => seed(_Seed()));

      test('an anonymous account is refused', () async {
        await refusedWithoutWriting(
          () => call(_caller(_uidA, null, provider: 'anonymous')),
          identityReasonNotLinked,
        );
      }, skip: skip);

      test('an unverified, missing or blank email is refused', () async {
        for (final caller in [
          _caller(_uidA, 'a@example.com', verified: false),
          _caller(_uidA, null),
          _caller(_uidA, '   '),
        ]) {
          await refusedWithoutWriting(
            () => call(caller),
            identityReasonUnverifiedEmail,
          );
        }
      }, skip: skip);

      test('a uid that cannot be a database key is refused', () async {
        await expectLater(
          call(_caller('bad.uid', 'a@example.com')),
          throwsA(isA<InvalidArgumentError>()),
        );
      }, skip: skip);
    });

    group('an account that is already linked', () {
      Future<void> seedLinked({
        bool legacyPublic = true,
        String? email = 'pat.contact@example.com',
      }) async {
        final s = _Seed()
          ..tipper(
            't1',
            name: 'Pat',
            authuid: _uidA,
            logon: 'pat@example.com',
            email: email,
            indexAccount: true,
            legacyPublic: legacyPublic,
          );
        await seed(s);
      }

      test(
        'is recognised, stamped and left otherwise alone (legacy shape)',
        () async {
          await seedLinked();
          final result = await call(
            _caller(_uidA, 'pat@example.com'),
            at: _t0 + 1000,
          );
          expect(result.outcome, LinkOutcome.existing);
          expect(result.tipperId, 't1');

          final root = await readRoot(db);
          expect(
            _at(root, 'TipperPrivate', 't1')['acctLoggedOnUTC'],
            stampOf(_t0 + 1000),
          );
          expect(
            _at(root, 'AllTippers', 't1')['acctLoggedOnUTC'],
            stampOf(_t0 + 1000),
          );
          expect(_at(root, 'TipperPrivate', 't1')['authuid'], _uidA);
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test(
        'in the final shape the public record never gets private fields',
        () async {
          await seedLinked(legacyPublic: false);
          await call(
            _caller(
              _uidA,
              'pat@example.com',
              picture: 'https://example.com/p.png',
            ),
            mode: IdentityMode.finalShape,
            at: _t0 + 1000,
          );
          final root = await readRoot(db);
          expect(_at(root, 'AllTippers', 't1').keys.toSet(), {
            'name',
            'photoURL',
          });
          expect(
            _at(root, 'TipperPrivate', 't1')['acctLoggedOnUTC'],
            stampOf(_t0 + 1000),
          );
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test(
        'follows a changed photo, fills an invalid contact email and never overwrites a valid one',
        () async {
          await seedLinked(email: 'not an email');
          await call(
            _caller(
              _uidA,
              'pat@example.com',
              picture: 'https://example.com/new.png',
            ),
          );
          var root = await readRoot(db);
          expect(
            _at(root, 'AllTippers', 't1')['photoURL'],
            'https://example.com/new.png',
          );
          expect(_at(root, 'TipperPrivate', 't1')['email'], 'pat@example.com');

          await seedLinked();
          await call(_caller(_uidA, 'pat@example.com'));
          root = await readRoot(db);
          expect(
            _at(root, 'TipperPrivate', 't1')['email'],
            'pat.contact@example.com',
          );
        },
        skip: skip,
      );

      test(
        'an index entry that its record does not agree with is refused for repair and nothing is written',
        () async {
          final s = _Seed()
            ..tipper(
              't1',
              name: 'Pat',
              authuid: 'someone-else',
              logon: 'pat@example.com',
            );
          s.data['AuthIndex'] = {_uidA: 't1'};
          await seed(s);
          await refusedWithoutWriting(
            () => call(_caller(_uidA, 'pat@example.com')),
            identityReasonNeedsAudit,
          );
        },
        skip: skip,
      );

      test(
        'a changed login address moves the claim, and the old one is released',
        () async {
          await seedLinked();
          await call(_caller(_uidA, 'new@example.com'));
          final root = await readRoot(db);
          expect((root['LogonIndex'] as Map).keys, [
            logonIndexKey('new@example.com'),
          ]);
          expect(_at(root, 'TipperPrivate', 't1')['logon'], 'new@example.com');
          expect(_at(root, 'AllTippers', 't1')['logon'], 'new@example.com');
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test(
        'a login address another tipper holds is refused, after the refresh, and the old claim stays',
        () async {
          final s = _Seed()
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
              logon: 'taken@example.com',
              indexAccount: true,
            );
          await seed(s);
          await expectLater(
            call(_caller(_uidA, 'taken@example.com'), at: _t0 + 5),
            _refusedAs(identityReasonClaimed),
          );
          final root = await readRoot(db);
          expect(
            _at(root, 'TipperPrivate', 't1')['acctLoggedOnUTC'],
            stampOf(_t0 + 5),
            reason: 'the refresh still happened',
          );
          expect(_at(root, 'TipperPrivate', 't1')['logon'], 'pat@example.com');
          expect(
            (root['LogonIndex'] as Map)[logonIndexKey('pat@example.com')],
            't1',
          );
          expectIdentityConsistent(root);
        },
        skip: skip,
      );
    });

    group('linking to an existing record', () {
      test(
        'by login address: the account is linked and the profile is refreshed',
        () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              logon: 'pat@example.com',
              email: 'pat.contact@example.com',
            ),
          );
          final result = await call(
            _caller(_uidA, 'pat@example.com'),
            at: _t0 + 10,
          );
          expect(result.outcome, LinkOutcome.linked);
          expect(result.tipperId, 't1');

          final root = await readRoot(db);
          expect((root['AuthIndex'] as Map)[_uidA], 't1');
          expect(_at(root, 'TipperPrivate', 't1')['authuid'], _uidA);
          expect(_at(root, 'AllTippers', 't1')['authuid'], _uidA);
          expect(
            _at(root, 'TipperPrivate', 't1')['acctLoggedOnUTC'],
            stampOf(_t0 + 10),
          );
          expectIdentityConsistent(root);
          expect(await resolveCallerTipper(db, _uidA), isA<ResolvedCaller>());
        },
        skip: skip,
      );

      test(
        'by contact email only: the login address becomes the verified one, claimed',
        () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              logon: 'old.login@example.com',
              email: 'pat@example.com',
            ),
          );
          final result = await call(_caller(_uidA, 'pat@example.com'));
          expect(result.outcome, LinkOutcome.linked);
          final root = await readRoot(db);
          expect(_at(root, 'TipperPrivate', 't1')['logon'], 'pat@example.com');
          expect((root['LogonIndex'] as Map).keys, [
            logonIndexKey('pat@example.com'),
          ]);
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test('matches regardless of case and surrounding spaces', () async {
        await seed(
          _Seed()..tipper('t1', name: 'Pat', logon: ' Pat@Example.COM '),
        );
        final result = await call(_caller(_uidA, 'pat@example.com'));
        expect(result.tipperId, 't1');
        expectIdentityConsistent(await readRoot(db));
      }, skip: skip);

      test(
        'an audited placeholder is replaced, and its audit entry is removed',
        () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              authuid: 'old.player@example.com',
              logon: 'pat@example.com',
              placeholder: 'old.player@example.com',
            ),
          );
          final result = await call(_caller(_uidA, 'pat@example.com'));
          expect(result.outcome, LinkOutcome.linked);
          final root = await readRoot(db);
          expect(_at(root, 'TipperPrivate', 't1')['authuid'], _uidA);
          expect(root['Placeholders'], isNull);
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test(
        'a value that is not exactly the audited placeholder is claimed, and nothing is written',
        () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              authuid: 'a-different-value',
              logon: 'pat@example.com',
              placeholder: 'old.player@example.com',
            ),
          );
          await refusedWithoutWriting(
            () => call(_caller(_uidA, 'pat@example.com')),
            identityReasonClaimed,
          );
        },
        skip: skip,
      );

      test(
        'a record with no recorded placeholder and a stored value is claimed, however it looks',
        () async {
          for (final looksLike in ['x@example.com', _uidB, 'plainstring']) {
            await seed(
              _Seed()..tipper(
                't1',
                name: 'Pat',
                authuid: looksLike,
                logon: 'pat@example.com',
              ),
            );
            await refusedWithoutWriting(
              () => call(_caller(_uidA, 'pat@example.com')),
              identityReasonClaimed,
            );
          }
        },
        skip: skip,
      );

      test(
        'a record already held by another real account is never taken over',
        () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              authuid: _uidB,
              logon: 'pat@example.com',
              indexAccount: true,
            ),
          );
          await refusedWithoutWriting(
            () => call(_caller(_uidA, 'pat@example.com')),
            identityReasonClaimed,
          );
        },
        skip: skip,
      );

      test(
        'the same account finishing its own half-linked record completes it',
        () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              authuid: _uidA,
              logon: 'pat@example.com',
            ),
          );
          final result = await call(_caller(_uidA, 'pat@example.com'));
          expect(result.outcome, LinkOutcome.linked);
          expectIdentityConsistent(await readRoot(db));
        },
        skip: skip,
      );
    });

    group('refusing to guess', () {
      test(
        'two records with the same login address are ambiguous and nothing is written',
        () async {
          await seed(
            _Seed()
              ..tipper(
                't1',
                name: 'Pat',
                logon: 'same@example.com',
                claimLogon: false,
              )
              ..tipper(
                't2',
                name: 'Sam',
                logon: 'same@example.com',
                claimLogon: false,
              ),
          );
          await refusedWithoutWriting(
            () => call(_caller(_uidA, 'same@example.com')),
            identityReasonAmbiguous,
          );
        },
        skip: skip,
      );

      test(
        "one record's login equal to another's contact email is ambiguous",
        () async {
          await seed(
            _Seed()
              ..tipper(
                't1',
                name: 'Pat',
                logon: 'x@example.com',
                email: 'other@example.com',
              )
              ..tipper(
                't2',
                name: 'Sam',
                logon: 'sam@example.com',
                email: 'x@example.com',
              ),
          );
          await refusedWithoutWriting(
            () => call(_caller(_uidA, 'x@example.com')),
            identityReasonAmbiguous,
          );
        },
        skip: skip,
      );

      test(
        'a record created by a 1.4.x client after the backfill is found, refused as unaudited, and no duplicate is made',
        () async {
          await seed(
            _Seed()..tipper(
              'legacy-made',
              name: 'Newbie',
              authuid: 'x@example.com',
              logon: 'new@example.com',
              hasPrivate: false,
              claimLogon: false,
              claimAlias: false,
            ),
          );
          await refusedWithoutWriting(
            () => call(_caller(_uidA, 'new@example.com'), alias: 'Newbie Two'),
            identityReasonNeedsAudit,
          );
          expect((await readRoot(db))['AllTippers'] as Map, hasLength(1));
        },
        skip: skip,
      );

      test(
        'a private record with no public record is not linkable either',
        () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              logon: 'pat@example.com',
              hasPublic: false,
            ),
          );
          await refusedWithoutWriting(
            () => call(_caller(_uidA, 'pat@example.com')),
            identityReasonNeedsAudit,
          );
        },
        skip: skip,
      );

      test(
        'an unaudited match blocks creating a new record even when the alias is free',
        () async {
          await seed(
            _Seed()..tipper(
              'legacy-made',
              name: 'Newbie',
              logon: 'new@example.com',
              hasPrivate: false,
              claimLogon: false,
              claimAlias: false,
            ),
          );
          await expectLater(
            call(_caller(_uidA, 'new@example.com'), alias: 'Totally Different'),
            _refusedAs(identityReasonNeedsAudit),
          );
        },
        skip: skip,
      );
    });

    group('racing for one record', () {
      test(
        'ten different accounts at once: exactly one wins, the rest are told it is claimed, and the data is consistent',
        () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              authuid: 'old@example.com',
              logon: 'pat@example.com',
              placeholder: 'old@example.com',
            ),
          );
          final outcomes = await Future.wait([
            for (var index = 0; index < 10; index++)
              call(
                _caller(
                  'racer${index.toString().padLeft(22, '0')}',
                  'pat@example.com',
                ),
              ).then<Object>((r) => r, onError: (Object e) => e),
          ]);
          final wins = outcomes.whereType<LinkOrCreateTipperResult>().toList();
          final losses = outcomes.whereType<HttpResponseException>().toList();
          expect(wins, hasLength(1));
          expect(losses, hasLength(9));
          for (final loss in losses) {
            expect(
              _reasonOf(loss),
              anyOf(identityReasonClaimed, identityReasonBusy),
            );
          }
          final root = await readRoot(db);
          expect((root['AuthIndex'] as Map), hasLength(1));
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test('one account calling twice at once ends with one link', () async {
        await seed(
          _Seed()..tipper(
            't1',
            name: 'Pat',
            authuid: 'old@example.com',
            logon: 'pat@example.com',
            placeholder: 'old@example.com',
          ),
        );
        final outcomes = await Future.wait([
          for (var index = 0; index < 2; index++)
            call(
              _caller(_uidA, 'pat@example.com'),
            ).then<Object>((r) => r, onError: (Object e) => e),
        ]);
        expect(outcomes.whereType<LinkOrCreateTipperResult>(), isNotEmpty);
        for (final outcome in outcomes.whereType<HttpResponseException>()) {
          expect(_reasonOf(outcome), identityReasonBusy);
        }
        // A later call settles whatever the race left.
        expect(
          (await call(_caller(_uidA, 'pat@example.com'))).outcome,
          LinkOutcome.existing,
        );
        final root = await readRoot(db);
        expect(root['AuthIndex'], {_uidA: 't1'});
        expectIdentityConsistent(root);
      }, skip: skip);
    });

    group('a crash after any step of a link, then a retry', () {
      for (final step in [
        'link:private-authuid',
        'link:logon',
        'link:committed',
        'link:profile',
      ]) {
        test('after $step', () async {
          await seed(
            _Seed()..tipper(
              't1',
              name: 'Pat',
              authuid: 'old@example.com',
              logon: 'pat@example.com',
              placeholder: 'old@example.com',
            ),
          );
          final caller = _caller(_uidA, 'pat@example.com');

          await expectLater(
            call(caller, checkpoint: _crashAfter(step)),
            throwsA(isA<SimulatedCrash>()),
          );
          var root = await readRoot(db);
          expectIdentityConsistent(root, allowPending: true);

          // Until the commit, the half-linked account has no access at all.
          final committed = step == 'link:committed' || step == 'link:profile';
          final resolution = await resolveCallerTipper(db, _uidA);
          expect(resolution is ResolvedCaller, committed);

          // The crashed worker's lease is still live, so an immediate retry waits...
          await expectLater(
            call(caller, at: _t0 + 1000),
            _refusedAs(identityReasonBusy),
          );

          // ...and nobody else can take the half-linked record, even once the lease has expired.
          final expired = _t0 + tipperLeaseTtl.inMilliseconds + 1;
          await expectLater(
            call(_caller(_uidB, 'pat@example.com'), at: expired),
            _refusedAs(identityReasonClaimed),
          );

          // ...and once it has expired the retry completes the job.
          final result = await call(
            caller,
            at: _t0 + tipperLeaseTtl.inMilliseconds + 1,
          );
          expect(result.tipperId, 't1');
          root = await readRoot(db);
          expect(root['AuthIndex'], {_uidA: 't1'});
          expect(root['Placeholders'], isNull);
          expectIdentityConsistent(root);
        }, skip: skip);
      }
    });

    group('creating a new record', () {
      Future<void> seedEmpty() => seed(_Seed());

      test(
        'writes both halves, the claims and the commit (legacy shape)',
        () async {
          await seedEmpty();
          final result = await call(
            _caller(
              _uidA,
              'new@example.com',
              picture: 'https://example.com/p.png',
            ),
            alias: 'New Player',
            at: _t0 + 5,
          );
          expect(result.outcome, LinkOutcome.created);

          final root = await readRoot(db);
          final id = result.tipperId;
          expect((root['AuthIndex'] as Map)[_uidA], id);
          expect((root['AliasIndex'] as Map)[aliasIndexKey('New Player')], id);
          expect(
            (root['LogonIndex'] as Map)[logonIndexKey('new@example.com')],
            id,
          );
          final private = TipperPrivate.fromJson(
            _at(root, 'TipperPrivate', id),
          );
          expect(private.authuid, _uidA);
          expect(private.tipperRole, TipperRole.tipper);
          expect(private.isAnonymous, false);
          expect(private.logon, 'new@example.com');
          expect(
            private.acctCreatedUTC,
            DateTime.fromMillisecondsSinceEpoch(_t0 + 5, isUtc: true),
          );
          final publicRecord = _at(root, 'AllTippers', id);
          expect(publicRecord['name'], 'New Player');
          expect(publicRecord['authuid'], _uidA);
          expect(publicRecord['logon'], 'new@example.com');
          expect(publicRecord['photoURL'], 'https://example.com/p.png');
          expect(id, hasLength(20));
          expectIdentityConsistent(root);
          expect(await resolveCallerTipper(db, _uidA), isA<ResolvedCaller>());
        },
        skip: skip,
      );

      test(
        'the pilot mode writes the legacy shape too, the final mode the minimal one',
        () async {
          await seedEmpty();
          final pilot = await call(
            _caller(_uidA, 'a@example.com'),
            alias: 'Pilot Pat',
            mode: IdentityMode.pilot,
          );
          expect(
            _at(
              await readRoot(db),
              'AllTippers',
              pilot.tipperId,
            ).containsKey('authuid'),
            true,
          );

          final created = await call(
            _caller(_uidB, 'b@example.com'),
            alias: 'Final Fran',
            mode: IdentityMode.finalShape,
          );
          expect(
            _at(
              await readRoot(db),
              'AllTippers',
              created.tipperId,
            ).keys.toSet(),
            {'name'},
          );
          expectIdentityConsistent(await readRoot(db));
        },
        skip: skip,
      );

      test(
        'is refused when creating is switched off, with nothing written',
        () async {
          final s = _Seed()..data['AppConfig'] = {'createLinkedTipper': false};
          await seed(s);
          await refusedWithoutWriting(
            () => call(_caller(_uidA, 'new@example.com'), alias: 'Pat'),
            identityReasonCreationDisabled,
          );
        },
        skip: skip,
      );

      test(
        'an alias that cannot be used is refused, with nothing written',
        () async {
          await seedEmpty();
          for (final alias in [null, '', '   ', '🏈🏈', 'x' * 65]) {
            await refusedWithoutWriting(
              () => call(_caller(_uidA, 'new@example.com'), alias: alias),
              identityReasonInvalidAlias,
            );
          }
        },
        skip: skip,
      );

      test(
        'a taken alias rolls back everything, however it is spelled',
        () async {
          await seed(
            _Seed()..tipper(
              't9',
              name: 'Reisy',
              authuid: _uidB,
              logon: 'r@example.com',
              indexAccount: true,
            ),
          );
          for (final alias in ['Reisy', 'R e i s y 🏈', 'reisy']) {
            await refusedWithoutWriting(
              () => call(_caller(_uidA, 'new@example.com'), alias: alias),
              identityReasonAliasTaken,
            );
          }
        },
        skip: skip,
      );

      test(
        'a login address already claimed rolls back the alias claim and the intent',
        () async {
          final s = _Seed();
          s.data['LogonIndex'] = {logonIndexKey('new@example.com'): 'someone'};
          await seed(s);
          await expectLater(
            call(_caller(_uidA, 'new@example.com'), alias: 'Free Alias'),
            _refusedAs(identityReasonClaimed),
          );
          final root = await readRoot(db);
          expect(root['AliasIndex'], isNull);
          expect(root['CreateIntents'], isNull);
          expect(root['AllTippers'], isNull);
        },
        skip: skip,
      );

      test(
        'a second call after creating just recognises the account',
        () async {
          await seedEmpty();
          final first = await call(
            _caller(_uidA, 'new@example.com'),
            alias: 'Pat',
          );
          final second = await call(
            _caller(_uidA, 'new@example.com'),
            alias: 'Pat',
          );
          expect(second.outcome, LinkOutcome.existing);
          expect(second.tipperId, first.tipperId);
          expect((await readRoot(db))['AllTippers'] as Map, hasLength(1));
          expectIdentityConsistent(await readRoot(db));
        },
        skip: skip,
      );

      test('a double tap makes exactly one record', () async {
        await seedEmpty();
        final outcomes = await Future.wait([
          for (var index = 0; index < 3; index++)
            call(
              _caller(_uidA, 'new@example.com'),
              alias: 'Pat',
            ).then<Object>((r) => r, onError: (Object e) => e),
        ]);
        expect(outcomes.whereType<LinkOrCreateTipperResult>(), isNotEmpty);
        for (final error in outcomes.whereType<HttpResponseException>()) {
          expect(_reasonOf(error), identityReasonBusy);
        }
        final root = await readRoot(db);
        expect(root['AllTippers'] as Map, hasLength(1));
        expect(root['AuthIndex'] as Map, hasLength(1));
        expect(root['AliasIndex'] as Map, hasLength(1));
        await call(
          _caller(_uidA, 'new@example.com'),
          alias: 'Pat',
        ); // settles any race leftovers
        expectIdentityConsistent(await readRoot(db));
      }, skip: skip);

      test(
        'two accounts choosing the same alias at once: one wins, the other rolls back cleanly',
        () async {
          await seedEmpty();
          final outcomes = await Future.wait([
            call(
              _caller(_uidA, 'a@example.com'),
              alias: 'Same Name',
            ).then<Object>((r) => r, onError: (Object e) => e),
            call(
              _caller(_uidB, 'b@example.com'),
              alias: 'same  name',
            ).then<Object>((r) => r, onError: (Object e) => e),
          ]);
          expect(outcomes.whereType<LinkOrCreateTipperResult>(), hasLength(1));
          final loser = outcomes.whereType<HttpResponseException>().single;
          expect(_reasonOf(loser), identityReasonAliasTaken);

          final root = await readRoot(db);
          expect(root['AllTippers'] as Map, hasLength(1));
          expect(
            root['LogonIndex'] as Map,
            hasLength(1),
            reason: 'the loser left no login claim',
          );
          expect(root['AuthIndex'] as Map, hasLength(1));
          expectIdentityConsistent(root);
        },
        skip: skip,
      );
    });

    group('a crash after any step of a create, then a retry', () {
      for (final step in [
        'create:intent',
        'create:alias',
        'create:logon',
        'create:records',
        'create:committed',
      ]) {
        test('after $step', () async {
          await seed(_Seed());
          final caller = _caller(_uidA, 'new@example.com');

          await expectLater(
            call(caller, alias: 'Pat', checkpoint: _crashAfter(step)),
            throwsA(isA<SimulatedCrash>()),
          );
          var root = await readRoot(db);
          expectIdentityConsistent(root, allowPending: true);
          final firstId =
              (root['CreateIntents'] as Map)[_uidA]['tipperId'] as String;
          expect(
            await resolveCallerTipper(db, _uidA) is ResolvedCaller,
            step == 'create:committed',
            reason: 'no access until the commit',
          );

          await expectLater(
            call(caller, alias: 'Pat', at: _t0 + 1000),
            _refusedAs(identityReasonBusy),
          );

          final result = await call(
            caller,
            alias: 'Pat',
            at: _t0 + tipperLeaseTtl.inMilliseconds + 1,
          );
          expect(
            result.tipperId,
            firstId,
            reason: 'the retry reuses the same tipper id',
          );
          root = await readRoot(db);
          expect(root['AllTippers'] as Map, hasLength(1));
          expect(root['AuthIndex'], {_uidA: firstId});
          expectIdentityConsistent(root);
        }, skip: skip);
      }

      test('a retry with a different alias lets go of the first one', () async {
        await seed(_Seed());
        final caller = _caller(_uidA, 'new@example.com');
        await expectLater(
          call(
            caller,
            alias: 'First Choice',
            checkpoint: _crashAfter('create:alias'),
          ),
          throwsA(isA<SimulatedCrash>()),
        );

        // Meanwhile nobody else can have the abandoned-but-held alias...
        await expectLater(
          call(_caller(_uidB, 'b@example.com'), alias: 'First Choice'),
          _refusedAs(identityReasonAliasTaken),
        );

        final result = await call(
          caller,
          alias: 'Second Choice',
          at: _t0 + tipperLeaseTtl.inMilliseconds + 1,
        );
        final root = await readRoot(db);
        expect((root['AliasIndex'] as Map).keys, [
          aliasIndexKey('Second Choice'),
        ]);
        expect((root['AliasIndex'] as Map).values, [result.tipperId]);
        expectIdentityConsistent(root);
      }, skip: skip);
    });

    group('caller token', () {
      test('reads the verified claims and nothing from the request', () {
        final token = CallerToken.fromClaims('u1', {
          'email': ' Pat@Example.com ',
          'email_verified': true,
          'picture': 'https://example.com/p.png',
          'firebase': {'sign_in_provider': 'google.com'},
        });
        expect(token.email, 'Pat@Example.com');
        expect(token.emailVerified, true);
        expect(token.signInProvider, 'google.com');
        expect(token.pictureUrl, 'https://example.com/p.png');
        expect(token.isAnonymous, false);
      });

      test('missing or odd claims are not trusted', () {
        final token = CallerToken.fromClaims('u1', {
          'email': 7,
          'email_verified': 'true',
          'picture': 'http://insecure.example.com/p.png',
          'firebase': 'nope',
        });
        expect(token.email, isNull);
        expect(token.emailVerified, false);
        expect(token.pictureUrl, isNull);
        expect(CallerToken.fromClaims('u1', null).emailVerified, false);
        expect(
          CallerToken.fromClaims('u1', {
            'firebase': {'sign_in_provider': 'anonymous'},
          }).isAnonymous,
          true,
        );
      });
    });
  });
}
