import 'package:daufootytipping/services/unconfirmed_tips_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final DateTime now = DateTime.utc(2027, 3, 12, 6);
  final int future = now.add(const Duration(hours: 3)).millisecondsSinceEpoch;
  final int past = now
      .subtract(const Duration(hours: 3))
      .millisecondsSinceEpoch;

  UnconfirmedTip tip({
    String compKey = 'comp-1',
    String tipperKey = 'tipper-1',
    String gameKey = 'game-1',
    String choice = 'a',
    String gameLabel = 'Home v Away',
    int? kickoffUtcMs,
    int? queuedAtUtcMs,
  }) => UnconfirmedTip(
    compKey: compKey,
    tipperKey: tipperKey,
    gameKey: gameKey,
    choice: choice,
    gameLabel: gameLabel,
    kickoffUtcMs: kickoffUtcMs ?? future,
    queuedAtUtcMs:
        queuedAtUtcMs ??
        now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
  );

  UnconfirmedTipsService build() => UnconfirmedTipsService(clock: () => now);

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('remembering queued tips', () {
    test('keeps a queued tip across runs of the app', () async {
      await build().queued(tip());

      final List<UnconfirmedTip> later = await build().pending();

      expect(later, [tip()]);
    });

    test('a newer tip for the same game replaces the older one', () async {
      final service = build();
      await service.queued(tip(choice: 'a'));
      await service.queued(tip(choice: 'e'));

      expect((await service.pending()).map((t) => t.choice), ['e']);
    });

    test('forgets a tip the server confirmed', () async {
      final service = build();
      await service.queued(tip());

      await service.accepted(tip());

      expect(await service.pending(), isEmpty);
    });

    test(
      'a late confirmation of a replaced tip leaves the current one',
      () async {
        final service = build();
        final older = tip(
          choice: 'a',
          queuedAtUtcMs: now.millisecondsSinceEpoch - 60000,
        );
        final newer = tip(choice: 'e');
        await service.queued(older);
        await service.queued(newer);

        await service.accepted(older);

        expect(await service.pending(), [newer]);
      },
    );

    test('forgets a tip after two weeks, whatever happened to it', () async {
      final service = build();
      await service.queued(
        tip(
          queuedAtUtcMs: now
              .subtract(const Duration(days: 15))
              .millisecondsSinceEpoch,
        ),
      );

      expect(await service.pending(), isEmpty);
    });

    test('a damaged store is treated as empty, never thrown', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        UnconfirmedTipsService.storageKey: 'not json',
      });

      expect(await build().pending(), isEmpty);
    });
  });

  group('a queued tip the server rejects after the screen stopped waiting', () {
    test('tells the user which game, and forgets the tip', () async {
      final service = build();
      await service.queued(tip());
      var notified = 0;
      service.addListener(() => notified++);

      await service.rejected(tip());

      expect(service.notices, hasLength(1));
      expect(service.notices.single, contains('Home v Away'));
      expect(service.notices.single, contains('not counted'));
      expect(notified, 1);
      expect(await service.pending(), isEmpty);
    });

    test('says nothing for a tip a newer one has replaced', () async {
      final service = build();
      final older = tip(
        choice: 'a',
        queuedAtUtcMs: now.millisecondsSinceEpoch - 60000,
      );
      await service.queued(older);
      await service.queued(tip(choice: 'e'));

      await service.rejected(older);

      expect(service.notices, isEmpty);
      expect((await service.pending()).map((t) => t.choice), ['e']);
    });

    test(
      'each notice is handed over once, and one that arrives later is kept',
      () async {
        final service = build();
        await service.queued(tip(gameKey: 'game-1', gameLabel: 'First v One'));
        await service.rejected(
          tip(gameKey: 'game-1', gameLabel: 'First v One'),
        );

        final first = service.takeNotices();
        await service.queued(tip(gameKey: 'game-2', gameLabel: 'Second v Two'));
        await service.rejected(
          tip(gameKey: 'game-2', gameLabel: 'Second v Two'),
        );

        expect(first.single, contains('First v One'));
        expect(service.notices.single, contains('Second v Two'));
        expect(service.takeNotices(), hasLength(1));
        expect(service.takeNotices(), isEmpty);
      },
    );
  });

  group('settling the tips queued in an earlier run', () {
    Future<UnconfirmedTipsService> reconciled(
      List<UnconfirmedTip> queued,
      Map<String, String> onServer, {
      String compKey = 'comp-1',
      String tipperKey = 'tipper-1',
    }) async {
      final service = build();
      for (final queuedTip in queued) {
        await service.queued(queuedTip);
      }
      await service.reconcile(
        compKey: compKey,
        tipperKey: tipperKey,
        storedChoice: (gameKey) => onServer[gameKey],
      );
      return service;
    }

    test('a tip the server holds needs no notice', () async {
      final service = await reconciled(
        [tip(kickoffUtcMs: past)],
        {'game-1': 'a'},
      );

      expect(service.notices, isEmpty);
      expect(await service.pending(), isEmpty);
    });

    test('a tip for a game that has started, which the server never got, is reported', () async {
      final service = await reconciled([tip(kickoffUtcMs: past)], {});

      expect(service.notices.single, contains('Home v Away'));
      expect(service.notices.single, contains('never reached the server'));
      expect(await service.pending(), isEmpty);
    });

    test(
      'a different tip on the server for a started game is reported too',
      () async {
        final service = await reconciled(
          [tip(kickoffUtcMs: past)],
          {'game-1': 'e'},
        );

        expect(service.notices, hasLength(1));
      },
    );

    test('a tip for a game still to start stays queued, silently', () async {
      final service = await reconciled([tip(kickoffUtcMs: future)], {});

      expect(service.notices, isEmpty);
      expect(await service.pending(), hasLength(1));
    });

    test('another competition or another tipper is left alone', () async {
      final service = await reconciled([
        tip(compKey: 'comp-2', kickoffUtcMs: past),
        tip(tipperKey: 'tipper-2', kickoffUtcMs: past),
      ], {});

      expect(service.notices, isEmpty);
      expect(await service.pending(), hasLength(2));
    });
  });
}
