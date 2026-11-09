import 'dart:math';

import 'package:dart_functions/live_scores/live_score_aggregate.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/client_live_score_oracle.dart';

/// A `history` entry in the 1.4.x client's shape.
Map<String, Object?> legacy({
  required DateTime at,
  required ScoringTeam team,
  required int score,
  String tipper = 'tipperA',
  bool complete = false,
}) => CrowdSourcedScore(at, team, tipper, score, complete).toJson();

String keyFor(DateTime at, ScoringTeam team) =>
    '${at.microsecondsSinceEpoch}-${team.name}';

final DateTime _kickoff = DateTime.utc(2027, 3, 7, 2, 30);

void main() {
  group('reading an entry', () {
    test('the 1.4.x shape: time from submittedTimeUTC', () {
      final at = _kickoff.add(
        const Duration(minutes: 12, microseconds: 123456),
      );
      final entry = LiveScoreEntry.tryParse(
        keyFor(at, ScoringTeam.home),
        legacy(at: at, team: ScoringTeam.home, score: 14),
      )!;
      expect(entry.micros, at.microsecondsSinceEpoch);
      expect(entry.team, ScoringTeam.home);
      expect(entry.score, 14);
      expect(entry.toJson()['submittedTimeUTC'], at.toIso8601String());
    });

    test('a numeric t wins over the legacy text', () {
      final tMicros = _kickoff
          .add(const Duration(minutes: 5))
          .microsecondsSinceEpoch;
      final entry = LiveScoreEntry.tryParse('k', <String, Object?>{
        't': tMicros,
        'submittedTimeUTC': _kickoff.toIso8601String(),
        'tipperID': 'a',
        'scoreTeam': 'away',
        'interimScore': 7,
      })!;
      expect(entry.micros, tMicros);
    });

    test(
      'a t in milliseconds, as the R2 rules force it to be, is read as such',
      () {
        final at = _kickoff.add(const Duration(minutes: 5));
        final entry = LiveScoreEntry.tryParse('-OaBcD', <String, Object?>{
          't': at.millisecondsSinceEpoch,
          'tipperID': 'a',
          'scoreTeam': 'home',
          'interimScore': 7,
        })!;
        expect(entry.micros, at.microsecondsSinceEpoch);
        expect(entry.toJson()['submittedTimeUTC'], at.toIso8601String());
      },
    );

    test(
      'the server time orders entries, not a push key or a client clock',
      () {
        final early = _kickoff.add(const Duration(minutes: 1));
        final late = _kickoff.add(const Duration(minutes: 9));
        // The later submission has the key that sorts first, and a client clock
        // that says it was early; only `t` says when it really was.
        final aggregate = computeLiveScoreAggregate(<String, Object?>{
          '-Aaaa': <String, Object?>{
            't': late.millisecondsSinceEpoch,
            'submittedTimeUTC': early.toIso8601String(),
            'tipperID': 'late',
            'scoreTeam': 'home',
            'interimScore': 20,
          },
          '-Zzzz': <String, Object?>{
            't': early.millisecondsSinceEpoch,
            'submittedTimeUTC': late.toIso8601String(),
            'tipperID': 'early',
            'scoreTeam': 'home',
            'interimScore': 10,
          },
        });
        expect(aggregate.snapshot!['homeInterimScore'], 20);
        expect(aggregate.snapshot!['tipperID'], 'late');
      },
    );

    test('an implausible t is ignored and the legacy text is used', () {
      final entry = LiveScoreEntry.tryParse('k', <String, Object?>{
        't': 1772000000, // seconds: neither milliseconds nor microseconds
        'submittedTimeUTC': _kickoff.toIso8601String(),
        'tipperID': 'a',
        'scoreTeam': 'away',
        'interimScore': 7,
      })!;
      expect(entry.micros, _kickoff.microsecondsSinceEpoch);
    });

    test('with neither, the push key says when', () {
      final entry = LiveScoreEntry.tryParse(
        '${_kickoff.microsecondsSinceEpoch}-home',
        <String, Object?>{
          'tipperID': 'a',
          'scoreTeam': 'home',
          'interimScore': 3,
        },
      )!;
      expect(entry.micros, _kickoff.microsecondsSinceEpoch);
    });

    test('an entry that cannot be used is ignored, not guessed at', () {
      Map<String, Object?> base() =>
          legacy(at: _kickoff, team: ScoringTeam.home, score: 1);
      expect(LiveScoreEntry.tryParse('k', 'text'), isNull);
      expect(
        LiveScoreEntry.tryParse('k', base()..['scoreTeam'] = 'middle'),
        isNull,
      );
      expect(
        LiveScoreEntry.tryParse('k', base()..['interimScore'] = 'many'),
        isNull,
      );
      expect(LiveScoreEntry.tryParse('k', base()..remove('tipperID')), isNull);
      expect(LiveScoreEntry.tryParse('k', base()..['tipperID'] = ''), isNull);
      expect(
        LiveScoreEntry.tryParse(
          'no-micros',
          base()..remove('submittedTimeUTC'),
        ),
        isNull,
      );
    });

    test('a score written as text is read as a number, as the worker does', () {
      final entry = LiveScoreEntry.tryParse(
        'k',
        legacy(at: _kickoff, team: ScoringTeam.home, score: 1)
          ..['interimScore'] = '22',
      )!;
      expect(entry.score, 22);
    });
  });

  group('the snapshot', () {
    test('an empty or missing history shows nothing', () {
      expect(computeLiveScoreAggregate(null).snapshot, isNull);
      expect(computeLiveScoreAggregate(<String, Object?>{}).snapshot, isNull);
      expect(computeLiveScoreAggregate('text').snapshot, isNull);
    });

    test(
      'each team shows its latest score, and the snapshot is that of the latest submission',
      () {
        final t1 = _kickoff.add(const Duration(minutes: 1));
        final t2 = _kickoff.add(const Duration(minutes: 2));
        final t3 = _kickoff.add(const Duration(minutes: 3));
        final snapshot = computeLiveScoreAggregate(<String, Object?>{
          keyFor(t1, ScoringTeam.home): legacy(
            at: t1,
            team: ScoringTeam.home,
            score: 6,
            tipper: 'x',
          ),
          keyFor(t2, ScoringTeam.away): legacy(
            at: t2,
            team: ScoringTeam.away,
            score: 4,
            tipper: 'y',
          ),
          keyFor(t3, ScoringTeam.home): legacy(
            at: t3,
            team: ScoringTeam.home,
            score: 12,
            tipper: 'z',
          ),
        }).snapshot!;
        expect(snapshot['homeInterimScore'], 12);
        expect(snapshot['awayInterimScore'], 4);
        expect(snapshot['tipperID'], 'z');
        expect(snapshot['submittedTimeUTC'], t3.toIso8601String());
        expect(snapshot['gameComplete'], false);
        expect(snapshot['basedOnCount'], 3);
      },
    );

    test(
      'a legacy entry that says the game is complete does not complete it',
      () {
        final later = _kickoff.add(const Duration(minutes: 5));
        final aggregate = computeLiveScoreAggregate(<String, Object?>{
          keyFor(_kickoff, ScoringTeam.home): legacy(
            at: _kickoff,
            team: ScoringTeam.home,
            score: 6,
            complete: true,
          ),
          keyFor(later, ScoringTeam.away): legacy(
            at: later,
            team: ScoringTeam.away,
            score: 4,
            complete: true,
          ),
        });
        final snapshot = aggregate.snapshot!;

        // The latest entry, the one that sets the snapshot's flag, says true.
        expect(aggregate.latest!.gameComplete, true);
        expect(snapshot['gameComplete'], false);
        for (final score in snapshot['crowdSourcedScores'] as List) {
          expect((score as Map)['gameComplete'], false);
        }
        expect(snapshot['homeInterimScore'], 6);
        expect(snapshot['awayInterimScore'], 4);
      },
    );

    test('a team nobody has scored for has no score in the snapshot', () {
      final snapshot = computeLiveScoreAggregate(<String, Object?>{
        keyFor(_kickoff, ScoringTeam.home): legacy(
          at: _kickoff,
          team: ScoringTeam.home,
          score: 6,
        ),
      }).snapshot!;
      expect(snapshot.containsKey('awayInterimScore'), false);
    });

    test(
      'each team keeps its three most recent; the count still covers them all',
      () {
        final history = <String, Object?>{};
        for (var i = 0; i < 5; i++) {
          final at = _kickoff.add(Duration(minutes: i));
          history[keyFor(at, ScoringTeam.home)] = legacy(
            at: at,
            team: ScoringTeam.home,
            score: i,
          );
        }
        for (var i = 0; i < 2; i++) {
          final at = _kickoff.add(Duration(minutes: 10 + i));
          history[keyFor(at, ScoringTeam.away)] = legacy(
            at: at,
            team: ScoringTeam.away,
            score: i,
          );
        }
        final aggregate = computeLiveScoreAggregate(history);
        List<int> byTeam(ScoringTeam team) => aggregate.kept
            .where((e) => e.team == team)
            .map((e) => e.score)
            .toList();
        expect(byTeam(ScoringTeam.home), [
          2,
          3,
          4,
        ], reason: 'the oldest two are gone');
        expect(byTeam(ScoringTeam.away), [0, 1]);
        expect(aggregate.basedOnCount, 7);
      },
    );

    test('entries it cannot read are counted, not used', () {
      final aggregate = computeLiveScoreAggregate(<String, Object?>{
        keyFor(_kickoff, ScoringTeam.home): legacy(
          at: _kickoff,
          team: ScoringTeam.home,
          score: 1,
        ),
        'junk': <String, Object?>{'hello': 'world'},
        'also-junk': 5,
      });
      expect(aggregate.kept, hasLength(1));
      expect(aggregate.ignored, 2);
      expect(aggregate.basedOnCount, 1);
    });

    test(
      'the latest is the latest by time, whatever order the keys sort in',
      () {
        // Push keys from an R2 client are random; they say nothing about order.
        final earlier = _kickoff.add(const Duration(minutes: 1));
        final later = _kickoff.add(const Duration(minutes: 9));
        final snapshot = computeLiveScoreAggregate(<String, Object?>{
          'zzzz-sorts-last': legacy(
            at: earlier,
            team: ScoringTeam.home,
            score: 3,
            tipper: 'first',
          ),
          'aaaa-sorts-first': legacy(
            at: later,
            team: ScoringTeam.home,
            score: 9,
            tipper: 'second',
          ),
        }).snapshot!;
        expect(snapshot['homeInterimScore'], 9);
        expect(snapshot['tipperID'], 'second');
        expect(snapshot['submittedTimeUTC'], later.toIso8601String());
      },
    );

    test('and the three kept are the three latest by time, not by key', () {
      final history = <String, Object?>{};
      for (var i = 0; i < 5; i++) {
        final at = _kickoff.add(Duration(minutes: i));
        // Later submissions get keys that sort EARLIER.
        history['key-${9 - i}'] = legacy(
          at: at,
          team: ScoringTeam.home,
          score: i,
        );
      }
      final kept = computeLiveScoreAggregate(history).kept;
      expect(kept.map((e) => e.score).toList(), [2, 3, 4]);
    });

    test(
      'two submissions at the same instant: the same one wins however they arrive',
      () {
        Map<String, Object?> entry(String tipper, int score) => legacy(
          at: _kickoff,
          team: ScoringTeam.home,
          score: score,
          tipper: tipper,
        );
        final forwards = computeLiveScoreAggregate(<String, Object?>{
          'a': entry('x', 1),
          'b': entry('y', 2),
        }).snapshot!;
        final backwards = computeLiveScoreAggregate(<String, Object?>{
          'b': entry('y', 2),
          'a': entry('x', 1),
        }).snapshot!;
        expect(forwards['homeInterimScore'], backwards['homeInterimScore']);
        expect(forwards['tipperID'], backwards['tipperID']);
      },
    );

    test(
      'the same history gives the same snapshot every time, in any order',
      () {
        final history = <String, Object?>{};
        for (var i = 0; i < 6; i++) {
          final at = _kickoff.add(Duration(seconds: 17 * i));
          final team = i.isEven ? ScoringTeam.home : ScoringTeam.away;
          history[keyFor(at, team)] = legacy(
            at: at,
            team: team,
            score: i * 3,
            tipper: 't${i % 3}',
          );
        }
        final once = computeLiveScoreAggregate(history).snapshot;
        expect(computeLiveScoreAggregate(history).snapshot, once);
        final shuffled = Map<String, Object?>.fromEntries(
          history.entries.toList()..shuffle(Random(3)),
        );
        expect(computeLiveScoreAggregate(shuffled).snapshot, once);
      },
    );
  });

  group('comparing two snapshots', () {
    Map<String, Object?> snapshot() =>
        computeLiveScoreAggregate(<String, Object?>{
          keyFor(_kickoff, ScoringTeam.home): legacy(
            at: _kickoff,
            team: ScoringTeam.home,
            score: 6,
          ),
          keyFor(
            _kickoff.add(const Duration(minutes: 1)),
            ScoringTeam.away,
          ): legacy(
            at: _kickoff.add(const Duration(minutes: 1)),
            team: ScoringTeam.away,
            score: 4,
          ),
        }).snapshot!;

    test(
      'the same snapshot, or one without the count, or with its list in another order, is no different',
      () {
        final expected = snapshot();
        expect(liveScoreDifferences(expected, expected), isEmpty);

        final legacyShaped = Map<String, Object?>.from(expected)
          ..remove('basedOnCount');
        expect(liveScoreDifferences(legacyShaped, expected), isEmpty);

        final reordered = Map<String, Object?>.from(expected)
          ..['crowdSourcedScores'] = (expected['crowdSourcedScores'] as List)
              .reversed
              .toList();
        expect(liveScoreDifferences(reordered, expected), isEmpty);
      },
    );

    test('a different score, tipper or list is named', () {
      final expected = snapshot();
      expect(
        liveScoreDifferences(
          Map<String, Object?>.from(expected)..['homeInterimScore'] = 7,
          expected,
        ),
        isNotEmpty,
      );
      expect(
        liveScoreDifferences(
          Map<String, Object?>.from(expected)..['tipperID'] = 'someone',
          expected,
        ),
        isNotEmpty,
      );
      expect(
        liveScoreDifferences(
          Map<String, Object?>.from(expected)
            ..['crowdSourcedScores'] = (expected['crowdSourcedScores'] as List)
                .sublist(1),
          expected,
        ),
        isNotEmpty,
      );
    });

    test(
      'a snapshot that says the game is complete differs from one that does not',
      () {
        final expected = snapshot();
        expect(
          liveScoreDifferences(
            Map<String, Object?>.from(expected)..['gameComplete'] = true,
            expected,
          ),
          ['gameComplete differs'],
        );
        final scores = (expected['crowdSourcedScores'] as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        scores.first['gameComplete'] = true;
        expect(
          liveScoreDifferences(
            Map<String, Object?>.from(expected)
              ..['crowdSourcedScores'] = scores,
            expected,
          ),
          isNotEmpty,
        );
      },
    );

    test('no snapshot at all is a difference', () {
      expect(liveScoreDifferences(null, snapshot()), ['no current snapshot']);
    });
  });

  group('held to the client\'s own algorithm', () {
    // The reference is a port of the 1.4.x client. A game-day is played through
    // it, one submission at a time, and the history it writes is handed to the
    // server's calculation, which must show the same game as the client's own
    // `current` snapshot. Submissions come from several tippers whose clocks
    // disagree, so some arrive out of order.
    test('three hundred random game days', () {
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(seed);
        final oracle = ClientLiveScoreOracle();
        final tippers = List<String>.generate(
          2 + random.nextInt(5),
          (i) => 'tipper$i',
        );
        final skew = {
          for (final t in tippers) t: random.nextInt(4000000) - 2000000,
        };
        final submissions = 1 + random.nextInt(30);
        var elapsed = 0;

        for (var i = 0; i < submissions; i++) {
          elapsed += 5000000 + random.nextInt(120000000); // 5 s to 2 min apart
          final tipper = tippers[random.nextInt(tippers.length)];
          // The client's clock; the sequence number keeps every instant distinct.
          final at = DateTime.fromMicrosecondsSinceEpoch(
            _kickoff.microsecondsSinceEpoch + elapsed + skew[tipper]! + i,
            isUtc: true,
          );
          final teams = switch (random.nextInt(3)) {
            0 => <ScoringTeam>[ScoringTeam.home],
            1 => <ScoringTeam>[ScoringTeam.away],
            _ => <ScoringTeam>[ScoringTeam.home, ScoringTeam.away],
          };
          oracle.submit(<CrowdSourcedScore>[
            for (var j = 0; j < teams.length; j++)
              // Two scores in one submission are a moment apart, as in the client.
              CrowdSourcedScore(
                at.add(Duration(microseconds: j)),
                teams[j],
                tipper,
                random.nextInt(80),
                false,
              ),
          ]);
        }

        final shuffled = Map<String, Object?>.fromEntries(
          oracle.history.entries.toList()..shuffle(Random(seed + 1)),
        );
        final serverSnapshot = computeLiveScoreAggregate(shuffled).snapshot!;
        expect(
          liveScoreDifferences(oracle.current, serverSnapshot),
          isEmpty,
          reason:
              'seed $seed: the server\'s snapshot differs from the client\'s',
        );
      }
    });
  });
}
