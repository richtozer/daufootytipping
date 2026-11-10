import 'dart:convert';
import 'dart:io';

import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_livescoring_modal.dart';
import 'package:daufootytipping/services/live_score_history_entry.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_database/firebase_database.dart' show ServerValue;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final score = CrowdSourcedScore(
    DateTime.utc(2027, 3, 12, 6, 30, 15, 123, 456),
    ScoringTeam.away,
    'tipper-1',
    14,
    false,
  );

  group('the history entry a client writes', () {
    test('has the tipper, team and score, and the server clock', () {
      expect(liveScoreHistoryEntry(score), <String, Object?>{
        'tipperID': 'tipper-1',
        'scoreTeam': 'away',
        'interimScore': 14,
        't': ServerValue.timestamp,
      });
    });

    test('carries nothing from the device clock', () {
      final entry = liveScoreHistoryEntry(score);

      expect(entry.containsKey('submittedTimeUTC'), isFalse);
      expect(entry.containsKey('gameComplete'), isFalse);
    });

    test('is keyed by the device time in microseconds and the team', () {
      expect(liveScoreHistoryKey(score), '1804833015123456-away');
    });

    test('has exactly the fields the R2 rules allow', () {
      final rules = jsonDecode(
        File('config/generated/database.rules.r2.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final entryRules =
          ((((rules['rules'] as Map)['Stats'] as Map)[r'$comp']
                      as Map)['live_scores_backend_v1']
                  as Map)[r'$game']
              as Map;
      final allowed =
          ((entryRules['history'] as Map)[r'$entry'] as Map<String, dynamic>)
              .keys
              .where((key) => !key.startsWith('.') && !key.startsWith(r'$'))
              .toSet();

      expect(liveScoreHistoryEntry(score).keys.toSet(), allowed);
    });
  });

  group('when a live score is not saved', () {
    test('a refusal by the rules is explained', () {
      final message = liveScoreSaveFailureMessage(
        FirebaseException(
          plugin: 'firebase_database',
          code: 'permission-denied',
        ),
      );

      expect(message, contains('not saved'));
      expect(message, contains('official score'));
    });

    test('anything else shows the error', () {
      expect(
        liveScoreSaveFailureMessage(StateError('boom')),
        contains('Unable to save live scores'),
      );
    });
  });
}
