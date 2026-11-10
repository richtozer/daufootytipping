// What the app does once the database is on the R2 rules, using data that the
// REAL callables wrote while the R1-compat rules were in force: the state the
// cutover will find. Every request here is one the client makes, with the same
// path and payload, under the rules the client will meet.
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/account_deletion.dart';
import 'package:daufootytipping/services/device_token_registrar.dart';
import 'package:daufootytipping/services/live_score_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/integration_support.dart';
import 'support/person.dart';

const String _comp = 'comp1';
const String _token = 'dXYZ:APA91bIntegration-0002_aaaaaaaaaaaaaaaa';

class _Account implements DeletableAccount {
  @override
  DateTime? get lastSignInTime => DateTime.now();

  @override
  Future<void> reauthenticate() async {}

  @override
  Future<void> delete() async {}
}

void main() {
  if (integrationSkipReason != null) {
    test('client integration tests', () {}, skip: integrationSkipReason);
    return;
  }

  late EmulatorDatabase database;
  late Person admin;
  late Person ann;
  late Person bob;
  late Tipper adminTipper;
  late Tipper annTipper;
  late Tipper bobTipper;

  setUpAll(() => database = EmulatorDatabase.fromEnvironment());

  Game game(String key) => Game(
    dbkey: key,
    league: League.nrl,
    homeTeam: Team(dbkey: 'home', name: 'Home', league: League.nrl),
    awayTeam: Team(dbkey: 'away', name: 'Away', league: League.nrl),
    location: 'Stadium',
    startTimeUTC: DateTime.now().toUtc(),
    fixtureRoundNumber: 1,
    fixtureMatchNumber: 1,
  );

  /// The write the app makes for a tip, as `GameTipViewModel.addTip` builds it.
  Map<String, Object?> tipUpdate(
    Tipper tipper,
    String gameKey,
    GameResult result,
  ) => {
    '${paths.tipsPathRoot}/$_comp/${tipper.dbkey}/$gameKey': Tip(
      dbkey: gameKey,
      game: game(gameKey),
      tipper: tipper,
      tip: result,
      submittedTimeUTC: DateTime.now().toUtc(),
    ).toJson(),
  };

  Future<DbResult> writeTip(
    Person person,
    Tipper as,
    String gameKey, [
    Tipper? forTipper,
  ]) => person.client.update(
    '/',
    tipUpdate(forTipper ?? as, gameKey, GameResult.a),
  );

  setUp(() async {
    await database.reset();
    await database.seedRunningApp();
    admin = Person(
      database,
      const Account(
        'uidAdmin000000000000000000001',
        email: 'admin@example.test',
      ),
    );
    ann = Person(
      database,
      const Account('uidAnn0000000000000000000001', email: 'ann@example.test'),
    );
    bob = Person(
      database,
      const Account('uidBob0000000000000000000002', email: 'bob@example.test'),
    );
    adminTipper = await admin.signUp('Admin');
    annTipper = await ann.signUp('Ann');
    bobTipper = await bob.signUp('Bob');
    await database.makeAdministrator(adminTipper.dbkey!);

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database.adminPatch('/', {
      '${paths.gamesPathRoot}/$_comp/upcoming/DateUtcEpochMs': now + 3600000,
      '${paths.gamesPathRoot}/$_comp/started/DateUtcEpochMs': now - 3600000,
      '${paths.gamesPathRoot}/$_comp/official/DateUtcEpochMs': now - 7200000,
      '${paths.gamesPathRoot}/$_comp/official/HomeTeamScore': 20,
      '${paths.gamesPathRoot}/$_comp/official/AwayTeamScore': 10,
      // Bob has already tipped both a started and an upcoming game.
      '${paths.tipsPathRoot}/$_comp/${bobTipper.dbkey}/started': {
        'r': 'b',
        't': now ~/ 1000 - 7200,
      },
      '${paths.tipsPathRoot}/$_comp/${bobTipper.dbkey}/upcoming': {
        'r': 'c',
        't': now ~/ 1000 - 60,
      },
    });

    // The cutover: from here the database is on R2.
    await database.useRules(Ruleset.r2);
  });

  group('signing in and the identity records', () {
    test('a linked tipper reads their own records, and signs in without asking the server', () async {
      final again = Person(database, ann.account);

      final tipper = await again.signIn();

      expect(tipper.dbkey, annTipper.dbkey);
      expect(again.invoker.calls, isEmpty);
    });

    test('and no one else\'s private record, nor the list of them', () async {
      expect(
        (await ann.client.get('${paths.tipperPrivatePath}/${bobTipper.dbkey}'))
            .denied,
        isTrue,
      );
      expect((await ann.client.get(paths.tipperPrivatePath)).denied, isTrue);
      expect(
        (await ann.client.get('${paths.authIndexPath}/${bob.account.uid}'))
            .denied,
        isTrue,
      );
    });

    test(
      'an administrator reads every private record, as the admin screens do',
      () async {
        final all = await admin.client.get(paths.tipperPrivatePath);

        expect(all.ok, isTrue);
        expect(
          all.map?.keys,
          containsAll([annTipper.dbkey, bobTipper.dbkey, adminTipper.dbkey]),
        );
      },
    );

    test('anyone with a session reads the public list of names', () async {
      final list = await ann.client.get(paths.tippersPath);

      expect(list.ok, isTrue);
      expect(
        list.map?.values.map((t) => (t as Map)['name']),
        containsAll(['Ann', 'Bob']),
      );
    });
  });

  group('tips', () {
    test('a tipper writes their own tip before kickoff', () async {
      expect((await writeTip(ann, annTipper, 'upcoming')).ok, isTrue);
    });

    test('and after kickoff the same write is refused: the rejection a queued tip meets', () async {
      expect((await writeTip(ann, annTipper, 'started')).denied, isTrue);
      expect((await writeTip(ann, annTipper, 'official')).denied, isTrue);
    });

    test('not for someone else, before or after kickoff', () async {
      expect(
        (await writeTip(ann, annTipper, 'upcoming', bobTipper)).denied,
        isTrue,
      );
    });

    test('an administrator may write a tip at any time, for anyone', () async {
      expect(
        (await writeTip(admin, adminTipper, 'started', annTipper)).ok,
        isTrue,
      );
    });

    test('a tipper reads their own tips by game, and as a whole', () async {
      await writeTip(ann, annTipper, 'upcoming');

      expect(
        (await ann.client.get(
          '${paths.tipsPathRoot}/$_comp/${annTipper.dbkey}/upcoming',
        )).ok,
        isTrue,
      );
      expect(
        (await ann.client.get(
          '${paths.tipsPathRoot}/$_comp/${annTipper.dbkey}',
        )).ok,
        isTrue,
      );
    });

    test('another tipper\'s tip is hidden until its game has started, then readable game by game', () async {
      final base = '${paths.tipsPathRoot}/$_comp/${bobTipper.dbkey}';

      expect((await ann.client.get('$base/upcoming')).denied, isTrue);
      final started = await ann.client.get('$base/started');
      expect(started.ok, isTrue);
      expect(started.map?['r'], 'b');
    });

    test('and never at the tipper\'s node or the competition\'s, which the drill-down avoids', () async {
      expect(
        (await ann.client.get(
          '${paths.tipsPathRoot}/$_comp/${bobTipper.dbkey}',
        )).denied,
        isTrue,
      );
      expect(
        (await ann.client.get('${paths.tipsPathRoot}/$_comp')).denied,
        isTrue,
      );
      expect(
        (await admin.client.get('${paths.tipsPathRoot}/$_comp')).ok,
        isTrue,
      );
    });
  });

  group('live scores', () {
    CrowdSourcedScore score(
      Tipper tipper, {
      ScoringTeam team = ScoringTeam.home,
    }) => CrowdSourcedScore(
      DateTime.now().toUtc(),
      team,
      tipper.dbkey!,
      12,
      false,
    );

    String historyPath(String gameKey, CrowdSourcedScore s) =>
        '${paths.statsPathRoot}/$_comp/${paths.liveScoresBackendRoot}/$gameKey/history/${liveScoreHistoryKey(s)}';

    Future<DbResult> submit(
      Person person,
      String gameKey,
      CrowdSourcedScore s, [
      Map<String, Object?>? entry,
    ]) => person.client.update('/', {
      historyPath(gameKey, s): entry ?? liveScoreHistoryEntry(s),
    });

    test('the entry the app builds is accepted for a started game', () async {
      final s = score(annTipper);

      final result = await submit(ann, 'started', s);

      expect(result.ok, isTrue);
      final stored = (await database.adminGet(historyPath('started', s))).map;
      expect(stored?['interimScore'], 12);
      expect(stored?['t'], isA<num>(), reason: 'the server\'s own clock');
    });

    test(
      'but not for a game that has not started, nor one with an official score',
      () async {
        expect(
          (await submit(ann, 'upcoming', score(annTipper))).denied,
          isTrue,
        );
        expect(
          (await submit(ann, 'official', score(annTipper))).denied,
          isTrue,
        );
      },
    );

    test('not for someone else', () async {
      expect((await submit(ann, 'started', score(bobTipper))).denied, isTrue);
    });

    test('and nothing beyond the four fields, nor the running score itself', () async {
      final s = score(annTipper);
      expect(
        (await submit(ann, 'started', s, {
          ...liveScoreHistoryEntry(s),
          'gameComplete': false,
        })).denied,
        isTrue,
      );
      expect(
        (await submit(ann, 'started', s, {
          ...liveScoreHistoryEntry(s),
          'submittedTimeUTC': 'now',
        })).denied,
        isTrue,
      );
      final current = await ann.client.update('/', {
        '${paths.statsPathRoot}/$_comp/${paths.liveScoresBackendRoot}/started/current':
            {'homeInterimScore': 99},
      });
      expect(current.denied, isTrue);
    });

    test('an entry cannot be overwritten', () async {
      final s = score(annTipper);
      await submit(ann, 'started', s);

      expect((await submit(ann, 'started', s)).denied, isTrue);
    });
  });

  group('the few other direct writes', () {
    test('a tipper changes their own photo, not another\'s', () async {
      expect(
        (await ann.client.put(
          '${paths.tippersPath}/${annTipper.dbkey}/photoURL',
          'https://example.test/a.png',
        )).ok,
        isTrue,
      );
      expect(
        (await ann.client.put(
          '${paths.tippersPath}/${bobTipper.dbkey}/photoURL',
          'https://example.test/a.png',
        )).denied,
        isTrue,
      );
    });

    test(
      'an administrator ticks who has paid; an ordinary tipper cannot',
      () async {
        final path =
            '${paths.tippersPath}/${annTipper.dbkey}/compsParticipatedIn';

        expect((await admin.client.put(path, [_comp])).ok, isTrue);
        expect((await ann.client.put(path, [_comp])).denied, isTrue);
      },
    );

    test(
      'the role the callable gave the administrator is what opens these doors',
      () async {
        // Promoted through the callable, not written by hand.
        await admin.identity.adminUpdateTipper(
          tipperId: bobTipper.dbkey!,
          role: TipperRole.admin,
        );

        expect((await bob.client.get(paths.tipperPrivatePath)).ok, isTrue);
      },
    );
  });

  group('the callables, once the database is on R2', () {
    test('the alias can still be changed', () async {
      final result = await ann.identity.updateTipperAlias('Annabel');

      expect(result.alias, 'Annabel');
      expect(
        (await ann.client.get('${paths.tippersPath}/${annTipper.dbkey}/name'))
            .body,
        'Annabel',
      );
    });

    test('a push token can still be registered and removed, though no client may touch the tokens', () async {
      final registrar = DeviceTokenRegistrar(identity: ann.identity);

      expect(await registrar.register(_token), isTrue);
      expect(
        (await ann.client.get('${paths.tokensPath}/${annTipper.dbkey}')).denied,
        isTrue,
      );
      await registrar.unregister(_token);

      expect(
        (await database.adminGet('${paths.tokensPath}/${annTipper.dbkey}'))
            .body,
        isNull,
      );
    });

    test('deleting the account ends the access first: unlinked, the tipper reads nothing of theirs', () async {
      final registrar = DeviceTokenRegistrar(identity: ann.identity);
      await registrar.register(_token);
      await writeTip(ann, annTipper, 'upcoming');

      final message = await AccountDeletion(
        identity: ann.identity,
        account: _Account(),
        unregisterPushToken: () => registrar.unregister(_token),
      ).run();

      expect(message, isNull);
      expect(
        (await ann.client.get('${paths.tipperPrivatePath}/${annTipper.dbkey}'))
            .denied,
        isTrue,
      );
      expect(
        (await ann.client.get(
          '${paths.tipsPathRoot}/$_comp/${annTipper.dbkey}',
        )).denied,
        isTrue,
      );
      expect((await writeTip(ann, annTipper, 'upcoming')).denied, isTrue);
    });
  });
}
