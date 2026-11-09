import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admin_update_tipper.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/identity/tipper_lease.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/identity_helpers.dart';
import '../support/identity_invariants.dart';

const int _t0 = 1700000000000;
const String _uidAdmin = 'uidAdmin000000000000000000001';
const String _uidPat = 'uidPat0000000000000000000002';
const String _uidSam = 'uidSam0000000000000000000003';
const Set<String> _admins = <String>{_uidAdmin};

void main() {
  final skip = emulatorSkipReason;

  group('adminUpdateTipper', () {
    late final RestDatabase db = openEmulatorDatabase();

    /// Alex, an administrator, and two ordinary tippers, Pat and Sam, all linked.
    IdentitySeed baseline() => IdentitySeed()
      ..tipper(
        'tA',
        name: 'Alex',
        authuid: _uidAdmin,
        logon: 'alex@example.com',
        email: 'alex@example.com',
        indexAccount: true,
      )
      ..tipper(
        't1',
        name: 'Pat',
        authuid: _uidPat,
        logon: 'pat@example.com',
        email: 'pat@example.com',
        indexAccount: true,
      )
      ..tipper(
        't2',
        name: 'Sam',
        authuid: _uidSam,
        logon: 'sam@example.com',
        email: 'sam@example.com',
        indexAccount: true,
      );

    Future<void> setRole(String id, String role) => db.ref('/').update({
      'TipperPrivate/$id/tipperRole': role,
      'AllTippers/$id/tipperRole': role,
    });

    Future<void> seed([IdentitySeed? seed]) async {
      await clearEmulatorDatabase(db);
      await db.ref('/').set((seed ?? baseline()).data);
      await setRole('tA', 'admin');
    }

    setUp(seed);

    Future<AdminUpdateTipperResult> update(
      AdminUpdateTipperRequest request, {
      String uid = _uidAdmin,
      IdentityMode mode = IdentityMode.coexist,
      int at = _t0,
      Checkpoint? checkpoint,
    }) => adminUpdateTipper(
      database: db,
      caller: callerToken(uid, 'x@example.com'),
      request: request,
      admission: admissionFor(mode: mode),
      adminUids: _admins,
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

    group('who may call it', () {
      test(
        'only an administrator; anyone else is refused and nothing is written',
        () async {
          await refusedWithoutWriting(
            () => update(
              const AdminUpdateTipperRequest(tipperId: 't2', name: 'Samuel'),
              uid: _uidPat,
            ),
            refusedAs('not_admin'),
          );
        },
        skip: skip,
      );

      test('an administrator who is not the tipper they change', () async {
        final result = await update(
          const AdminUpdateTipperRequest(tipperId: 't2', name: 'Samuel'),
        );
        expect(result.changed, ['name']);
      }, skip: skip);
    });

    group('a refusal changes nothing', () {
      test('a tipper who does not exist', () async {
        await refusedWithoutWriting(
          () => update(
            const AdminUpdateTipperRequest(tipperId: 'tNope', name: 'X'),
          ),
          throwsA(isA<NotFoundError>()),
        );
      }, skip: skip);

      test(
        'a record missing a half is not touched: it needs repair first',
        () async {
          await seed(baseline()..tipper('t9', name: 'Half', hasPrivate: false));
          await refusedWithoutWriting(
            () => update(
              const AdminUpdateTipperRequest(tipperId: 't9', name: 'Whole'),
            ),
            refusedAs('needs_audit'),
          );
        },
        skip: skip,
      );

      test('a name that is blank or too long', () async {
        await refusedWithoutWriting(
          () => update(
            const AdminUpdateTipperRequest(tipperId: 't2', name: '   '),
          ),
          refusedAs('invalid_alias'),
        );
        await refusedWithoutWriting(
          () =>
              update(AdminUpdateTipperRequest(tipperId: 't2', name: 'x' * 65)),
          refusedAs('invalid_alias'),
        );
      }, skip: skip);

      test('an email that is not an address', () async {
        await refusedWithoutWriting(
          () => update(
            const AdminUpdateTipperRequest(
              tipperId: 't2',
              email: 'not-an-email',
            ),
          ),
          refusedAs('invalid_email'),
        );
      }, skip: skip);

      test(
        'a name another tipper holds: and the email and role in the same request are not applied',
        () async {
          await refusedWithoutWriting(
            () => update(
              const AdminUpdateTipperRequest(
                tipperId: 't2',
                name: 'pat', // Pat's alias, in any case
                email: 'new@example.com',
                role: TipperRole.admin,
              ),
            ),
            refusedAs('alias_taken'),
          );
        },
        skip: skip,
      );
    });

    group('the name', () {
      test(
        'renames another tipper: the claim moves and only that tipper changes',
        () async {
          final result = await update(
            const AdminUpdateTipperRequest(tipperId: 't2', name: '  Samuel  '),
          );
          expect(result.tipperId, 't2');
          expect(result.changed, ['name']);

          final root = await readRoot(db);
          expect(rowAt(root, 'AllTippers', 't2')['name'], 'Samuel');
          expect(root['AliasIndex'], {
            aliasIndexKey('Alex'): 'tA',
            aliasIndexKey('Pat'): 't1',
            aliasIndexKey('Samuel'): 't2',
          });
          expect(rowAt(root, 'AllTippers', 't1')['name'], 'Pat');
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test(
        'a change of spelling that keeps the key only rewrites the name',
        () async {
          await update(
            const AdminUpdateTipperRequest(tipperId: 't2', name: 'SAM'),
          );
          final root = await readRoot(db);
          expect(rowAt(root, 'AllTippers', 't2')['name'], 'SAM');
          expect((root['AliasIndex'] as Map)[aliasIndexKey('Sam')], 't2');
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test('the name it already has changes nothing', () async {
        final before = canonical(await readRoot(db));
        final result = await update(
          const AdminUpdateTipperRequest(tipperId: 't2', name: 'Sam'),
        );
        expect(result.changed, isEmpty);
        expect(canonical(await readRoot(db)), before);
      }, skip: skip);
    });

    group('the email', () {
      test(
        'is written to the private record and, in the legacy modes, the public copy',
        () async {
          final result = await update(
            const AdminUpdateTipperRequest(
              tipperId: 't2',
              email: ' sam.new@example.com ',
            ),
          );
          expect(result.changed, ['email']);
          final root = await readRoot(db);
          expect(
            rowAt(root, 'TipperPrivate', 't2')['email'],
            'sam.new@example.com',
          );
          expect(
            rowAt(root, 'AllTippers', 't2')['email'],
            'sam.new@example.com',
          );
          expect(
            rowAt(root, 'TipperPrivate', 't2')['logon'],
            'sam@example.com',
            reason: 'the login address is a different thing and is not changed',
          );
          expect(
            (root['LogonIndex'] as Map).length,
            3,
            reason: 'no login claim moved',
          );
          expectIdentityConsistent(root);
        },
        skip: skip,
      );

      test('after the purge only the private record carries it', () async {
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
              't2',
              name: 'Sam',
              authuid: _uidSam,
              logon: 'sam@example.com',
              email: 'sam@example.com',
              indexAccount: true,
              legacyPublic: false,
            ),
        );
        await update(
          const AdminUpdateTipperRequest(
            tipperId: 't2',
            email: 'sam.new@example.com',
          ),
          mode: IdentityMode.finalShape,
        );
        final root = await readRoot(db);
        expect(
          rowAt(root, 'TipperPrivate', 't2')['email'],
          'sam.new@example.com',
        );
        expect(rowAt(root, 'AllTippers', 't2').containsKey('email'), false);
      }, skip: skip);
    });

    group('the role', () {
      test('promotes a tipper, in both halves', () async {
        final result = await update(
          const AdminUpdateTipperRequest(
            tipperId: 't2',
            role: TipperRole.admin,
          ),
        );
        expect(result.changed, ['role']);
        final root = await readRoot(db);
        expect(rowAt(root, 'TipperPrivate', 't2')['tipperRole'], 'admin');
        expect(rowAt(root, 'AllTippers', 't2')['tipperRole'], 'admin');
      }, skip: skip);

      test('demotes an administrator while another remains', () async {
        await setRole('t2', 'admin');
        final result = await update(
          const AdminUpdateTipperRequest(
            tipperId: 't2',
            role: TipperRole.tipper,
          ),
        );
        expect(result.changed, ['role']);
        expect(
          rowAt(await readRoot(db), 'TipperPrivate', 't2')['tipperRole'],
          'tipper',
        );
      }, skip: skip);

      test(
        'an administrator can demote themselves while another remains',
        () async {
          await setRole('t2', 'admin');
          await update(
            const AdminUpdateTipperRequest(
              tipperId: 'tA',
              role: TipperRole.tipper,
            ),
          );
          expect(
            rowAt(await readRoot(db), 'TipperPrivate', 'tA')['tipperRole'],
            'tipper',
          );
        },
        skip: skip,
      );

      test(
        'the last administrator cannot be demoted, not even by themselves',
        () async {
          await refusedWithoutWriting(
            () => update(
              const AdminUpdateTipperRequest(
                tipperId: 'tA',
                role: TipperRole.tipper,
              ),
            ),
            refusedAs('last_admin'),
          );
        },
        skip: skip,
      );

      test('the role it already has changes nothing', () async {
        final before = canonical(await readRoot(db));
        final result = await update(
          const AdminUpdateTipperRequest(
            tipperId: 'tA',
            role: TipperRole.admin,
          ),
        );
        expect(result.changed, isEmpty);
        expect(canonical(await readRoot(db)), before);
      }, skip: skip);
    });

    test('several fields at once are all applied', () async {
      final result = await update(
        const AdminUpdateTipperRequest(
          tipperId: 't2',
          name: 'Samuel',
          email: 'samuel@example.com',
          role: TipperRole.admin,
        ),
      );
      expect(result.changed, ['name', 'email', 'role']);
      final root = await readRoot(db);
      expect(rowAt(root, 'AllTippers', 't2')['name'], 'Samuel');
      expect(rowAt(root, 'TipperPrivate', 't2')['email'], 'samuel@example.com');
      expect(rowAt(root, 'TipperPrivate', 't2')['tipperRole'], 'admin');
      expectIdentityConsistent(root);
    }, skip: skip);

    test(
      'a crash after the name is finished by running the same request again',
      () async {
        const request = AdminUpdateTipperRequest(
          tipperId: 't2',
          name: 'Samuel',
          email: 'samuel@example.com',
          role: TipperRole.admin,
        );
        await expectLater(
          update(request, checkpoint: crashAfter('admin:name')),
          throwsA(isA<SimulatedCrash>()),
        );
        expect(
          rowAt(await readRoot(db), 'TipperPrivate', 't2')['email'],
          'sam@example.com',
          reason: 'the email and role had not been written',
        );

        final result = await update(
          request,
          at: _t0 + tipperLeaseTtl.inMilliseconds + 1000,
        );
        expect(result.changed, [
          'email',
          'role',
        ], reason: 'the name was already done');
        final root = await readRoot(db);
        expect(rowAt(root, 'AllTippers', 't2')['name'], 'Samuel');
        expect(
          rowAt(root, 'TipperPrivate', 't2')['email'],
          'samuel@example.com',
        );
        expect(rowAt(root, 'TipperPrivate', 't2')['tipperRole'], 'admin');
        expect(root['IdentityLocks'], isNull);
        expectIdentityConsistent(root);
      },
      skip: skip,
    );
  });
}
