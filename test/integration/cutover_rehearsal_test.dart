// One rehearsal of the cutover and the rollback (DESIGN-database-rules-phase4.md,
// sections 8 and 9), on the local emulator, with the real server, the real
// rulesets, the real mode, purge and restore tools (compiled, as the owner runs
// them) and the app's own client classes.
//
// The story: a database as production has it (tippers made by the real callables,
// plus what 1.4.x clients leave behind), then cutover step A (freeze, R2 rules,
// coexist), the verification window with an administrator promoted and another
// demoted, step B (the purge, mode final), and finally the rollback to R1-compat.
// Anything that needs the Firebase Auth export (the final backfill) is stood in for
// by a write of the record it would build, and said so.
import 'dart:convert';
import 'dart:io';

import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/integration_support.dart';
import 'support/person.dart';

const String _comp = 'comp1';

class _Tool {
  const _Tool(this.code, this.out, this.err);

  final int code;
  final String out;
  final String err;

  String get text => '$out$err';
}

Future<_Tool> _run(String environmentVariable, List<String> arguments) async {
  final executable = Platform.environment[environmentVariable]!;
  final result = await Process.run(executable, arguments);
  return _Tool(result.exitCode, '${result.stdout}', '${result.stderr}');
}

void main() {
  if (integrationSkipReason != null) {
    test('client integration tests', () {}, skip: integrationSkipReason);
    return;
  }

  late EmulatorDatabase database;
  late Directory scratch;

  setUpAll(() async {
    database = EmulatorDatabase.fromEnvironment();
    scratch = await Directory.systemTemp.createTemp('cutover-rehearsal-');
  });

  tearDownAll(() => scratch.delete(recursive: true));

  Future<_Tool> mode(List<String> arguments) =>
      _run('IDENTITY_MODE_TOOL', [...arguments, '--project', 'rehearsal']);

  Future<void> setMode(String name) async {
    final result = await mode(['set', name, '--yes']);
    expect(result.code, 0, reason: 'mode $name: ${result.text}');
  }

  Future<_Tool> purge(List<String> arguments) =>
      _run('IDENTITY_PURGE_TOOL', [...arguments, '--project', 'rehearsal']);

  Future<_Tool> restore(List<String> arguments) =>
      _run('IDENTITY_RESTORE_TOOL', [...arguments, '--project', 'rehearsal']);

  Future<Map<String, dynamic>> tippersNow() async =>
      (await database.adminGet(paths.tippersPath)).map ?? {};

  Future<Map<String, dynamic>> privateNow() async =>
      (await database.adminGet(paths.tipperPrivatePath)).map ?? {};

  Future<void> setAggregator(String name) =>
      database.adminPut('${paths.serverConfigPath}/liveScores', {'mode': name});

  test(
    'cutover step A, the verification window, step B, and the rollback',
    timeout: const Timeout(Duration(minutes: 8)),
    () async {
      // ---- Before: a database as production has it -------------------------------
      await database.reset();
      await database.seedRunningApp();
      await setAggregator('shadow');

      final alex = Person(
        database,
        const Account(
          'uidAlex000000000000000000001',
          email: 'alex@example.test',
        ),
      );
      final ann = Person(
        database,
        const Account(
          'uidAnn0000000000000000000002',
          email: 'ann@example.test',
        ),
      );
      final bob = Person(
        database,
        const Account(
          'uidBob0000000000000000000003',
          email: 'bob@example.test',
        ),
      );
      final alexTipper = await alex.signUp('Alex');
      final annTipper = await ann.signUp('Ann');
      final bobTipper = await bob.signUp('Bob');
      await database.makeAdministrator(alexTipper.dbkey!);

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await database.adminPatch('/', {
        '${paths.daucompsPath}/$_comp/name': 'Comp 1',
        '${paths.gamesPathRoot}/$_comp/upcoming/DateUtcEpochMs': now + 3600000,
        '${paths.gamesPathRoot}/$_comp/started/DateUtcEpochMs': now - 3600000,
      });

      // What 1.4.x clients leave behind after the backfill:
      // - Ann signed in again from a 1.4.x client, which refreshes the PUBLIC login time.
      final annSignedInLater = DateTime.now().toUtc().add(
        const Duration(minutes: 5),
      );
      await database.adminPut(
        '${paths.tippersPath}/${annTipper.dbkey}/acctLoggedOnUTC',
        annSignedInLater.toIso8601String(),
      );
      // - Dee was made by a 1.4.x client: every identity field in the public record,
      //   and no private record or index entry at all.
      await database.adminPut('${paths.tippersPath}/tDee', {
        'name': 'Dee',
        'authuid': 'uidDee000000000000000000004',
        'tipperRole': 'tipper',
        'email': 'dee@example.test',
        'logon': 'dee@example.test',
        'isAnonymous': false,
        'acctCreatedUTC': '2026-10-30T00:00:00.000Z',
        'acctLoggedOnUTC': '2026-10-30T00:00:00.000Z',
      });
      // - Old records still carry the two legacy fields, and one tipper never gave an alias.
      await database.adminPatch('/', {
        '${paths.tippersPath}/${bobTipper.dbkey}/active': true,
        '${paths.tippersPath}/${bobTipper.dbkey}/tipperID': 'old-bob',
      });
      await database.adminPut('${paths.tippersPath}/tNoAlias123456', {
        'authuid': '',
        'tipperRole': 'tipper',
        'email': 'noalias@example.test',
        'logon': 'noalias@example.test',
        'isAnonymous': false,
      });
      await database.adminPut('${paths.tipperPrivatePath}/tNoAlias123456', {
        'tipperRole': 'tipper',
        'email': 'noalias@example.test',
        'logon': 'noalias@example.test',
        'isAnonymous': false,
      });

      stdout.writeln('--- step A');
      // ---- Step A: stop and drain, reconcile, R2 ---------------------------------
      await setMode('freeze');
      await database.useRules(Ruleset.freeze);

      expect(
        (await ann.client.put(
          '${paths.tippersPath}/${annTipper.dbkey}/name',
          'Hacked',
        )).denied,
        isTrue,
        reason: 'step A2: an identity write is refused once the freeze rules are in force',
      );
      expect(
        (await ann.client.put(
          '${paths.tippersPath}/${annTipper.dbkey}/email',
          'x@example.test',
        )).denied,
        isTrue,
        reason: 'step A2: and so is a contact change',
      );
      expect(
        (await ann.client.put(
          '${paths.tippersPath}/${annTipper.dbkey}/photoURL',
          'https://example.test/a.png',
        )).ok,
        isTrue,
        reason: 'step A: photos continue during the freeze',
      );
      final frozen = await ann.identity
          .updateTipperAlias('Annabel')
          .then<String>((_) => 'allowed', onError: (Object e) => 'refused');
      expect(
        frozen,
        'refused',
        reason: 'step A: the callables are refused while frozen',
      );

      // The purge must refuse while Dee is unresolved, and write nothing.
      final before = jsonEncode(await tippersNow());
      final blocked = await purge(['--out', '${scratch.path}/blocked.json']);
      expect(blocked.code, 1, reason: 'step A: ${blocked.text}');
      expect(blocked.err, contains('tDee'));
      expect(blocked.err, contains('no private record'));
      expect(blocked.text, isNot(contains('example.test')));
      expect(
        jsonEncode(await tippersNow()),
        before,
        reason: 'a blocked purge writes nothing',
      );

      // The final backfill pass would build Dee's private record and index entry from the
      // Auth export. Here its output is written directly (a stand-in for that tool).
      await database.adminPatch('/', {
        '${paths.tipperPrivatePath}/tDee': {
          'authuid': 'uidDee000000000000000000004',
          'tipperRole': 'tipper',
          'email': 'dee@example.test',
          'logon': 'dee@example.test',
          'isAnonymous': false,
          'acctCreatedUTC': '2026-10-30T00:00:00.000Z',
          'acctLoggedOnUTC': '2026-10-30T00:00:00.000Z',
        },
        '${paths.authIndexPath}/uidDee000000000000000000004': 'tDee',
      });

      await database.useRules(Ruleset.r2);
      await setMode('coexist');
      await setAggregator('active');

      stdout.writeln('--- verification window');
      // ---- The verification window, under R2 --------------------------------------
      final annAgain = Person(database, ann.account);
      final signedIn = await annAgain.signIn();
      expect(
        signedIn.dbkey,
        annTipper.dbkey,
        reason: 'window: a linked tipper signs in under R2',
      );
      expect(
        annAgain.invoker.calls,
        isEmpty,
        reason: 'window: without asking the server',
      );

      final dee = Person(
        database,
        const Account('uidDee000000000000000000004', email: 'dee@example.test'),
      );
      expect(
        (await dee.signIn()).name,
        'Dee',
        reason: 'window: the backfilled tipper signs in too',
      );

      // A newly promoted administrator gains access, in the functions and in the rules.
      Future<int> adminCallStatus(Person who) async {
        try {
          await who.identity.adminMergeTippers(
            originalId: bobTipper.dbkey!,
            targetId: annTipper.dbkey!,
            dryRun: true,
          );
          return 200;
        } on Object catch (e) {
          return '$e'.contains('not_admin') ? 403 : 500;
        }
      }

      expect(
        await adminCallStatus(bob),
        403,
        reason: 'window: Bob is not yet an administrator (functions)',
      );
      expect(
        (await bob.client.get(paths.tipperPrivatePath)).denied,
        isTrue,
        reason: 'window: nor (rules)',
      );
      expect(
        (await bob.client.put(
          '${paths.tippersPath}/${annTipper.dbkey}/compsParticipatedIn',
          [_comp],
        )).denied,
        isTrue,
      );

      await alex.identity.adminUpdateTipper(
        tipperId: bobTipper.dbkey!,
        role: TipperRole.admin,
      );

      expect(
        await adminCallStatus(bob),
        200,
        reason: 'window: promoted, Bob gains the admin callables at once',
      );
      expect(
        (await bob.client.get(paths.tipperPrivatePath)).ok,
        isTrue,
        reason: 'window: and the private records',
      );
      expect(
        (await bob.client.get('${paths.tipsPathRoot}/$_comp')).ok,
        isTrue,
        reason: 'window: and every tip',
      );
      expect(
        (await bob.client.put(
          '${paths.tippersPath}/${annTipper.dbkey}/compsParticipatedIn',
          [_comp],
        )).ok,
        isTrue,
        reason: 'window: and the paid ticks',
      );

      // ...and a demoted one loses it, in the same places.
      await alex.identity.adminUpdateTipper(
        tipperId: bobTipper.dbkey!,
        role: TipperRole.tipper,
      );

      expect(
        await adminCallStatus(bob),
        403,
        reason: 'window: demoted, Bob loses the admin callables',
      );
      expect(
        (await bob.client.get(paths.tipperPrivatePath)).denied,
        isTrue,
        reason: 'window: and the private records',
      );
      expect(
        (await bob.client.get('${paths.tipsPathRoot}/$_comp')).denied,
        isTrue,
        reason: 'window: and every tip',
      );
      expect(
        (await bob.client.put(
          '${paths.tippersPath}/${annTipper.dbkey}/compsParticipatedIn',
          [_comp],
        )).denied,
        isTrue,
        reason: 'window: and the paid ticks',
      );

      // The tipping the window exists to protect still works.
      final tip = await ann.client.update('/', {
        '${paths.tipsPathRoot}/$_comp/${annTipper.dbkey}/upcoming': {
          'r': 'a',
          't': now ~/ 1000,
        },
      });
      expect(tip.ok, isTrue, reason: 'window: a tip before kickoff');
      final late = await ann.client.update('/', {
        '${paths.tipsPathRoot}/$_comp/${annTipper.dbkey}/started': {
          'r': 'a',
          't': now ~/ 1000,
        },
      });
      expect(late.denied, isTrue, reason: 'window: and none after it');

      stdout.writeln('--- step B');
      // ---- Step B: drain, then purge ----------------------------------------------
      await setMode('freeze');
      final planned = await purge([]);
      expect(planned.code, 0, reason: 'step B plan: ${planned.text}');
      expect(planned.out, contains('Plan only'));
      expect(
        planned.out,
        contains('1 later login time(s)'),
        reason: 'Ann\'s sign-in from a 1.4.x client',
      );
      expect(
        planned.out,
        contains('1 tipper(s) are left with no public field'),
      );

      final snapshot = '${scratch.path}/all-tippers-before-purge.json';
      final purged = await purge(['--apply', '--snapshot', snapshot]);
      expect(purged.code, 0, reason: 'step B: ${purged.text}');
      expect(
        File(snapshot).existsSync(),
        isTrue,
        reason: 'step B: the snapshot is saved first',
      );
      expect(File(snapshot).readAsStringSync(), contains('ann@example.test'));
      await setMode('final');

      const identityFields = [
        'authuid',
        'tipperRole',
        'email',
        'logon',
        'isAnonymous',
        'acctCreatedUTC',
        'acctLoggedOnUTC',
        'active',
        'tipperID',
      ];
      final publicNow = await tippersNow();
      for (final entry in publicNow.entries) {
        for (final field in identityFields) {
          expect(
            (entry.value as Map).containsKey(field),
            isFalse,
            reason: 'step B: ${entry.key} still has $field',
          );
        }
      }
      expect(
        jsonEncode(publicNow),
        isNot(contains('@')),
        reason: 'step B: no email address left in public data',
      );
      expect(
        (publicNow['tNoAlias123456'] as Map)['name'],
        startsWith('Unnamed tipper'),
      );
      expect(
        (await privateNow())[annTipper.dbkey]['acctLoggedOnUTC'],
        annSignedInLater.toIso8601String(),
        reason: 'step B: Ann\'s later login time was kept',
      );
      expect(
        (await ann.client.get(paths.tippersPath)).ok,
        isTrue,
        reason: 'step B: the public list is still readable by any session',
      );

      // After the purge the app still works: the shape it was built for.
      final annPurged = await Person(database, ann.account).signIn();
      expect(annPurged.name, 'Ann');
      expect(
        annPurged.authuid,
        ann.account.uid,
        reason: 'step B: identity comes from the private record',
      );
      final alexPurged = await Person(database, alex.account).signIn();
      expect(
        alexPurged.tipperRole,
        TipperRole.admin,
        reason: 'step B: and so does the role',
      );
      expect(
        await adminCallStatus(alex),
        200,
        reason: 'step B: the administrator still administers',
      );
      expect(
        await adminCallStatus(bob),
        403,
        reason: 'step B: and the demoted one still cannot',
      );

      // A new sign-up in mode final leaves no personal data in the public record.
      final cy = Person(
        database,
        const Account('uidCy0000000000000000000005', email: 'cy@example.test'),
      );
      final cyTipper = await cy.signUp('Cy');
      final cyPublic = (await database.adminGet(
        '${paths.tippersPath}/${cyTipper.dbkey}',
      )).map!;
      expect(cyPublic.keys, [
        'name',
      ], reason: 'step B: a tipper made after the purge has only a name');
      expect((await privateNow()).containsKey(cyTipper.dbkey), isTrue);

      // The sweep: run again, it finds nothing.
      await setMode('freeze');
      final sweep = await purge([
        '--apply',
        '--snapshot',
        '${scratch.path}/sweep.json',
      ]);
      expect(sweep.code, 0, reason: sweep.text);
      expect(sweep.out, contains('Nothing to purge'));
      expect(
        File('${scratch.path}/sweep.json').existsSync(),
        isFalse,
        reason: 'a sweep needs no snapshot',
      );

      stdout.writeln('--- rollback');
      // ---- The rollback: freeze and drain, restore, R1-compat --------------------
      final restored = await restore(['--apply']);
      expect(restored.code, 0, reason: 'rollback: ${restored.text}');
      await database.useRules(Ruleset.r1Compat);
      await setMode('coexist');
      await setAggregator('shadow');

      final legacy = await tippersNow();
      for (final id in [
        alexTipper.dbkey!,
        annTipper.dbkey!,
        bobTipper.dbkey!,
        'tDee',
      ]) {
        final record = legacy[id] as Map;
        for (final field in [
          'authuid',
          'tipperRole',
          'email',
          'logon',
          'isAnonymous',
        ]) {
          expect(
            record.containsKey(field),
            isTrue,
            reason: 'rollback: $id has $field again for 1.4.x clients',
          );
        }
      }
      expect((legacy[annTipper.dbkey!] as Map)['email'], 'ann@example.test');
      expect(
        (legacy[annTipper.dbkey!] as Map)['acctLoggedOnUTC'],
        annSignedInLater.toIso8601String(),
        reason: 'rollback: the login time that was carried across the purge is restored with it',
      );
      expect((legacy[alexTipper.dbkey!] as Map)['tipperRole'], 'admin');
      expect(
        (legacy[bobTipper.dbkey!] as Map)['tipperRole'],
        'tipper',
        reason: 'rollback: Bob\'s demotion survives',
      );
      expect(
        (legacy[bobTipper.dbkey!] as Map).containsKey('active'),
        isFalse,
        reason: 'rollback: the legacy fields were removed on purpose and stay removed',
      );

      // The R2 client still works against R1-compat, which is why it is the rollback target.
      final annBack = await Person(database, ann.account).signIn();
      expect(
        annBack.name,
        'Ann',
        reason: 'rollback: the R2 client signs in under R1-compat',
      );
      expect(
        (await ann.client.put(
          '${paths.tippersPath}/${annTipper.dbkey}/photoURL',
          'https://example.test/b.png',
        )).ok,
        isTrue,
        reason: 'rollback: and a 1.4.x-style own-record write is allowed again',
      );
      expect(
        await adminCallStatus(alex),
        200,
        reason: 'rollback: the functions still know the administrator',
      );
      expect(await adminCallStatus(bob), 403);
    },
  );
}
