import 'dart:async';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockGamesViewModel extends Mock implements GamesViewModel {}

class _MockTippersViewModel extends Mock implements TippersViewModel {}

class _MockDatabaseReference extends Mock implements DatabaseReference {}

class _FakeSnapshot extends Fake implements DataSnapshot {
  _FakeSnapshot(this.value);

  @override
  final Object? value;

  @override
  bool get exists => value != null;
}

class _FakeEvent extends Fake implements DatabaseEvent {
  _FakeEvent(Object? value) : snapshot = _FakeSnapshot(value);

  @override
  final DataSnapshot snapshot;
}

DataSnapshot _snapshot(Object? value) => _FakeSnapshot(value);

DatabaseEvent _event(Object? value) => _FakeEvent(value);

/// A database that records which paths were listened to and lets a test push an
/// event, an error, or a one-off read to any of them.
class _FakeTipsDatabase {
  _FakeTipsDatabase() {
    when(() => root.child(any())).thenAnswer((invocation) {
      final path = invocation.positionalArguments.first as String;
      requestedPaths.add(path);
      final controller = controllers.putIfAbsent(
        path,
        () => StreamController<DatabaseEvent>.broadcast(),
      );
      final ref = _MockDatabaseReference();
      when(() => ref.onValue).thenAnswer((_) => controller.stream);
      when(() => ref.get()).thenAnswer((_) async => _snapshot(reads[path]));
      return ref;
    });
  }

  final root = _MockDatabaseReference();
  final requestedPaths = <String>[];
  final controllers = <String, StreamController<DatabaseEvent>>{};
  final reads = <String, Object?>{};

  Future<void> emit(String path, Object? value) async {
    await Future<void>.delayed(Duration.zero); // wait for the auth event
    controllers[path]!.add(_event(value));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> fail(String path) async {
    await Future<void>.delayed(Duration.zero);
    controllers[path]!.addError(Exception('permission-denied'));
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _MockGamesViewModel games;
  late _FakeTipsDatabase database;
  late Tipper tipper;
  late DAUComp comp;
  late Game started;
  late Game alsoStarted;

  String tipPath(Game game) =>
      '${p.tipsPathRoot}/${comp.dbkey}/${tipper.dbkey}/${game.dbkey}';

  Game buildGame(String dbkey) => Game(
    dbkey: dbkey,
    league: League.nrl,
    homeTeam: Team(dbkey: 'home', name: 'Home', league: League.nrl),
    awayTeam: Team(dbkey: 'away', name: 'Away', league: League.nrl),
    location: 'Stadium',
    startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
    fixtureRoundNumber: 1,
    fixtureMatchNumber: 1,
    scoring: Scoring(homeTeamScore: 10, awayTeamScore: 8),
  );

  TipsViewModel build({
    Duration retryDelay = TipsViewModel.defaultGameReadRetryDelay,
    Stream<bool> Function()? signedIn,
  }) => TipsViewModel.forTipperGames(
    _MockTippersViewModel(),
    comp,
    games,
    tipper,
    signedIn: signedIn ?? () => Stream.value(true), database: database.root,
    gameReadRetryDelay: retryDelay,
  );

  setUp(() {
    games = _MockGamesViewModel();
    when(() => games.addListener(any())).thenReturn(null);
    when(() => games.removeListener(any())).thenReturn(null);
    database = _FakeTipsDatabase();
    tipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: const [],
      authuid: '',
      name: 'Other tipper',
      email: null,
      tipperRole: TipperRole.tipper,
    );
    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );
    started = buildGame('game-1');
    alsoStarted = buildGame('game-2');
  });

  group('per-game tips (the only reads R2 allows for another tipper)', () {
    test('whole-tipper listener also closes and reopens with the session', () async {
      final auth = StreamController<bool>.broadcast();
      final tips = TipsViewModel.forTipper(
        _MockTippersViewModel(), comp, games, tipper,
        database: database.root, signedIn: () => auth.stream,
      );
      final path = '${p.tipsPathRoot}/${comp.dbkey}/${tipper.dbkey}';
      expect(database.requestedPaths, isEmpty);
      auth.add(true);
      await database.emit(path, null);
      await tips.initialLoadCompleted;
      auth.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(database.controllers[path]!.hasListener, isFalse);
      auth.add(true);
      await database.emit(path, null);
      expect(database.requestedPaths, [path, path]);
      tips.dispose();
      await auth.close();
    });
    test('closes on sign-out and reopens after the next sign-in', () async {
      final auth = StreamController<bool>.broadcast();
      final tips = build(signedIn: () => auth.stream);
      final loaded = tips.watchGames([started]);
      expect(database.requestedPaths, isEmpty);
      auth.add(true);
      await database.emit(tipPath(started), {'r': 'b', 't': 1700000000});
      await loaded;
      auth.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(database.controllers[tipPath(started)]!.hasListener, isFalse);
      auth.add(true);
      await database.emit(tipPath(started), {'r': 'd', 't': 1700000001});
      expect(database.requestedPaths, [tipPath(started), tipPath(started)]);
      expect((await tips.findTip(started, tipper))!.tip, GameResult.d);
      tips.dispose();
      await auth.close();
    });
    test(
      'listens at each game and never at the tipper or the competition',
      () async {
        final tips = build();
        addTearDown(tips.dispose);

        final loaded = tips.watchGames([started, alsoStarted]);
        await database.emit(tipPath(started), null);
        await database.emit(tipPath(alsoStarted), null);
        await loaded;

        expect(database.requestedPaths, [
          tipPath(started),
          tipPath(alsoStarted),
        ]);
        expect(
          database.requestedPaths,
          isNot(contains('${p.tipsPathRoot}/${comp.dbkey}/${tipper.dbkey}')),
        );
        expect(
          database.requestedPaths,
          isNot(contains('${p.tipsPathRoot}/${comp.dbkey}')),
        );
      },
    );

    test(
      'shows the tip, follows a change, and falls back when it goes',
      () async {
        final tips = build();
        addTearDown(tips.dispose);
        final loaded = tips.watchGames([started]);
        await database.emit(tipPath(started), {'r': 'a', 't': 1700000000});
        await loaded;

        expect((await tips.findTip(started, tipper))?.tip.name, 'a');

        await database.emit(tipPath(started), {'r': 'e', 't': 1700000100});
        expect((await tips.findTip(started, tipper))?.tip.name, 'e');

        await database.emit(tipPath(started), null);
        final fallback = await tips.findTip(started, tipper);
        expect(fallback?.submittedTimeUTC.millisecondsSinceEpoch, 0);
      },
    );

    test('reads the older stored shape too', () async {
      final tips = build();
      addTearDown(tips.dispose);
      final loaded = tips.watchGames([started]);
      await database.emit(tipPath(started), {
        'gameResult': 'b',
        'submittedTimeUTC': '2024-05-04T05:06:07.000Z',
      });
      await loaded;

      expect((await tips.findTip(started, tipper))?.tip.name, 'b');
    });

    test('stops listening to a game that is no longer wanted', () async {
      final tips = build();
      addTearDown(tips.dispose);
      final loaded = tips.watchGames([started, alsoStarted]);
      await database.emit(tipPath(started), {'r': 'a', 't': 1700000000});
      await database.emit(tipPath(alsoStarted), {'r': 'a', 't': 1700000000});
      await loaded;
      expect(database.controllers[tipPath(alsoStarted)]!.hasListener, isTrue);

      await tips.watchGames([started]);

      expect(database.controllers[tipPath(alsoStarted)]!.hasListener, isFalse);
      expect(database.controllers[tipPath(started)]!.hasListener, isTrue);
      expect(
        (await tips.findTip(
          alsoStarted,
          tipper,
        ))?.submittedTimeUTC.millisecondsSinceEpoch,
        0,
      );
    });

    test(
      'asking again for the same games adds nothing and notifies nobody',
      () async {
        final tips = build();
        addTearDown(tips.dispose);
        final loaded = tips.watchGames([started]);
        await database.emit(tipPath(started), {'r': 'a', 't': 1700000000});
        await loaded;
        var notifications = 0;
        tips.addListener(() => notifications++);

        await tips.watchGames([started]);

        expect(database.requestedPaths, [tipPath(started)]);
        expect(notifications, 0);
      },
    );

    test(
      'a game the server refuses to show does not hold up the others',
      () async {
        final tips = build();
        addTearDown(tips.dispose);
        final loaded = tips.watchGames([started, alsoStarted]);
        await database.fail(tipPath(started));
        await database.emit(tipPath(alsoStarted), {'r': 'e', 't': 1700000000});
        await loaded;

        expect(tips.isInitialLoadComplete, isTrue);
        expect((await tips.findTip(alsoStarted, tipper))?.tip.name, 'e');
        expect(
          (await tips.findTip(
            started,
            tipper,
          ))?.submittedTimeUTC.millisecondsSinceEpoch,
          0,
        );
      },
    );

    test(
      'a refresh reads each watched game once, still one game at a time',
      () async {
        final tips = build();
        addTearDown(tips.dispose);
        final loaded = tips.watchGames([started]);
        await database.emit(tipPath(started), null);
        await loaded;
        when(() => games.findGame(started.dbkey))
            .thenAnswer((_) async => started);
        database.reads[tipPath(started)] = {'r': 'c', 't': 1700000000};

        await tips.refreshFromServer();

        expect((await tips.findTip(started, tipper))?.tip.name, 'c');
        expect(
          database.requestedPaths.every((path) => path == tipPath(started)),
          isTrue,
        );
      },
    );

    test('says what was submitted, and null for a game never tipped', () async {
      final tips = build();
      addTearDown(tips.dispose);
      final loaded = tips.watchGames([started, alsoStarted]);
      await database.emit(tipPath(started), {'r': 'a', 't': 1700000000});
      await database.emit(tipPath(alsoStarted), null);
      await loaded;

      expect(
        tips.submittedTipForGame(started.dbkey, tipper)?.tip,
        GameResult.a,
      );
      expect(tips.submittedTipForGame(alsoStarted.dbkey, tipper), isNull);
      // findTip gives a started game with no tip a default, which is not a tip.
      expect((await tips.findTip(alsoStarted, tipper))?.tip, GameResult.d);
    });

    group('a game the server would not show yet', () {
      const quickRetry = Duration(milliseconds: 10);
      const longEnoughForARetry = Duration(milliseconds: 60);

      test('is tried afresh by the next request, not skipped', () async {
        final tips = build(retryDelay: const Duration(hours: 1));
        addTearDown(tips.dispose);
        final loaded = tips.watchGames([started]);
        await database.fail(tipPath(started));
        await loaded;
        expect(database.controllers[tipPath(started)]!.hasListener, isFalse);

        final again = tips.watchGames([started]);
        await database.emit(tipPath(started), {'r': 'a', 't': 1700000000});
        await again;

        expect(database.requestedPaths, [tipPath(started), tipPath(started)]);
        expect(database.controllers[tipPath(started)]!.hasListener, isTrue);
        expect((await tips.findTip(started, tipper))?.tip.name, 'a');
      });

      test(
        'is tried again on its own, and shows once the server agrees',
        () async {
          final tips = build(retryDelay: quickRetry);
          addTearDown(tips.dispose);
          final loaded = tips.watchGames([started]);
          await database.fail(tipPath(started));
          await loaded;

          await Future<void>.delayed(longEnoughForARetry);
          expect(database.requestedPaths, [tipPath(started), tipPath(started)]);
          await database.emit(tipPath(started), {'r': 'e', 't': 1700000000});

          expect((await tips.findTip(started, tipper))?.tip.name, 'e');
        },
      );

      test('is given up on after a few tries, until asked for again', () async {
        final tips = build(retryDelay: quickRetry);
        addTearDown(tips.dispose);
        final loaded = tips.watchGames([started]);
        await database.fail(tipPath(started));
        await loaded;
        for (
          var retry = 1;
          retry <= TipsViewModel.maxAutomaticGameReadRetries;
          retry++
        ) {
          await Future<void>.delayed(longEnoughForARetry);
          await database.fail(tipPath(started));
        }
        await Future<void>.delayed(longEnoughForARetry * 2);

        expect(
          database.requestedPaths,
          hasLength(1 + TipsViewModel.maxAutomaticGameReadRetries),
        );

        final asked = tips.watchGames([started]);
        await database.emit(tipPath(started), {'r': 'a', 't': 1700000000});
        await asked;
        expect((await tips.findTip(started, tipper))?.tip.name, 'a');
      });

      test('is not tried again once it is no longer wanted', () async {
        final tips = build(retryDelay: quickRetry);
        addTearDown(tips.dispose);
        final loaded = tips.watchGames([started]);
        await database.fail(tipPath(started));
        await loaded;
        await tips.watchGames(const []);

        await Future<void>.delayed(longEnoughForARetry);

        expect(database.requestedPaths, [tipPath(started)]);
      });

      test('is not tried again once the view model is disposed', () async {
        final tips = build(retryDelay: quickRetry);
        final loaded = tips.watchGames([started]);
        await database.fail(tipPath(started));
        await loaded;
        tips.dispose();

        await Future<void>.delayed(longEnoughForARetry);

        expect(database.requestedPaths, [tipPath(started)]);
      });
    });

    test('disposing closes every listener', () async {
      final tips = build();
      final loaded = tips.watchGames([started, alsoStarted]);
      await database.emit(tipPath(started), null);
      await database.emit(tipPath(alsoStarted), null);
      await loaded;

      tips.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(database.controllers[tipPath(started)]!.hasListener, isFalse);
      expect(database.controllers[tipPath(alsoStarted)]!.hasListener, isFalse);
    });

    test('a view model for the whole tipper node ignores watchGames', () async {
      final tips = TipsViewModel.forTipper(
        _MockTippersViewModel(),
        comp,
        games,
        tipper,
        signedIn: () => Stream.value(true), database: database.root,
        listenToTips: false,
      );
      addTearDown(tips.dispose);

      await tips.watchGames([started]);

      expect(database.requestedPaths, isEmpty);
    });
  });
}
