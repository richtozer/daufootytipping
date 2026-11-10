import 'dart:async';

import 'package:daufootytipping/services/unconfirmed_tips_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final DateTime now = DateTime.utc(2027, 3, 12, 6);
  final int future = now.add(const Duration(hours: 3)).millisecondsSinceEpoch;
  final int past = now
      .subtract(const Duration(hours: 3))
      .millisecondsSinceEpoch;

  // The tips below were made ten minutes ago.
  final int tippedAt =
      now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;

  UnconfirmedTip tip({
    String compKey = 'comp-1',
    String tipperKey = 'tipper-1',
    String gameKey = 'game-1',
    String choice = 'a',
    String gameLabel = 'Home v Away',
    int? submittedUtcSeconds,
    int? kickoffUtcMs,
    int? queuedAtUtcMs,
  }) => UnconfirmedTip(
    compKey: compKey,
    tipperKey: tipperKey,
    gameKey: gameKey,
    choice: choice,
    submittedUtcSeconds: submittedUtcSeconds ?? tippedAt,
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

      await service.answered(tip());

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

        await service.answered(older);

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

    test('a refusal is reported as confirmed', () async {
      final service = build();
      await service.queued(tip());

      await service.rejected(tip());

      expect(service.takeNotices().allConfirmed, isTrue);
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

        final first = service.takeNotices().messages;
        await service.queued(tip(gameKey: 'game-2', gameLabel: 'Second v Two'));
        await service.rejected(
          tip(gameKey: 'game-2', gameLabel: 'Second v Two'),
        );

        expect(first.single, contains('First v One'));
        expect(service.notices.single, contains('Second v Two'));
        expect(service.takeNotices().messages, hasLength(1));
        expect(service.takeNotices().messages, isEmpty);
      },
    );
  });

  group('operations that overlap', () {
    // A store that is slow to answer, so that without care two operations would
    // both read the list before either has written it back.
    UnconfirmedTipsService slow() => UnconfirmedTipsService(
      clock: () => now,
      preferences: () async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return SharedPreferences.getInstance();
      },
    );

    test('two tips queued at once are both kept', () async {
      final service = slow();

      await Future.wait([
        service.queued(tip(gameKey: 'game-1')),
        service.queued(tip(gameKey: 'game-2')),
        service.queued(tip(gameKey: 'game-3')),
      ]);

      expect((await service.pending()).map((t) => t.gameKey).toSet(), {
        'game-1',
        'game-2',
        'game-3',
      });
    });

    test('a tip queued while another is confirmed is not lost', () async {
      final service = slow();
      await service.queued(tip(gameKey: 'game-1'));

      await Future.wait([
        service.answered(tip(gameKey: 'game-1')),
        service.queued(tip(gameKey: 'game-2')),
      ]);

      expect((await service.pending()).map((t) => t.gameKey), ['game-2']);
    });

    test('a tip queued while another is refused is not lost', () async {
      final service = slow();
      await service.queued(tip(gameKey: 'game-1'));

      await Future.wait([
        service.rejected(tip(gameKey: 'game-1')),
        service.queued(tip(gameKey: 'game-2')),
      ]);

      expect((await service.pending()).map((t) => t.gameKey), ['game-2']);
      expect(service.notices, hasLength(1));
    });
  });

  group('what the tips listener shows of the queued tips', () {
    const settle = Duration(milliseconds: 20);
    const longerThanSettle = Duration(milliseconds: 120);

    late StreamController<bool?> connection;
    late Map<String, ShownTip> shown;
    late UnconfirmedTipsService service;

    ShownTip? Function(String) shownOnDevice() =>
        (gameKey) => shown[gameKey];

    Future<void> look({
      String compKey = 'comp-1',
      String tipperKey = 'tipper-1',
    }) => service.observe(
      compKey: compKey,
      tipperKey: tipperKey,
      shown: shownOnDevice(),
    );

    Future<void> connect(bool up) async {
      connection.add(up);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    setUp(() {
      connection = StreamController<bool?>.broadcast();
      shown = <String, ShownTip>{};
      service = UnconfirmedTipsService(
        clock: () => now,
        connectionStates: connection.stream,
        settleFor: settle,
      );
    });

    tearDown(() async {
      service.dispose();
      await connection.close();
    });

    test(
      'a tip the device shows is not taken as counted, nor as lost',
      () async {
        await connect(true);
        await service.queued(tip(kickoffUtcMs: past));
        shown['game-1'] = (choice: 'a', submittedUtcSeconds: tippedAt);

        await look();
        await Future<void>.delayed(longerThanSettle);

        expect(service.notices, isEmpty);
        expect(await service.pending(), hasLength(1));
      },
    );

    test(
      'a tip the device shows is left alone while the connection is down',
      () async {
        await connect(false);
        await service.queued(tip(kickoffUtcMs: past));
        shown['game-1'] = (choice: 'a', submittedUtcSeconds: tippedAt);

        await look();
        await Future<void>.delayed(longerThanSettle);

        expect(service.notices, isEmpty);
        expect(await service.pending(), hasLength(1));
      },
    );

    test('a missing tip is reported once it has stayed missing', () async {
      await connect(true);
      await service.queued(tip(kickoffUtcMs: past));
      var notified = 0;
      service.addListener(() => notified++);

      await look();
      expect(service.notices, isEmpty, reason: 'not on the first look');
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices.single, contains('Home v Away'));
      expect(service.notices.single, contains('could not confirm'));
      expect(service.notices.single, contains('before the game started'));
      expect(service.notices.single, isNot(contains('not counted')));
      expect(notified, 1);
      expect(await service.pending(), isEmpty);
    });

    test('a missing tip for a game still to start asks to tip again', () async {
      await connect(true);
      await service.queued(tip(kickoffUtcMs: future));

      await look();
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices.single, contains('could not confirm'));
      expect(service.notices.single, contains('tip again if it is missing'));
      expect(await service.pending(), isEmpty);
    });

    test('a missing tip is reported as unconfirmed, not as refused', () async {
      await connect(true);
      await service.queued(tip(kickoffUtcMs: past));
      await look();
      await Future<void>.delayed(longerThanSettle);

      expect(service.takeNotices().allConfirmed, isFalse);
    });

    test(
      'one refusal and one inference together are not all confirmed',
      () async {
        await connect(true);
        await service.queued(tip(gameKey: 'game-1', kickoffUtcMs: past));
        await service.queued(tip(gameKey: 'game-2', kickoffUtcMs: past));
        await look();
        await Future<void>.delayed(longerThanSettle);
        await service.queued(tip(gameKey: 'game-3', kickoffUtcMs: past));
        await service.rejected(tip(gameKey: 'game-3', kickoffUtcMs: past));

        final taken = service.takeNotices();

        expect(taken.messages, hasLength(3));
        expect(taken.allConfirmed, isFalse);
      },
    );

    test('a brief drop of the connection starts the wait again', () async {
      final slow = UnconfirmedTipsService(
        clock: () => now,
        connectionStates: connection.stream,
        settleFor: const Duration(milliseconds: 120),
      );
      addTearDown(slow.dispose);
      await connect(true);
      await slow.queued(tip(kickoffUtcMs: past));
      await slow.observe(
        compKey: 'comp-1',
        tipperKey: 'tipper-1',
        shown: shownOnDevice(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));
      await connect(false);
      await connect(true);
      // The first wait would be over by now; the new one has barely begun.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(slow.notices, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(slow.notices, hasLength(1));
    });

    test('a tip that comes back within the wait is not reported', () async {
      await connect(true);
      await service.queued(tip(kickoffUtcMs: past));
      await look();

      shown['game-1'] = (choice: 'a', submittedUtcSeconds: tippedAt);
      await look();
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices, isEmpty);
      expect(await service.pending(), hasLength(1));
    });

    test('nothing is decided while the connection is down', () async {
      await connect(false);
      await service.queued(tip(kickoffUtcMs: past));

      await look();
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices, isEmpty);
      expect(await service.pending(), hasLength(1));
    });

    test('a missing tip is reported once the connection returns', () async {
      await connect(false);
      await service.queued(tip(kickoffUtcMs: past));
      await look();
      await Future<void>.delayed(longerThanSettle);
      expect(service.notices, isEmpty);

      await connect(true);
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices, hasLength(1));
    });

    test('the connection dropping during the wait stops the report', () async {
      await connect(true);
      await service.queued(tip(kickoffUtcMs: past));
      await look();

      await connect(false);
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices, isEmpty);
      expect(await service.pending(), hasLength(1));
    });

    test(
      'a newer tip for the game replaces the queued one, silently',
      () async {
        await connect(true);
        await service.queued(tip(choice: 'a', kickoffUtcMs: past));
        shown['game-1'] = (choice: 'e', submittedUtcSeconds: tippedAt + 60);

        await look();
        await Future<void>.delayed(longerThanSettle);

        expect(service.notices, isEmpty);
        expect(await service.pending(), isEmpty);
      },
    );

    test(
      'an older tip showing instead means the queued one was refused',
      () async {
        await connect(true);
        await service.queued(tip(choice: 'a', kickoffUtcMs: past));
        shown['game-1'] = (choice: 'e', submittedUtcSeconds: tippedAt - 3600);

        await look();
        await Future<void>.delayed(longerThanSettle);

        expect(service.notices, hasLength(1));
        expect(await service.pending(), isEmpty);
      },
    );

    test('another competition or another tipper is left alone', () async {
      await connect(true);
      await service.queued(tip(compKey: 'comp-2', kickoffUtcMs: past));
      await service.queued(tip(tipperKey: 'tipper-2', kickoffUtcMs: past));

      await look();
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices, isEmpty);
      expect(await service.pending(), hasLength(2));
    });

    test('a tip refused in this run is not reported a second time', () async {
      await connect(true);
      await service.queued(tip(kickoffUtcMs: past));
      await look();

      await service.rejected(tip(kickoffUtcMs: past));
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices, hasLength(1));
    });

    test('a screen that has gone stops the wait', () async {
      await connect(true);
      await service.queued(tip(kickoffUtcMs: past));
      await look();

      service.stopObserving();
      await Future<void>.delayed(longerThanSettle);

      expect(service.notices, isEmpty);
      expect(await service.pending(), hasLength(1));
    });
  });
}
