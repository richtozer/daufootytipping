import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admin_merge_tippers.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/leases.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/identity/unlink_account.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/identity_helpers.dart';
import '../support/identity_invariants.dart';

const int _t0 = 1700000000000;
const String _uidAdmin = 'uidAdmin000000000000000000001';
const String _uidOld = 'uidOld0000000000000000000002';
const String _uidNew = 'uidNew0000000000000000000003';
const String _uidSam = 'uidSam0000000000000000000004';

/// The ordinary request: merge everything.
const AdminMergeTippersRequest _everything = AdminMergeTippersRequest(
  originalId: 'tNew',
  targetId: 'tOld',
  mergeTips: true,
  mergeLogon: true,
);

void main() {
  final skip = emulatorSkipReason;

  group('adminMergeTippers', () {
    late final RestDatabase db = openEmulatorDatabase();

    /// Pat, with history, on an old record (`tOld`); the same person on a new
    /// record (`tNew`) that a new sign-in method created; an administrator; and
    /// an unrelated tipper. Both tipped game g2 in c1.
    IdentitySeed baseline({
      String? oldAuthuid = _uidOld,
      bool indexOld = true,
      String? newAuthuid = _uidNew,
      bool indexNew = true,
      String? newPlaceholder,
      String oldLogon = 'pat.old@example.com',
      String newLogon = 'pat.new@example.com',
    }) {
      final seed = IdentitySeed()
        ..tipper(
          'tA',
          name: 'Alex',
          authuid: _uidAdmin,
          logon: 'alex@example.com',
          email: 'alex@example.com',
          indexAccount: true,
        )
        ..tipper(
          'tOld',
          name: 'Pat',
          authuid: oldAuthuid,
          logon: oldLogon,
          email: oldLogon,
          indexAccount: indexOld,
        )
        ..tipper(
          'tNew',
          name: 'Patricia',
          authuid: newAuthuid,
          logon: newLogon,
          email: newLogon,
          indexAccount: indexNew,
          placeholder: newPlaceholder,
        )
        ..tipper(
          't2',
          name: 'Sam',
          authuid: _uidSam,
          logon: 'sam@example.com',
          indexAccount: true,
        );
      seed.data['AllDAUComps'] = <String, Object?>{
        'c1': <String, Object?>{'name': '2026'},
        'c2': <String, Object?>{'name': '2025'},
      };
      seed.data['AllTips'] = <String, Object?>{
        'c1': <String, Object?>{
          'tOld': <String, Object?>{
            'g1': <String, Object?>{'r': 'a', 't': 1},
            'g2': <String, Object?>{'r': 'b', 't': 2},
          },
          'tNew': <String, Object?>{
            'g2': <String, Object?>{'r': 'c', 't': 9},
            'g3': <String, Object?>{'r': 'd', 't': 3},
          },
          't2': <String, Object?>{
            'g1': <String, Object?>{'r': 'a', 't': 4},
          },
        },
        'c2': <String, Object?>{
          'tNew': <String, Object?>{
            'h1': <String, Object?>{'r': 'a', 't': 5},
          },
        },
      };
      seed.data['AllTippersTokens'] = <String, Object?>{
        'tOld': <String, Object?>{'tokOld': '2026-03-01T00:00:00.000'},
        'tNew': <String, Object?>{'tokNew': '2026-03-02T00:00:00.000'},
      };
      seed.data['TokenOwners'] = <String, Object?>{
        'tokOld': <String, Object?>{'owner': 'tOld', 'seq': 1},
        'tokNew': <String, Object?>{'owner': 'tNew', 'seq': 1},
      };
      return seed;
    }

    Future<void> seed([IdentitySeed? seed]) async {
      await clearEmulatorDatabase(db);
      await db.ref('/').set((seed ?? baseline()).data);
      await db.ref('/').update({
        'TipperPrivate/tA/tipperRole': 'admin',
        'AllTippers/tA/tipperRole': 'admin',
      });
    }

    setUp(seed);

    Future<AdminMergeTippersResult> merge(
      AdminMergeTippersRequest request, {
      String uid = _uidAdmin,
      IdentityMode mode = IdentityMode.coexist,
      int at = _t0,
      Checkpoint? checkpoint,
    }) => adminMergeTippers(
      database: db,
      caller: callerToken(uid, 'x@example.com'),
      request: request,
      admission: admissionFor(mode: mode),
      nowMs: () => at,
      checkpoint: checkpoint,
    );

    Future<void> refusedWithoutWriting(
      Future<Object?> Function() action,
      Matcher matcher,
    ) async {
      final before = canonical(await readRoot(db));
      await expectLater(action(), matcher);
      expect(
        canonical(await readRoot(db)),
        before,
        reason: 'a refused request must not write',
      );
    }

    group('the usual merge: a new sign-in record into the old one with history', () {
      test(
        'moves the tips, login, account, tokens and claims, and removes the original',
        () async {
          final result = await merge(_everything);
          expect(result.targetId, 'tOld');
          expect(result.tipsMoved, 3);
          expect(result.tipsReplaced, 1, reason: 'both tipped g2 in c1');
          expect(result.loginMoved, true);
          expect(result.accountMoved, true);
          expect(result.dryRun, false);

          final root = await readRoot(db);

          // The original is gone, both halves.
          expect(rowAt(root, 'AllTippers', 'tNew'), isEmpty);
          expect(rowAt(root, 'TipperPrivate', 'tNew'), isEmpty);

          // Tips: the original's replace the target's for a shared game; nothing is lost otherwise.
          final c1 = (root['AllTips'] as Map)['c1'] as Map;
          expect((c1['tOld'] as Map).keys.toSet(), {'g1', 'g2', 'g3'});
          expect(((c1['tOld'] as Map)['g2'] as Map)['r'], 'c');
          expect(c1.containsKey('tNew'), false);
          expect((c1['t2'] as Map).keys, ['g1'], reason: 'Sam is untouched');
          final c2 = (root['AllTips'] as Map)['c2'] as Map;
          expect((c2['tOld'] as Map).keys, ['h1']);
          expect(c2.containsKey('tNew'), false);

          // The login address: the target has it, and its old one is released.
          expect(
            rowAt(root, 'TipperPrivate', 'tOld')['logon'],
            'pat.new@example.com',
          );
          expect(
            rowAt(root, 'AllTippers', 'tOld')['logon'],
            'pat.new@example.com',
          );
          final logons = root['LogonIndex'] as Map;
          expect(logons[logonIndexKey('pat.new@example.com')], 'tOld');
          expect(
            logons.containsKey(logonIndexKey('pat.old@example.com')),
            false,
          );

          // The account: the new one now reaches the old record; the old one no longer does.
          final authIndex = root['AuthIndex'] as Map;
          expect(authIndex[_uidNew], 'tOld');
          expect(authIndex.containsKey(_uidOld), false);
          expect(rowAt(root, 'TipperPrivate', 'tOld')['authuid'], _uidNew);
          expect(rowAt(root, 'AllTippers', 'tOld')['authuid'], _uidNew);

          // The name: the target keeps its own, and the original's alias is free.
          expect(rowAt(root, 'AllTippers', 'tOld')['name'], 'Pat');
          final aliases = root['AliasIndex'] as Map;
          expect(aliases[aliasIndexKey('Pat')], 'tOld');
          expect(aliases.containsKey(aliasIndexKey('Patricia')), false);

          // Push tokens, and who owns them.
          final tokens = (root['AllTippersTokens'] as Map);
          expect((tokens['tOld'] as Map).keys.toSet(), {'tokOld', 'tokNew'});
          expect(tokens.containsKey('tNew'), false);
          expect(
            ((root['TokenOwners'] as Map)['tokNew'] as Map)['owner'],
            'tOld',
          );

          expect(root['IdentityLocks'], isNull);
          expectIdentityConsistent(root);
          expectTokensConsistent(root);
        },
        skip: skip,
      );

      test('a dry run reports the same counts and changes nothing', () async {
        final before = canonical(await readRoot(db));
        final plan = await merge(
          AdminMergeTippersRequest(
            originalId: 'tNew',
            targetId: 'tOld',
            mergeTips: true,
            mergeLogon: true,
            dryRun: true,
          ),
        );
        expect(plan.dryRun, true);
        expect(plan.tipsMoved, 3);
        expect(plan.tipsReplaced, 1);
        expect(plan.loginMoved, true);
        expect(plan.accountMoved, true);
        expect(canonical(await readRoot(db)), before);
      }, skip: skip);

      test(
        'without the options, the tips and the login stay where they are',
        () async {
          final result = await merge(
            const AdminMergeTippersRequest(
              originalId: 'tNew',
              targetId: 'tOld',
            ),
          );
          expect(result.tipsMoved, 0);
          expect(result.loginMoved, false);
          expect(result.accountMoved, true, reason: 'the account always moves');

          final root = await readRoot(db);
          expect(
            ((root['AllTips'] as Map)['c1'] as Map).containsKey('tNew'),
            true,
            reason: 'the original\'s tips are left where they are',
          );
          expect(
            rowAt(root, 'TipperPrivate', 'tOld')['logon'],
            'pat.old@example.com',
          );
          final logons = root['LogonIndex'] as Map;
          expect(logons[logonIndexKey('pat.old@example.com')], 'tOld');
          expect(
            logons.containsKey(logonIndexKey('pat.new@example.com')),
            false,
            reason: 'the original\'s login claim is released with it',
          );
          expect(rowAt(root, 'TipperPrivate', 'tNew'), isEmpty);
        },
        skip: skip,
      );
    });

    group('accounts', () {
      test(
        'an original with no account (only a placeholder) leaves the target\'s link alone',
        () async {
          // A placeholder that would pass for a database key, so only the audit's
          // record of it says it is not an account.
          await seed(
            baseline(
              newAuthuid: 'legacyPlaceholder1',
              indexNew: false,
              newPlaceholder: 'legacyPlaceholder1',
            ),
          );
          final result = await merge(_everything);
          expect(result.accountMoved, false);
          final root = await readRoot(db);
          expect((root['AuthIndex'] as Map)[_uidOld], 'tOld');
          expect(rowAt(root, 'TipperPrivate', 'tOld')['authuid'], _uidOld);
          expect(
            root['Placeholders'] == null ||
                !(root['Placeholders'] as Map).containsKey('tNew'),
            true,
          );
        },
        skip: skip,
      );

      test('a target with no account takes the original\'s', () async {
        await seed(baseline(oldAuthuid: null, indexOld: false));
        final result = await merge(_everything);
        expect(result.accountMoved, true);
        final root = await readRoot(db);
        expect((root['AuthIndex'] as Map)[_uidNew], 'tOld');
        expect(rowAt(root, 'TipperPrivate', 'tOld')['authuid'], _uidNew);
        expectIdentityConsistent(root);
      }, skip: skip);

      test(
        'after the purge only the private record carries the link',
        () async {
          await seed(
            IdentitySeed()
              ..tipper(
                'tA',
                name: 'Alex',
                authuid: _uidAdmin,
                logon: 'alex@example.com',
                indexAccount: true,
              )
              ..tipper(
                'tOld',
                name: 'Pat',
                authuid: _uidOld,
                logon: 'pat.old@example.com',
                indexAccount: true,
                legacyPublic: false,
              )
              ..tipper(
                'tNew',
                name: 'Patricia',
                authuid: _uidNew,
                logon: 'pat.new@example.com',
                indexAccount: true,
                legacyPublic: false,
              ),
          );
          await merge(
            const AdminMergeTippersRequest(
              originalId: 'tNew',
              targetId: 'tOld',
              mergeLogon: true,
            ),
            mode: IdentityMode.finalShape,
          );
          final root = await readRoot(db);
          expect(rowAt(root, 'TipperPrivate', 'tOld')['authuid'], _uidNew);
          expect(
            rowAt(root, 'AllTippers', 'tOld').containsKey('authuid'),
            false,
          );
          expect(rowAt(root, 'AllTippers', 'tOld').containsKey('logon'), false);
          expect((root['AuthIndex'] as Map)[_uidNew], 'tOld');
        },
        skip: skip,
      );
    });

    group('duplicates that share a login address or an alias', () {
      test(
        'the same login on both records, held by the target: the target keeps the claim',
        () async {
          await seed(
            baseline(
              oldLogon: 'same@example.com',
              newLogon: 'same@example.com',
            ),
          );
          await merge(_everything);
          final logons = (await readRoot(db))['LogonIndex'] as Map;
          expect(logons[logonIndexKey('same@example.com')], 'tOld');
        },
        skip: skip,
      );

      test(
        'the same login on both records, held by the original: it passes to the target',
        () async {
          await seed(
            baseline(
              oldLogon: 'same@example.com',
              newLogon: 'same@example.com',
            ),
          );
          await db
              .ref('LogonIndex/${logonIndexKey('same@example.com')}')
              .set('tNew');
          await merge(_everything);
          final root = await readRoot(db);
          expect(
            (root['LogonIndex'] as Map)[logonIndexKey('same@example.com')],
            'tOld',
          );
          expect(
            rowAt(root, 'TipperPrivate', 'tOld')['logon'],
            'same@example.com',
          );
        },
        skip: skip,
      );

      test(
        'the same alias on both records, held by the original: it passes to the target',
        () async {
          await seed(baseline());
          await db
              .ref('AllTippers/tNew/name')
              .set('Pat'); // the same alias as the target
          await db.ref('AliasIndex/${aliasIndexKey('Patricia')}').remove();
          await db.ref('AliasIndex/${aliasIndexKey('Pat')}').set('tNew');
          await merge(_everything);
          final root = await readRoot(db);
          expect((root['AliasIndex'] as Map)[aliasIndexKey('Pat')], 'tOld');
          expect(rowAt(root, 'AllTippers', 'tOld')['name'], 'Pat');
        },
        skip: skip,
      );
    });

    group('a clash with a third tipper is refused before anything moves', () {
      const preview = AdminMergeTippersRequest(
        originalId: 'tNew',
        targetId: 'tOld',
        mergeTips: true,
        mergeLogon: true,
        dryRun: true,
      );

      test(
        'the login address is already held by a third tipper: the preview and the merge both refuse',
        () async {
          await db
              .ref('LogonIndex/${logonIndexKey('pat.new@example.com')}')
              .set('t2');
          await refusedWithoutWriting(
            () => merge(preview),
            refusedAs('claimed'),
          );
          await refusedWithoutWriting(
            () => merge(_everything),
            refusedAs('claimed'),
          );

          final tips = (await readRoot(db))['AllTips'] as Map;
          expect(((tips['c1'] as Map)['tOld'] as Map).keys.toSet(), {
            'g1',
            'g2',
          }, reason: 'no tip has moved');
          expect((tips['c1'] as Map).containsKey('tNew'), true);
        },
        skip: skip,
      );

      test(
        'the same state is no clash when the login address is not being moved',
        () async {
          await db
              .ref('LogonIndex/${logonIndexKey('pat.new@example.com')}')
              .set('t2');
          final result = await merge(
            const AdminMergeTippersRequest(
              originalId: 'tNew',
              targetId: 'tOld',
              mergeTips: true,
            ),
          );
          expect(result.tipsMoved, 3);
          expect(
            ((await readRoot(db))['LogonIndex'] as Map)[logonIndexKey(
              'pat.new@example.com',
            )],
            't2',
            reason: 'the third tipper keeps what is theirs',
          );
        },
        skip: skip,
      );

      test(
        'the account is already held by a third tipper: the preview and the merge both refuse',
        () async {
          await db.ref('AuthIndex/$_uidNew').set('t2');
          await refusedWithoutWriting(
            () => merge(preview),
            refusedAs('claimed'),
          );
          await refusedWithoutWriting(
            () => merge(_everything),
            refusedAs('claimed'),
          );
        },
        skip: skip,
      );

      test('the preview of a merge with no clash still goes through', () async {
        final plan = await merge(preview);
        expect(plan.dryRun, true);
        expect(plan.tipsMoved, 3);
      }, skip: skip);
    });

    group('a refusal changes nothing', () {
      test('only an administrator may merge', () async {
        await refusedWithoutWriting(
          () => merge(_everything, uid: _uidSam),
          refusedAs('not_admin'),
        );
      }, skip: skip);

      test('a tipper cannot be merged into itself', () async {
        await refusedWithoutWriting(
          () => merge(
            const AdminMergeTippersRequest(
              originalId: 'tOld',
              targetId: 'tOld',
            ),
          ),
          throwsA(isA<InvalidArgumentError>()),
        );
      }, skip: skip);

      test('either tipper missing', () async {
        await refusedWithoutWriting(
          () => merge(
            const AdminMergeTippersRequest(
              originalId: 'tNope',
              targetId: 'tOld',
            ),
          ),
          throwsA(isA<NotFoundError>()),
        );
        await refusedWithoutWriting(
          () => merge(
            const AdminMergeTippersRequest(
              originalId: 'tNew',
              targetId: 'tNope',
            ),
          ),
          throwsA(isA<NotFoundError>()),
        );
      }, skip: skip);

      test('a record missing a half needs repair first', () async {
        await seed(
          baseline()..tipper('tHalf', name: 'Half', hasPrivate: false),
        );
        await refusedWithoutWriting(
          () => merge(
            const AdminMergeTippersRequest(
              originalId: 'tHalf',
              targetId: 'tOld',
            ),
          ),
          refusedAs('needs_audit'),
        );
      }, skip: skip);

      test(
        'a tipper being changed by someone else makes the merge wait: busy',
        () async {
          await acquireLease(
            db.ref('IdentityLocks/tOld'),
            owner: 'someone-else',
            nowMs: _t0,
            ttl: const Duration(minutes: 5),
          );
          final before = canonical(await readRoot(db));
          await expectLater(merge(_everything), refusedAs('busy'));
          expect(canonical(await readRoot(db)), before);
        },
        skip: skip,
      );
    });

    test(
      'the original being changed by someone else, such as a sign-in, makes the merge wait too',
      () async {
        await acquireLease(
          db.ref('IdentityLocks/tNew'),
          owner: 'someone-else',
          nowMs: _t0,
          ttl: const Duration(minutes: 5),
        );
        final before = canonical(await readRoot(db));
        await expectLater(merge(_everything), refusedAs('busy'));
        expect(canonical(await readRoot(db)), before);
      },
      skip: skip,
    );

    test(
      'a merge cut short at any step, then run again, ends exactly as one that was not',
      () async {
        await merge(_everything);
        final expected = canonical(await readRoot(db));

        const steps = <String>[
          'merge:tips',
          'merge:tokens',
          'merge:logon',
          'merge:old-account',
          'merge:authuid',
          'merge:index',
          'merge:claims',
        ];
        for (final step in steps) {
          await seed();
          await expectLater(
            merge(_everything, checkpoint: crashAfter(step)),
            throwsA(isA<SimulatedCrash>()),
            reason: step,
          );
          final result = await merge(
            _everything,
            at: _t0 + tipperLeaseTtl.inMilliseconds + 1000,
          );
          expect(result.dryRun, false, reason: step);
          expect(
            canonical(await readRoot(db)),
            expected,
            reason: 'after $step',
          );
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    group('a person who deleted their account and then signed up again', () {
      /// Pat deletes the account on `tOld` (which has the history) through the
      /// real deletion, after the app has removed the push token, and then
      /// signs up again as `tNew`.
      Future<void> patDeletesTheOldAccount() async {
        await db.ref('/').update(<String, Object?>{
          'AllTippersTokens/tOld': null,
          'TokenOwners/tokOld': null,
        });
        await unlinkMyAccount(
          database: db,
          caller: callerToken(_uidOld, 'pat.old@example.com'),
          admission: admissionFor(mode: IdentityMode.coexist),
          nowMs: () => _t0,
        );
      }

      test(
        'merging the deleted record into the new one gives the new one the history and nothing else',
        () async {
          await patDeletesTheOldAccount();
          const request = AdminMergeTippersRequest(
            originalId: 'tOld',
            targetId: 'tNew',
            mergeTips: true,
            mergeLogon: true,
          );

          final plan = await merge(
            const AdminMergeTippersRequest(
              originalId: 'tOld',
              targetId: 'tNew',
              mergeTips: true,
              mergeLogon: true,
              dryRun: true,
            ),
          );
          expect(plan.tipsMoved, 2);
          expect(plan.tipsReplaced, 1, reason: 'both tipped g2 in c1');
          expect(plan.loginMoved, false, reason: 'the deleted record has none');
          expect(plan.accountMoved, false, reason: 'nor an account');

          final result = await merge(request);
          expect(result.tipsMoved, 2);
          expect(result.loginMoved, false);
          expect(result.accountMoved, false);

          final root = await readRoot(db);
          expect(rowAt(root, 'AllTippers', 'tOld'), isEmpty);
          expect(rowAt(root, 'TipperPrivate', 'tOld'), isEmpty);

          final c1 = (root['AllTips'] as Map)['c1'] as Map;
          expect((c1['tNew'] as Map).keys.toSet(), {'g1', 'g2', 'g3'});
          expect(
            ((c1['tNew'] as Map)['g2'] as Map)['r'],
            'b',
            reason: 'the deleted record\'s tip wins a shared game, as before',
          );
          expect(c1.containsKey('tOld'), false);
          final c2 = (root['AllTips'] as Map)['c2'] as Map;
          expect((c2['tNew'] as Map).keys, ['h1'], reason: 'kept');

          // The new record keeps its own name, login and account.
          expect(rowAt(root, 'AllTippers', 'tNew')['name'], 'Patricia');
          expect(
            rowAt(root, 'TipperPrivate', 'tNew')['logon'],
            'pat.new@example.com',
          );
          expect(rowAt(root, 'TipperPrivate', 'tNew')['authuid'], _uidNew);
          expect((root['AuthIndex'] as Map)[_uidNew], 'tNew');
          expect(
            rowAt(root, 'TipperPrivate', 'tNew').containsKey(
              tipperAccountDeletedField,
            ),
            false,
            reason: 'the person is not a deleted tipper',
          );
          expect(
            (root['AliasIndex'] as Map)[aliasIndexKey('Patricia')],
            'tNew',
          );
          expect(root['IdentityLocks'], isNull);
          expectIdentityConsistent(root);
          expectTokensConsistent(root);
        },
        skip: skip,
      );
    });
  });
}
