import 'package:dart_functions/errors.dart';
import 'package:dart_functions/live_scores/live_score_aggregation.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/paths.dart' as paths;
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../../bin/server.dart';
import '../support/emulator.dart';

const String _comp = 'c1';
const String _game = 'nrl-01-001';
final DateTime _kickoff = DateTime.utc(2027, 3, 7, 2, 30);

String _livePath() => '/Stats/$_comp/${paths.liveScoresBackendRoot}/$_game';

BackendScoringCommand _command({String type = 'liveScoreHistoryWritten'}) =>
    BackendScoringCommand.fromJson(<String, dynamic>{
      'commandType': type,
      'compKey': _comp,
      'gameKey': _game,
      'sourceEventId': 'event-1',
      'sourcePath': '${_livePath()}/history',
      'scopeKey': 'comp:$_comp/game:$_game',
      'commandId': 'event_1',
    });

/// The worker's side of the M5 wiring: a `liveScoreHistoryWritten` command, as
/// the trigger sends it, runs the aggregator. (The trigger, the HTTP request and
/// the secret are covered end to end by `scripts/test-live-score-wiring.sh`.)
void main() {
  final skip = emulatorSkipReason;

  group('the liveScoreHistoryWritten command', () {
    test('parses, and needs the game', () {
      expect(
        _command().commandType,
        BackendScoringCommandType.liveScoreHistoryWritten,
      );
      expect(
        () => BackendScoringCommand.fromJson(<String, dynamic>{
          'commandType': 'liveScoreHistoryWritten',
          'compKey': _comp,
          'sourceEventId': 'event-1',
          'sourcePath': '${_livePath()}/history',
          'scopeKey': 'comp:$_comp',
          'commandId': 'event_1',
        }),
        throwsArgumentError,
      );
    });

    test('refuses a database it cannot compare-and-set on', () async {
      await expectLater(
        executeBackendScoringCommand(
          db: Object(),
          command: _command(),
          now: DateTime.utc(2027, 3, 7),
        ),
        throwsA(isA<InternalError>()),
      );
    });

    group('with the database', () {
      late final RestDatabase db = openEmulatorDatabase();

      setUp(() async {
        await clearEmulatorDatabase(db);
        for (var minute = 1; minute <= 2; minute++) {
          final at = _kickoff.add(Duration(minutes: minute));
          await db
              .ref('${_livePath()}/history/${at.microsecondsSinceEpoch}-home')
              .set(
                CrowdSourcedScore(
                  at,
                  ScoringTeam.home,
                  'tipperA',
                  minute * 6,
                  false,
                ).toJson(),
              );
        }
      });

      Future<BackendScoringCommandResult> deliver([
        BackendScoringCommand? command,
      ]) => executeBackendScoringCommand(
        db: db,
        command: command ?? _command(),
        now: DateTime.utc(2027, 3, 7),
      );

      test('is shadow by default: it reports, and changes nothing', () async {
        final result = await deliver();
        expect(result.status, 'completed');
        expect(result.skipped, true);
        expect(result.message, contains('shadowDiffers'));
        expect((await db.ref('${_livePath()}/current').once()).value, isNull);
        expect(
          (await db.ref('/Stats/$_comp').once()).value.toString(),
          isNot(contains('scoring_idempotency')),
          reason: 'no idempotency record per submission',
        );
      }, skip: skip);

      test('writes `current` once the mode is active, and only then', () async {
        await db.ref(liveScoresModePath).set('active');
        final result = await deliver();
        expect(result.skipped, false);
        expect(result.message, contains('written'));
        final current =
            (await db.ref('${_livePath()}/current').once()).value as Map;
        expect(current['homeInterimScore'], 12);

        final again = await deliver();
        expect(again.skipped, true);
        expect(again.message, contains('unchanged'));
      }, skip: skip);

      test('is not a scoring command: the scoring path is untouched', () async {
        await db.ref(liveScoresModePath).set('active');
        await deliver();
        final stats = (await db.ref('/Stats/$_comp').once()).value as Map;
        expect(
          stats.keys,
          isNot(contains(paths.scoringIdempotencyBackendRoot)),
        );
      }, skip: skip);
    });
  });
}
