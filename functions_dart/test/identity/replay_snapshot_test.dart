// Replays every real linked account against a COPY of the real identity data, in the emulator.
//
// This is the safe stand-in for a write-enabled check in production: the callables run against the
// real shapes of the real records (214 tippers, legacy fields, accounts with no stored login), and
// nothing is written anywhere but the emulator.
//
// It needs IDENTITY_SNAPSHOT=<path of a JSON file holding the identity nodes: AllTippers,
// TipperPrivate, AuthIndex, AliasIndex, LogonIndex, Placeholders, AppConfig, AllTippersTokens>, and
// is skipped without it, so no personal data is ever in the repository. The file belongs under
// test/data/ (git-ignored). The test prints COUNTS and opaque ids only: never a name, an address or
// a push token.
//
//   IDENTITY_SNAPSHOT=test/data/identity-replay-snapshot.json \
//     rules_test/support/isolated.sh firebase emulators:exec --only database --project demo-dau-rules \
//     "cd functions_dart && dart test test/identity/replay_snapshot_test.dart"
import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/device_tokens.dart';
import 'package:dart_functions/identity/link_or_create.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/identity/update_alias.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:firebase_functions/firebase_functions.dart'
    show HttpResponseException;
import 'package:test/test.dart';

import '../support/emulator.dart';
import '../support/identity_helpers.dart';
import '../support/identity_invariants.dart';

const int _now = 1793000000000;

String? _snapshotPath() {
  final path = Platform.environment['IDENTITY_SNAPSHOT'];
  return path == null || path.isEmpty ? null : path;
}

String? _skipReason() {
  if (emulatorSkipReason != null) {
    return emulatorSkipReason;
  }
  final path = _snapshotPath();
  if (path == null) {
    return 'needs IDENTITY_SNAPSHOT=<identity snapshot json> (kept under test/data/)';
  }
  return File(path).existsSync() ? null : 'no file at $path';
}

/// What a call came to: an outcome, or a refusal named by its reason or status.
String _label(Object error) {
  if (error is HttpResponseException) {
    return '${error.status}:${reasonOf(error) ?? '-'}';
  }
  return 'unexpected:${error.runtimeType}';
}

void _count(Map<String, int> into, String key) =>
    into[key] = (into[key] ?? 0) + 1;

void _report(
  String title,
  Map<String, int> counts,
  Map<String, List<String>> ids,
) {
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  // ignore: avoid_print
  print('  $title');
  for (final entry in entries) {
    final sample = (ids[entry.key] ?? const <String>[]).take(8).join(', ');
    // ignore: avoid_print
    print(
      '    ${entry.value.toString().padLeft(4)}  ${entry.key}${entry.key.startsWith('existing') ? '' : '   e.g. $sample'}',
    );
  }
}

void main() {
  group('replay of the real identity data', () {
    late final RestDatabase db = openEmulatorDatabase();
    late Map<String, Object?> snapshot;

    setUpAll(() async {
      snapshot = Map<String, Object?>.from(
        jsonDecode(File(_snapshotPath()!).readAsStringSync()) as Map,
      );
      await clearEmulatorDatabase(db);
      await db.ref('/').set(snapshot);
    });

    Map<String, Object?> node(String name) =>
        Map<String, Object?>.from((snapshot[name] as Map?) ?? const {});

    test(
      'every linked account signs in, renames to itself and moves a token',
      () async {
        final authIndex = node('AuthIndex');
        final privateRecords = node('TipperPrivate');
        final publicRecords = node('AllTippers');
        final before = await readRoot(db);
        final admission = admissionFor(mode: IdentityMode.coexist);

        final signIn = <String, int>{};
        final signInIds = <String, List<String>>{};
        final rename = <String, int>{};
        final renameIds = <String, List<String>>{};
        final tokens = <String, int>{};
        final tokenIds = <String, List<String>>{};
        final timings = <int>[];
        var noEmail = 0;

        final uids = authIndex.keys.toList()..sort();
        for (final uid in uids) {
          final tipperId = '${authIndex[uid]}';
          final privateRecord = Map<String, Object?>.from(
            (privateRecords[tipperId] as Map?) ?? const {},
          );
          final email = (privateRecord['logon'] ?? privateRecord['email'])
              ?.toString();
          if (email == null || email.trim().isEmpty) {
            noEmail += 1;
            continue;
          }
          final caller = callerToken(uid, email);

          // 1. Sign-in: the refresh every user does first.
          final timer = Stopwatch()..start();
          try {
            final result = await linkOrCreateTipper(
              database: db,
              caller: caller,
              request: const LinkOrCreateTipperRequest(),
              admission: admission,
              nowMs: () => _now,
            );
            final label =
                'existing' == result.outcome.wire && result.tipperId == tipperId
                ? 'existing'
                : 'WRONG:${result.outcome.wire}';
            _count(signIn, label);
            (signInIds[label] ??= []).add(tipperId);
          } on Object catch (error) {
            final label = _label(error);
            _count(signIn, label);
            (signInIds[label] ??= []).add(tipperId);
          }
          timings.add(timer.elapsedMilliseconds);

          // 2. Renaming to the name already held: the nothing-to-change path.
          final name = (publicRecords[tipperId] as Map?)?['name']?.toString();
          if (name != null) {
            try {
              await updateTipperAlias(
                database: db,
                caller: caller,
                request: UpdateTipperAliasRequest(alias: name),
                admission: admission,
                nowMs: () => _now,
              );
              _count(rename, 'ok');
            } on Object catch (error) {
              final label = _label(error);
              _count(rename, label);
              (renameIds[label] ??= []).add(tipperId);
            }
          }

          // 3. A device token registered and removed again.
          final token = 'replay-token-$tipperId';
          try {
            await registerDeviceToken(
              database: db,
              caller: caller,
              request: DeviceTokenRequest(token: token),
              nowMs: () => _now,
            );
            final removed = await unregisterDeviceToken(
              database: db,
              caller: caller,
              request: DeviceTokenRequest(token: token),
            );
            _count(tokens, removed.removed ? 'ok' : 'NOT-REMOVED');
          } on Object catch (error) {
            final label = _label(error);
            _count(tokens, label);
            (tokenIds[label] ??= []).add(tipperId);
          }
        }

        timings.sort();
        final after = await readRoot(db);
        Map<String, Object?> nodeOf(Map<String, Object?> root, String name) =>
            Map<String, Object?>.from((root[name] as Map?) ?? const {});

        final logonBefore = nodeOf(before, 'LogonIndex').length;
        final logonAfter = nodeOf(after, 'LogonIndex').length;
        final publicNames = <String, Object?>{
          for (final entry in nodeOf(after, 'AllTippers').entries)
            entry.key: (entry.value as Map)['name'],
        };
        final namesBefore = <String, Object?>{
          for (final entry in nodeOf(before, 'AllTippers').entries)
            entry.key: (entry.value as Map)['name'],
        };

        // ignore: avoid_print
        print(
          '\nReplay of ${uids.length} linked accounts ($noEmail with no address to sign in with):',
        );
        _report('sign-in (link-or-create-tipper)', signIn, signInIds);
        _report(
          'rename to the current name (update-tipper-alias)',
          rename,
          renameIds,
        );
        _report('register then unregister a token', tokens, tokenIds);
        // ignore: avoid_print
        print(
          '  sign-in time in the emulator: median ${timings.isEmpty ? 0 : timings[timings.length ~/ 2]} ms, '
          'slowest ${timings.isEmpty ? 0 : timings.last} ms',
        );
        // ignore: avoid_print
        print(
          '  LogonIndex ${logonBefore} -> $logonAfter entries '
          '(accounts that had no stored login are given one)',
        );

        // Nothing about who owns what may change.
        expect(
          canonical(nodeOf(after, 'AuthIndex')),
          canonical(nodeOf(before, 'AuthIndex')),
          reason: 'no account link changed',
        );
        expect(
          canonical(nodeOf(after, 'AliasIndex')),
          canonical(nodeOf(before, 'AliasIndex')),
          reason: 'no alias claim changed',
        );
        expect(
          canonical(publicNames),
          canonical(namesBefore),
          reason: 'no public name changed',
        );
        expect(
          nodeOf(after, 'AllTippers').length,
          nodeOf(before, 'AllTippers').length,
          reason: 'no tipper record was created or lost',
        );
        expect(after['IdentityLocks'], isNull, reason: 'no lease left behind');
        expect(
          after['ClaimMoves'],
          isNull,
          reason: 'no half-done move left behind',
        );
        expect(
          after['CreateIntents'],
          isNull,
          reason: 'no half-done create left behind',
        );

        // Every linked account was replayed (one with nothing to sign in with is a data fault).
        expect(
          noEmail,
          0,
          reason: 'every linked account has an address to sign in with',
        );
        expect(
          signIn.values.fold<int>(0, (sum, n) => sum + n),
          uids.length,
          reason: 'every linked account was replayed',
        );

        // Every sign-in and every rename and token trip worked.
        expect(signIn.keys.toSet(), {
          'existing',
        }, reason: 'every linked account refreshed as existing');
        expect(
          rename.keys.toSet().difference({'ok'}),
          isEmpty,
          reason: 'every rename-to-itself worked',
        );
        expect(tokens.keys.toSet(), {
          'ok',
        }, reason: 'every token went in and out');
      },
      skip: _skipReason(),
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}
