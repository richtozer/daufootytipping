import 'dart:async';
import 'dart:math';

import 'package:dart_functions/live_scores/live_score_aggregate.dart';
import 'package:dart_functions/live_scores/live_score_aggregation.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/client_live_score_oracle.dart';
import '../support/emulator.dart';
import '../support/http_faults.dart';

const String _comp = 'c1';
const String _game = 'nrl-01-001';
final DateTime _kickoff = DateTime.utc(2027, 3, 7, 2, 30);

String _livePath() => '/Stats/$_comp/${paths.liveScoresBackendRoot}/$_game';

String _key(DateTime at, ScoringTeam team) =>
    '${at.microsecondsSinceEpoch}-${team.name}';

CrowdSourcedScore _score(
  int minute,
  ScoringTeam team,
  int score, {
  String tipper = 'tipperA',
}) => CrowdSourcedScore(
  _kickoff.add(Duration(minutes: minute)),
  team,
  tipper,
  score,
  false,
);

void main() {
  final skip = emulatorSkipReason;

  group('the live-score aggregator', () {
    late RecordRequests recorder;
    late final RestDatabase db = openEmulatorDatabase(
      wrap: (inner) => recorder = RecordRequests(inner),
    );
    late List<String> log;

    setUp(() async {
      await clearEmulatorDatabase(db);
      recorder.requests.clear();
      log = <String>[];
    });

    Future<void> putHistory(List<CrowdSourcedScore> scores) async {
      for (final score in scores) {
        await db
            .ref(
              '${_livePath()}/history/${_key(score.submittedTimeUTC, score.scoreTeam)}',
            )
            .set(score.toJson());
      }
    }

    Future<Map?> currentNow() async =>
        (await db.ref('${_livePath()}/current').once()).value as Map?;

    Future<AggregationResult> run([
      LiveScoresMode? mode,
      Future<void> Function()? beforeWrite,
    ]) => runLiveScoreAggregation(
      database: db,
      compKey: _comp,
      gameKey: _game,
      mode: mode,
      log: log.add,
      beforeWrite: beforeWrite,
    );

    int writesToCurrent() => recorder.requests
        .where((r) => r.method != 'GET' && r.path.endsWith('/current.json'))
        .length;

    final threeScores = <CrowdSourcedScore>[
      _score(1, ScoringTeam.home, 6),
      _score(2, ScoringTeam.away, 4, tipper: 'tipperB'),
      _score(3, ScoringTeam.home, 12, tipper: 'tipperC'),
    ];

    group('the mode', () {
      test(
        'is shadow when nothing is set, and when what is set is not a mode',
        () async {
          expect(await readLiveScoresMode(db), LiveScoresMode.shadow);
          await db.ref(liveScoresModePath).set('banana');
          expect(await readLiveScoresMode(db), LiveScoresMode.shadow);
          await db.ref(liveScoresModePath).set(7);
          expect(await readLiveScoresMode(db), LiveScoresMode.shadow);
        },
        skip: skip,
      );

      test('reads each of the three', () async {
        for (final mode in LiveScoresMode.values) {
          await db.ref(liveScoresModePath).set(mode.name);
          expect(await readLiveScoresMode(db), mode);
        }
      }, skip: skip);

      test('is used when the caller does not name one', () async {
        await putHistory(threeScores);
        await db.ref(liveScoresModePath).set('active');
        expect((await run()).outcome, AggregationOutcome.written);
      }, skip: skip);
    });

    group('shadow', () {
      test(
        'writes nothing, and says the snapshot already there matches',
        () async {
          await putHistory(threeScores);
          final snapshot = computeLiveScoreAggregate(
            (await db.ref('${_livePath()}/history').once()).value,
          ).snapshot!;
          await db.ref('${_livePath()}/current').set(snapshot);
          recorder.requests.clear();

          final result = await run(LiveScoresMode.shadow);
          expect(result.outcome, AggregationOutcome.shadowMatch);
          expect(writesToCurrent(), 0);
          expect(log.single, contains('match=true'));
        },
        skip: skip,
      );

      test('writes nothing, and names how a stale snapshot differs', () async {
        await putHistory(threeScores);
        await db.ref('${_livePath()}/current').set(<String, Object?>{
          'homeInterimScore': 6,
          'awayInterimScore': 4,
          'submittedTimeUTC': threeScores[1].submittedTimeUTC.toIso8601String(),
          'tipperID': 'tipperB',
          'gameComplete': false,
          'crowdSourcedScores': [
            threeScores[0].toJson(),
            threeScores[1].toJson(),
          ],
        });
        recorder.requests.clear();

        final result = await run(LiveScoresMode.shadow);
        expect(result.outcome, AggregationOutcome.shadowDiffers);
        expect(result.differences, isNotEmpty);
        expect(
          (await currentNow())!['homeInterimScore'],
          6,
          reason: 'left as it was',
        );
        expect(writesToCurrent(), 0);
        expect(log.single, contains('match=false'));
      }, skip: skip);

      test(
        'with no snapshot at all, says so and still writes nothing',
        () async {
          await putHistory(threeScores);
          final result = await run(LiveScoresMode.shadow);
          expect(result.outcome, AggregationOutcome.shadowDiffers);
          expect(await currentNow(), isNull);
        },
        skip: skip,
      );
    });

    for (final mode in <LiveScoresMode>[
      LiveScoresMode.active,
      LiveScoresMode.compat,
    ]) {
      group(mode.name, () {
        test('writes the snapshot, with the count of history it saw', () async {
          await putHistory(threeScores);
          final result = await run(mode);
          expect(result.outcome, AggregationOutcome.written);
          final current = await currentNow();
          expect(current!['homeInterimScore'], 12);
          expect(current['awayInterimScore'], 4);
          expect(current['tipperID'], 'tipperC');
          expect(current['basedOnCount'], 3);
          expect((current['crowdSourcedScores'] as List), hasLength(3));
        }, skip: skip);

        test(
          'does not rewrite a snapshot that already shows the game: a rewrite would only rescore',
          () async {
            await putHistory(threeScores);
            await run(mode);
            recorder.requests.clear();

            final again = await run(mode);
            expect(again.outcome, AggregationOutcome.unchanged);
            expect(writesToCurrent(), 0);
          },
          skip: skip,
        );

        test('does not let an older computation undo a newer one', () async {
          await putHistory(threeScores);
          // A slow run has read three entries and is about to write...
          final release = Completer<void>();
          final slow = run(mode, () => release.future);
          await Future<void>.delayed(const Duration(milliseconds: 100));

          // ...while history grows and a newer run writes first.
          await putHistory(<CrowdSourcedScore>[
            _score(4, ScoringTeam.away, 10),
          ]);
          final newer = await run(mode);
          expect(newer.outcome, AggregationOutcome.written);
          expect((await currentNow())!['basedOnCount'], 4);

          release.complete();
          final late = await slow;
          expect(late.outcome, AggregationOutcome.unchanged);
          final current = await currentNow();
          expect(
            current!['basedOnCount'],
            4,
            reason: 'the newer snapshot stands',
          );
          expect(current['awayInterimScore'], 10);
        }, skip: skip);

        test(
          'leaves alone a snapshot a legacy client wrote that already shows this game: rewriting it would only rescore',
          () async {
            await putHistory(threeScores);
            final snapshot = computeLiveScoreAggregate(
              (await db.ref('${_livePath()}/history').once()).value,
            ).snapshot!;
            // The same content, as a 1.4.x client writes it: no count.
            await db
                .ref('${_livePath()}/current')
                .set(
                  Map<String, Object?>.from(snapshot)..remove('basedOnCount'),
                );
            recorder.requests.clear();

            final result = await run(mode);
            expect(result.outcome, AggregationOutcome.unchanged);
            expect(writesToCurrent(), 0);
            expect((await currentNow())!.containsKey('basedOnCount'), false);
          },
          skip: skip,
        );

        test(
          'replaces a snapshot a legacy client wrote, which has no count',
          () async {
            await putHistory(threeScores);
            await db.ref('${_livePath()}/current').set(<String, Object?>{
              'homeInterimScore': 6,
              'awayInterimScore': 4,
              'submittedTimeUTC': threeScores[1].submittedTimeUTC
                  .toIso8601String(),
              'tipperID': 'tipperB',
              'gameComplete': false,
              'crowdSourcedScores': [
                threeScores[0].toJson(),
                threeScores[1].toJson(),
              ],
            });
            final result = await run(mode);
            expect(result.outcome, AggregationOutcome.written);
            expect((await currentNow())!['homeInterimScore'], 12);
          },
          skip: skip,
        );

        test(
          'duplicated, shuffled and simultaneous runs agree, and one of them writes',
          () async {
            await putHistory(threeScores);
            final results = await Future.wait(<Future<AggregationResult>>[
              run(mode),
              run(mode),
              run(mode),
            ]);
            expect(
              results.where((r) => r.outcome == AggregationOutcome.written),
              isNotEmpty,
            );
            final current = await currentNow();
            expect(current!['homeInterimScore'], 12);
            expect(current['basedOnCount'], 3);
            expect((await run(mode)).outcome, AggregationOutcome.unchanged);
          },
          skip: skip,
        );
      });
    }

    group('an official score', () {
      Future<void> official() => db.ref('/DAUCompsGames/$_comp/$_game').set(
        <String, Object?>{'HomeTeamScore': 20, 'AwayTeamScore': 14},
      );

      test('overrides all of it: nothing is written in any mode', () async {
        await putHistory(threeScores);
        await official();
        for (final mode in LiveScoresMode.values) {
          recorder.requests.clear();
          final result = await run(mode);
          expect(
            result.outcome,
            AggregationOutcome.skippedOfficial,
            reason: mode.name,
          );
          expect(writesToCurrent(), 0, reason: mode.name);
        }
        expect(await currentNow(), isNull);
      }, skip: skip);

      test('one team\'s score alone is not an official result', () async {
        await putHistory(threeScores);
        await db.ref('/DAUCompsGames/$_comp/$_game').set(<String, Object?>{
          'HomeTeamScore': 20,
        });
        expect(
          (await run(LiveScoresMode.active)).outcome,
          AggregationOutcome.written,
        );
      }, skip: skip);

      test(
        'arriving while the snapshot is being written: the snapshot is removed again',
        () async {
          await putHistory(threeScores);
          final result = await run(LiveScoresMode.active, official);
          expect(result.outcome, AggregationOutcome.clearedForOfficial);
          expect(
            await currentNow(),
            isNull,
            reason: 'no stale snapshot for a finished game',
          );
        },
        skip: skip,
      );
    });

    group('a legacy client that said the game is complete', () {
      // Only an official score completes a game. The scoring worker already
      // ignores the flag, and the aggregator does not let it propagate.
      final completeScores = <CrowdSourcedScore>[
        _score(1, ScoringTeam.home, 6),
        CrowdSourcedScore(
          _kickoff.add(const Duration(minutes: 2)),
          ScoringTeam.away,
          'tipperB',
          4,
          true,
        ),
      ];

      test(
        'does not complete it in the snapshot the aggregator writes',
        () async {
          await putHistory(completeScores);
          final result = await run(LiveScoresMode.active);
          expect(result.outcome, AggregationOutcome.written);
          final current = (await currentNow())!;
          expect(current['gameComplete'], false);
          for (final score in current['crowdSourcedScores'] as List) {
            expect((score as Map)['gameComplete'], false);
          }
        },
        skip: skip,
      );

      test(
        'and a snapshot a legacy client wrote as complete is put right, once',
        () async {
          await putHistory(completeScores);
          final shown = computeLiveScoreAggregate(
            (await db.ref('${_livePath()}/history').once()).value,
          ).snapshot!;
          // As a legacy client writes it: no count.
          await db
              .ref('${_livePath()}/current')
              .set(
                <String, Object?>{...shown, 'gameComplete': true}
                  ..remove('basedOnCount'),
              );

          expect(
            (await run(LiveScoresMode.shadow)).outcome,
            AggregationOutcome.shadowDiffers,
          );
          expect((await currentNow())!['gameComplete'], true, reason: 'shadow');

          expect(
            (await run(LiveScoresMode.active)).outcome,
            AggregationOutcome.written,
          );
          expect((await currentNow())!['gameComplete'], false);
          expect(
            (await run(LiveScoresMode.active)).outcome,
            AggregationOutcome.unchanged,
          );
        },
        skip: skip,
      );
    });

    test('a game with nothing in its history has nothing to do', () async {
      final result = await run(LiveScoresMode.active);
      expect(result.outcome, AggregationOutcome.nothingToDo);
      expect(await currentNow(), isNull);
    }, skip: skip);

    test('something that is not a key is refused', () async {
      await expectLater(
        runLiveScoreAggregation(
          database: db,
          compKey: 'c1/../x',
          gameKey: _game,
          log: log.add,
        ),
        throwsArgumentError,
      );
    }, skip: skip);

    group('legacy clients and the aggregator over the same history', () {
      // Two 1.4.x clients each keep their own local list and, on every submission,
      // overwrite `current` from it, so each write can lose the other's scores. The
      // aggregator runs after every submission. It must put `current` right each
      // time, and once it has, running it again changes nothing: it must not flap.
      test(
        'converge to one displayed score, and stay there',
        () async {
          for (var seed = 0; seed < 20; seed++) {
            await clearEmulatorDatabase(db);
            await db.ref(liveScoresModePath).set('compat');
            final random = Random(seed);
            final clients = <ClientLiveScoreOracle>[
              ClientLiveScoreOracle(),
              ClientLiveScoreOracle(),
            ];
            var staleWrites = 0;

            for (var i = 0; i < 12; i++) {
              final client = clients[random.nextInt(2)];
              final team = random.nextBool()
                  ? ScoringTeam.home
                  : ScoringTeam.away;
              final at = _kickoff.add(
                Duration(seconds: 20 * i + random.nextInt(15)),
              );
              client.submit(<CrowdSourcedScore>[
                CrowdSourcedScore(
                  at,
                  team,
                  client == clients.first ? 'clientA' : 'clientB',
                  random.nextInt(60),
                  false,
                ),
              ]);
              // The legacy client's two writes, as one update: its own `current` and its history.
              await db.ref(_livePath()).update(<String, Object?>{
                'current': client.current,
                for (final entry in client.history.entries)
                  'history/${entry.key}': entry.value,
              });

              final expected = computeLiveScoreAggregate(
                (await db.ref('${_livePath()}/history').once()).value,
              ).snapshot!;
              if (liveScoreDifferences(
                await currentNow(),
                expected,
              ).isNotEmpty) {
                staleWrites += 1;
              }

              await run(LiveScoresMode.compat);
              expect(
                liveScoreDifferences(await currentNow(), expected),
                isEmpty,
                reason:
                    'seed $seed submission $i: current is not what history shows',
              );
              recorder.requests.clear();
              expect(
                (await run(LiveScoresMode.compat)).outcome,
                AggregationOutcome.unchanged,
              );
              expect(
                writesToCurrent(),
                0,
                reason: 'seed $seed submission $i: it flapped',
              );
            }
            expect(
              staleWrites,
              greaterThan(0),
              reason:
                  'seed $seed: the clients never disagreed, so this proved nothing',
            );
          }
        },
        skip: skip,
        timeout: const Timeout(Duration(minutes: 5)),
      );
    });
  });
}
