import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/live_scores/live_score_aggregation.dart';
import 'package:dart_functions/rtdb/emulator_admin_client.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// The M5 live-score wiring, end to end on the local emulators: a write to the
/// database emulator fires the real TypeScript trigger, which posts the real
/// command (with the secret) to the real Dart worker, which runs the aggregator
/// and, for a change to `current`, the existing scoring.
///
/// Run it with `scripts/test-live-score-wiring.sh`, which starts the Database and
/// Functions emulators inside the isolation boundary and sets the variables
/// below. On its own it is skipped, so the ordinary `dart test` runs are
/// unaffected.
final String? _skip = Platform.environment['LIVE_SCORE_WIRING_E2E'] == '1'
    ? null
    : 'needs scripts/test-live-score-wiring.sh';

String _env(String name) => Platform.environment[name] ?? '';

const String _region = 'asia-southeast1';
const String _game = 'nrl-01-001';
final DateTime _kickoff = DateTime.utc(2027, 3, 7, 2, 30);

/// How long to wait for something that should happen, and for something that
/// should *not* to have had its chance.
final Duration _patience = Duration(
  seconds: int.tryParse(_env('LIVE_SCORE_WIRING_PATIENCE')) ?? 90,
);
const Duration _quiet = Duration(seconds: 5);

/// What the Dart worker has logged about the aggregator, read from the emulators'
/// console output (the harness tees it to a file). The Functions emulator prints
/// each line of the worker's output once, prefixed with `>`. Lines name
/// competitions, games and counts, never people.
class _AggregatorLog {
  _AggregatorLog(this._path);

  final String _path;

  static final RegExp _line = RegExp(
    r'^>\s+\[liveScores\] ([a-z ]+?) comp=(\S+) game=(\S+)',
    multiLine: true,
  );

  /// The verbs ("shadow", "wrote", "skipped", ...) logged for [comp], in order.
  List<String> verbs(String comp) {
    final file = File(_path);
    if (!file.existsSync()) {
      return const <String>[];
    }
    return <String>[
      for (final match in _line.allMatches(file.readAsStringSync()))
        if (match.group(2) == comp) match.group(1)!,
    ];
  }
}

Future<void> _until(
  FutureOr<bool> Function() condition,
  String what, {
  Duration? timeout,
}) async {
  final deadline = DateTime.now().add(timeout ?? _patience);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Gave up waiting for $what.');
}

void main() {
  final database = RestDatabase(
    client: EmulatorAdminClient(http.Client()),
    databaseUrl:
        'http://${_env('FIREBASE_DATABASE_EMULATOR_HOST')}/?ns=${_env('LIVE_SCORE_WIRING_NS')}',
  );
  final log = _AggregatorLog(_env('LIVE_SCORE_WIRING_LOG'));
  final workerUrl = Uri.parse(
    '${_env('LIVE_SCORE_WIRING_FUNCTIONS_ORIGIN')}/${_env('LIVE_SCORE_WIRING_PROJECT')}/$_region/backend-scoring-command',
  );
  final secret = _env('LIVE_SCORE_WIRING_SECRET');

  var testNumber = 0;
  late String comp;

  String livePath() => '/Stats/$comp/${paths.liveScoresBackendRoot}/$_game';
  String keyOf(DateTime at, ScoringTeam team) =>
      '${at.microsecondsSinceEpoch}-${team.name}';

  Future<Object?> value(String path) async =>
      (await database.ref(path).once()).value;

  Future<void> seedCompetition() async {
    await database.ref('/AllDAUComps/$comp').set(<String, Object?>{
      'name': 'Wiring test comp',
      'aflFixtureJsonURL': 'https://example.invalid/afl.json',
      'nrlFixtureJsonURL': 'https://example.invalid/nrl.json',
      'combinedRounds2': <Object?>[
        <String, Object?>{
          'roundStartDate': '2027-03-01T00:00:00Z',
          'roundEndDate': '2027-03-14T23:59:59Z',
        },
      ],
    });
    await database.ref(paths.teamsPathRoot).set(<String, Object?>{
      'nrl-broncos': <String, Object?>{'name': 'Broncos', 'league': 'nrl'},
      'nrl-roosters': <String, Object?>{'name': 'Roosters', 'league': 'nrl'},
    });
    await database.ref('${paths.gamesPathRoot}/$comp').set(<String, Object?>{
      _game: <String, Object?>{
        'RoundNumber': 1,
        'MatchNumber': 1,
        'HomeTeam': 'Broncos',
        'AwayTeam': 'Roosters',
        'Location': 'Stadium One',
        'DateUtc': _kickoff.toIso8601String(),
      },
    });
    await database.ref(paths.tippersPath).set(<String, Object?>{
      'tipper-one': <String, Object?>{
        'authuid': 'auth-one',
        'email': 'tipper.one@example.invalid',
        'name': 'Tipper One',
        'tipperRole': 'tipper',
        'compsParticipatedIn': <String>[comp],
        'isAnonymous': false,
      },
    });
    await database.ref('${paths.tipsPathRoot}/$comp').set(<String, Object?>{
      'tipper-one': <String, Object?>{
        _game: <String, Object?>{'r': 'd', 't': 1800000000},
      },
    });
  }

  /// A submission, written the way a 1.4.x client writes one.
  Future<void> submit(
    int minute,
    ScoringTeam team,
    int score, {
    String tipper = 'tipper-one',
  }) {
    final at = _kickoff.add(Duration(minutes: minute));
    return database
        .ref('${livePath()}/history/${keyOf(at, team)}')
        .set(CrowdSourcedScore(at, team, tipper, score, false).toJson());
  }

  /// A submission, then a wait for the aggregator's run for it to be logged. Real
  /// submissions are minutes apart; this keeps the runs in a known order so the
  /// test can say exactly what each one did (the simultaneous case is covered by
  /// the emulator tests of the handler).
  Future<void> submitAndAwaitRun(
    int minute,
    ScoringTeam team,
    int score, {
    String tipper = 'tipper-one',
  }) async {
    final runs = log.verbs(comp).length;
    await submit(minute, team, score, tipper: tipper);
    await _until(
      () => log.verbs(comp).length > runs,
      'the aggregator to handle the submission',
    );
  }

  Future<List<Map<Object?, Object?>>> idempotencyRecords() async {
    final records =
        await value('/Stats/$comp/${paths.scoringIdempotencyBackendRoot}')
            as Map?;
    return <Map<Object?, Object?>>[
      for (final record in records?.values ?? const <Object?>[])
        if (record is Map) record,
    ];
  }

  Future<int> completedScorings(String commandType) async =>
      (await idempotencyRecords())
          .where(
            (r) =>
                r['commandType'] == commandType && r['status'] == 'completed',
          )
          .length;

  /// The number of completed scorings of [commandType] once it has stopped
  /// changing for a few seconds: scoring runs after the write that causes it, so
  /// a count taken straight away can still be about to move.
  Future<int> settledScorings(String commandType) async {
    var count = await completedScorings(commandType);
    var unchangedFor = 0;
    while (unchangedFor < 6) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final now = await completedScorings(commandType);
      unchangedFor = now == count ? unchangedFor + 1 : 0;
      count = now;
    }
    return count;
  }

  Future<void> setMode(String mode) =>
      database.ref(liveScoresModePath).set(mode);

  Future<http.Response> post(
    Object? body, {
    Map<String, String> headers = const <String, String>{},
  }) => http.post(
    workerUrl,
    headers: <String, String>{'Content-Type': 'application/json', ...headers},
    body: jsonEncode(body),
  );

  Map<String, Object?> historyCommand({String? gameKey = _game}) =>
      <String, Object?>{
        'command': <String, Object?>{
          'commandType': 'liveScoreHistoryWritten',
          'compKey': comp,
          'gameKey': ?gameKey,
          'sourceEventId': 'direct-call-$testNumber',
          'sourcePath': '${livePath()}/history',
          'scopeKey': 'comp:$comp/game:$_game',
          'commandId': 'direct_call_$testNumber',
        },
      };

  setUp(() async {
    testNumber += 1;
    comp = 'wiring$testNumber';
    await database.ref('/').remove();
    await seedCompetition();
    // Seeding a tip fires the existing tip scoring (itself a check that the
    // emulators deliver triggers). Let it finish, so that what a test sees
    // happen afterwards is not the seed's doing.
    await _until(
      () async => await completedScorings('tipWritten') == 1,
      'the seed tip to be scored',
    );
  });

  group('the live-score wiring on the emulators', () {
    test(
      'the worker refuses a request that does not carry the secret',
      () async {
        expect((await post(historyCommand())).statusCode, 403);
        expect(
          (await post(
            historyCommand(),
            headers: <String, String>{
              'x-backend-scoring-secret': 'not-the-secret',
            },
          )).statusCode,
          403,
        );
        expect(
          (await http.get(
            workerUrl,
            headers: <String, String>{'x-backend-scoring-secret': secret},
          )).statusCode,
          405,
        );
        await Future<void>.delayed(_quiet);
        expect(log.verbs(comp), isEmpty, reason: 'nothing ran');
      },
    );

    test(
      'the worker takes the command, and rejects one without a game',
      () async {
        final ok = await post(
          historyCommand(),
          headers: <String, String>{'x-backend-scoring-secret': secret},
        );
        expect(ok.statusCode, 200, reason: ok.body);
        expect(jsonDecode(ok.body), containsPair('status', 'completed'));
        expect(ok.body, contains('nothingToDo'));

        final bad = await post(
          historyCommand(gameKey: null),
          headers: <String, String>{'x-backend-scoring-secret': secret},
        );
        expect(bad.statusCode, 400);
      },
    );

    test(
      'shadow (the default): a submission reaches the aggregator and changes nothing',
      () async {
        final before = jsonDecode(jsonEncode(await value('/'))) as Map;

        await submitAndAwaitRun(1, ScoringTeam.home, 6);
        await Future<void>.delayed(_quiet);

        expect(log.verbs(comp), ['shadow'], reason: 'one submission, one run');
        final after = jsonDecode(jsonEncode(await value('/'))) as Map;
        final stats = (after['Stats'] as Map)[comp] as Map;
        // The submission itself is the only difference: its `history` entry.
        // No `current`, so no rescore; every other record, the seed's scoring
        // included, is exactly as it was.
        final live = stats.remove(paths.liveScoresBackendRoot) as Map;
        expect((live[_game] as Map).keys, ['history']);
        expect(after, before);
        expect(await completedScorings('liveScoreWritten'), 0);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'active: each submission rebuilds `current`, scoring runs once per change, and aggregation never runs itself',
      () async {
        await setMode('active');

        await submitAndAwaitRun(1, ScoringTeam.home, 6);
        expect(await value('${livePath()}/current'), isNotNull);
        await _until(
          () async => await completedScorings('liveScoreWritten') == 1,
          'the first scoring',
        );

        await submitAndAwaitRun(2, ScoringTeam.away, 4, tipper: 'tipper-two');
        expect(
          ((await value('${livePath()}/current')) as Map)['awayInterimScore'],
          4,
        );
        await _until(
          () async => await completedScorings('liveScoreWritten') == 2,
          'the second scoring',
        );

        await submitAndAwaitRun(
          3,
          ScoringTeam.home,
          12,
          tipper: 'tipper-three',
        );
        expect(
          ((await value('${livePath()}/current')) as Map)['homeInterimScore'],
          12,
        );
        await _until(
          () async => await completedScorings('liveScoreWritten') == 3,
          'the third scoring',
        );

        // Nothing more happens by itself.
        await Future<void>.delayed(_quiet);
        expect(log.verbs(comp), [
          'wrote',
          'wrote',
          'wrote',
        ], reason: 'three submissions, three runs, no run caused by `current`');
        expect(await completedScorings('liveScoreWritten'), 3);

        final current = (await value('${livePath()}/current')) as Map;
        expect(current['homeInterimScore'], 12);
        expect(current['awayInterimScore'], 4);
        expect(current['tipperID'], 'tipper-three');
        expect(current['gameComplete'], false);
        expect(current['basedOnCount'], 3);

        final status =
            (await value('/Stats/$comp/${paths.scoringStatusKey}')) as Map;
        expect(status['status'], 'completed');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'active: a stale legacy write of `current` is put right by the next submission, and a repeat changes nothing',
      () async {
        await setMode('active');
        await submitAndAwaitRun(1, ScoringTeam.home, 6);
        await submitAndAwaitRun(2, ScoringTeam.away, 4, tipper: 'tipper-two');
        expect(
          ((await value('${livePath()}/current')) as Map)['awayInterimScore'],
          4,
        );

        // A 1.4.x client that has not seen the away score writes its own idea
        // of `current` together with its submission.
        final at = _kickoff.add(const Duration(minutes: 3));
        final mine = CrowdSourcedScore(
          at,
          ScoringTeam.home,
          'tipper-three',
          12,
          false,
        );
        await database.ref(livePath()).update(<String, Object?>{
          'history/${keyOf(at, ScoringTeam.home)}': mine.toJson(),
          'current': <String, Object?>{
            'homeInterimScore': 12,
            'submittedTimeUTC': at.toIso8601String(),
            'tipperID': 'tipper-three',
            'gameComplete': false,
            'crowdSourcedScores': <Object?>[mine.toJson()],
          },
        });

        await _until(() async {
          final current = (await value('${livePath()}/current')) as Map?;
          return current?['homeInterimScore'] == 12 &&
              current?['awayInterimScore'] == 4 &&
              current?['basedOnCount'] == 3;
        }, 'the aggregator to restore the away score');
        await Future<void>.delayed(_quiet);
        expect(log.verbs(comp), ['wrote', 'wrote', 'wrote']);

        // Delivering the same command again (a retry, a duplicate event) finds
        // the snapshot already right and writes nothing.
        final scorings = await settledScorings('liveScoreWritten');
        final repeat = await post(
          historyCommand(),
          headers: <String, String>{'x-backend-scoring-secret': secret},
        );
        expect(repeat.statusCode, 200, reason: repeat.body);
        await _until(
          () => log.verbs(comp).length == 4,
          'the repeated command to be handled',
        );
        expect(log.verbs(comp).last, 'unchanged');
        await Future<void>.delayed(_quiet);
        expect(await completedScorings('liveScoreWritten'), scorings);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'the fixture import clears the live node and nothing brings it back',
      () async {
        await setMode('active');
        await submitAndAwaitRun(1, ScoringTeam.home, 6);
        await submitAndAwaitRun(2, ScoringTeam.away, 4, tipper: 'tipper-two');
        expect(
          ((await value('${livePath()}/current')) as Map)['awayInterimScore'],
          4,
        );

        // What the fixture import writes when a game finishes: the official
        // score and the removal of the game's whole live node, in one update.
        await database.ref('/').update(<String, Object?>{
          'DAUCompsGames/$comp/$_game/HomeTeamScore': 20,
          'DAUCompsGames/$comp/$_game/AwayTeamScore': 10,
          livePath().substring(1): null,
        });

        await _until(
          () async => await completedScorings('officialScoreWritten') >= 1,
          'the official score to be scored',
        );
        // The removal of each history entry reaches the aggregator, and every
        // one of those runs finds the official score and stands aside.
        await _until(
          () => log.verbs(comp).where((v) => v == 'skipped').length >= 2,
          'the removed entries to reach the aggregator',
        );
        await Future<void>.delayed(_quiet);

        expect(await value(livePath()), isNull, reason: 'not recreated');
        final verbs = log.verbs(comp);
        expect(verbs, [
          'wrote',
          'wrote',
          'skipped',
          'skipped',
        ], reason: 'after the import the aggregator only stands aside');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }, skip: _skip);
}
