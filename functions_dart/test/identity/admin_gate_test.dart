// Who counts as an administrator: the same test as the R2 database rules.
import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admin_gate.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _uid = 'uidAdmin000000000000000000001';

void main() {
  /// A reader over a map of path to value that notes every path it is asked for.
  ({List<String> reads, Future<Object?> Function(String) read}) database(
    Map<String, Object?> values,
  ) {
    final reads = <String>[];
    return (
      reads: reads,
      read: (path) async {
        reads.add(path);
        return values[path];
      },
    );
  }

  Map<String, Object?> linked({
    String role = 'admin',
    String recordedUid = _uid,
    String tipperId = 'tipper-1',
  }) => {
    '/AuthIndex/$_uid': tipperId,
    '/TipperPrivate/$tipperId': {'authuid': recordedUid, 'tipperRole': role},
  };

  Future<void> check(Map<String, Object?> values, [String uid = _uid]) =>
      requireAdministratorUid(database(values).read, uid);

  group('an administrator', () {
    test(
      'is the tipper the account is indexed to, whose record names it back and says admin',
      () async {
        await check(linked());
      },
    );

    test('is checked against exactly the two identity records', () async {
      final db = database(linked());

      await requireAdministratorUid(db.read, _uid);

      expect(db.reads, ['/AuthIndex/$_uid', '/TipperPrivate/tipper-1']);
    });
  });

  group('no one else is, and the refusal is the same whatever the reason', () {
    final refusals = <String, Map<String, Object?>>{
      'an ordinary tipper': linked(role: 'tipper'),
      'a role in the wrong case': linked(role: 'Admin'),
      'a missing role': {
        '/AuthIndex/$_uid': 'tipper-1',
        '/TipperPrivate/tipper-1': {'authuid': _uid},
      },
      'a record that names someone else': linked(recordedUid: 'someone-else'),
      'an account with no index entry': {
        '/TipperPrivate/tipper-1': {'authuid': _uid, 'tipperRole': 'admin'},
      },
      'an index entry with no private record': {'/AuthIndex/$_uid': 'tipper-1'},
      'an index entry that is not a tipper id': {
        '/AuthIndex/$_uid': {'tipper-1': true},
      },
      'an index entry that is not a usable key': linked(tipperId: 'a/b'),
      'a forged public record': {
        '/AllTippers/tipper-1': {'authuid': _uid, 'tipperRole': 'admin'},
      },
    };

    for (final entry in refusals.entries) {
      test(entry.key, () async {
        await expectLater(
          check(entry.value),
          throwsA(
            isA<PermissionDeniedError>().having(
              (e) => '${e.details}',
              'details',
              contains('not_admin'),
            ),
          ),
        );
      });
    }

    test('an account id that cannot be a database key', () async {
      await expectLater(
        requireAdministratorUid(database(const {}).read, 'a/b'),
        throwsA(isA<PermissionDeniedError>()),
      );
    });
  });

  test('a failed read refuses the call instead of passing it', () async {
    await expectLater(
      requireAdministratorUid(
        (path) async => throw StateError('the database could not be read'),
        _uid,
      ),
      throwsStateError,
    );
  });

  group('for a callable', () {
    test('an anonymous caller is refused without reading anything', () async {
      var requests = 0;
      final unused = RestDatabase(
        client: MockClient((request) async {
          requests++;
          return http.Response('null', 200);
        }),
        databaseUrl: 'http://127.0.0.1:9/?ns=unused',
      );

      await expectLater(
        requireAdmin(
          unused,
          const CallerToken(uid: _uid, signInProvider: 'anonymous'),
        ),
        throwsA(isA<PermissionDeniedError>()),
      );
      expect(requests, 0);
    });
  });
}
