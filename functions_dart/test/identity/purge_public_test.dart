import 'dart:convert';

import 'package:dart_functions/identity/purge_public.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

/// A public record as a 1.4.x client left it: the three public fields and the
/// seven private ones.
Map<String, Object?> _legacy({
  String name = 'Alice',
  String uid = 'uid-alice',
  String? loggedOn = '2026-10-01T02:03:04.000Z',
  Map<String, Object?> extra = const {},
}) => <String, Object?>{
  'name': name,
  'photoURL': 'a.png',
  'compsParticipatedIn': <String>['c1'],
  'authuid': uid,
  'tipperRole': 'tipper',
  'email': 'alice@example.test',
  'logon': 'alice@example.test',
  'isAnonymous': false,
  'acctCreatedUTC': '2025-01-01T00:00:00.000Z',
  'acctLoggedOnUTC': ?loggedOn,
  ...extra,
};

/// The private record that goes with [_legacy].
Map<String, Object?> _private({
  String uid = 'uid-alice',
  String? loggedOn = '2026-10-01T02:03:04.000Z',
  Map<String, Object?> overrides = const {},
}) => <String, Object?>{
  'authuid': uid,
  'tipperRole': 'tipper',
  'email': 'alice@example.test',
  'logon': 'alice@example.test',
  'isAnonymous': false,
  'acctCreatedUTC': '2025-01-01T00:00:00.000Z',
  'acctLoggedOnUTC': ?loggedOn,
  ...overrides,
};

PurgePlan plan(Object? tippers, Object? tipperPrivate) =>
    planPublicIdentityPurge(tippers: tippers, tipperPrivate: tipperPrivate);

/// Applies a plan's patch to the two nodes, as the database would.
({Map<String, Object?> tippers, Map<String, Object?> private}) apply(
  Map<String, Object?> tippers,
  Map<String, Object?> tipperPrivate,
  Map<String, Object?> patch,
) {
  final data = <String, Object?>{
    'AllTippers': jsonDecode(jsonEncode(tippers)),
    'TipperPrivate': jsonDecode(jsonEncode(tipperPrivate)),
  };
  for (final entry in patch.entries) {
    final parts = entry.key.split('/');
    var node = data;
    for (final part in parts.take(parts.length - 1)) {
      node = (node[part] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    if (entry.value == null) {
      node.remove(parts.last);
    } else {
      node[parts.last] = entry.value;
    }
  }
  return (
    tippers: Map<String, Object?>.from(data['AllTippers']! as Map),
    private: Map<String, Object?>.from(data['TipperPrivate']! as Map),
  );
}

void main() {
  group('an ordinary record', () {
    test('loses the seven private fields, and keeps the public ones', () {
      final result = plan({'t1': _legacy()}, {'t1': _private()});

      expect(result.isBlocked, isFalse);
      expect(result.recordsToPurge, 1);
      expect(result.fieldsToRemove, 7);
      expect(result.patch.keys, [
        for (final field in tipperPrivateFieldNames) 'AllTippers/t1/$field',
      ]);
      expect(result.patch.values, everyElement(isNull));
    });

    test(
      'also loses the two legacy fields, with or without a private record behind them',
      () {
        final result = plan(
          {
            't1': _legacy(extra: {'active': true, 'tipperID': 'old'}),
            't2': {'name': 'Legacy only', 'active': true},
          },
          {'t1': _private()},
        );

        expect(result.patch['AllTippers/t1/active'], isNull);
        expect(result.patch.containsKey('AllTippers/t1/tipperID'), isTrue);
        expect(result.patch.containsKey('AllTippers/t2/active'), isTrue);
        expect(result.fieldsToRemove, 10);
      },
    );

    test('is gone on a second run: the plan on purged data is empty', () {
      final tippers = {
        't1': _legacy(),
        't2': _legacy(name: 'Bob', uid: 'uid-bob'),
      };
      final privates = {'t1': _private(), 't2': _private(uid: 'uid-bob')};
      final first = plan(tippers, privates);

      final after = apply(tippers, privates, first.patch);

      expect(plan(after.tippers, after.private).isEmpty, isTrue);
      expect(after.tippers['t1'], {
        'name': 'Alice',
        'photoURL': 'a.png',
        'compsParticipatedIn': ['c1'],
      });
    });
  });

  group('a tipper with no public field left', () {
    test('is given a placeholder name so the record does not vanish', () {
      final result = plan(
        {
          'tNoAlias123456': {
            'authuid': 'uid-x',
            'tipperRole': 'tipper',
            'email': 'x@example.test',
            'logon': 'x@example.test',
            'isAnonymous': false,
          },
        },
        {
          'tNoAlias123456': {
            'authuid': 'uid-x',
            'tipperRole': 'tipper',
            'email': 'x@example.test',
            'logon': 'x@example.test',
            'isAnonymous': false,
          },
        },
      );

      expect(result.placeholderNames, 1);
      expect(
        result.patch['AllTippers/tNoAlias123456/name'],
        placeholderTipperName('tNoAlias123456'),
      );
    });

    test('but one with a photo and no name is not renamed', () {
      final result = plan(
        {
          't1': {
            'photoURL': 'p.png',
            'authuid': 'uid-alice',
            'tipperRole': 'tipper',
            'email': 'alice@example.test',
            'logon': 'alice@example.test',
            'isAnonymous': false,
          },
        },
        {'t1': _private(loggedOn: null)..remove('acctCreatedUTC')},
      );

      expect(result.placeholderNames, 0);
    });
  });

  group('login times', () {
    test('a later public time is written to the private record, not lost', () {
      final result = plan(
        {'t1': _legacy(loggedOn: '2026-11-02T10:00:00.000Z')},
        {'t1': _private(loggedOn: '2026-10-01T02:03:04.000Z')},
      );

      expect(result.isBlocked, isFalse);
      expect(result.loginTimesPreserved, 1);
      expect(
        result.patch['TipperPrivate/t1/acctLoggedOnUTC'],
        '2026-11-02T10:00:00.000Z',
      );
      expect(result.patch.containsKey('AllTippers/t1/acctLoggedOnUTC'), isTrue);
    });

    test('and after the purge the private record holds the later time', () {
      final tippers = {'t1': _legacy(loggedOn: '2026-11-02T10:00:00.000Z')};
      final privates = {'t1': _private()};

      final after = apply(tippers, privates, plan(tippers, privates).patch);

      expect(
        (after.private['t1']! as Map)['acctLoggedOnUTC'],
        '2026-11-02T10:00:00.000Z',
      );
    });

    test(
      'an older or equal public time is simply removed; the private one stays',
      () {
        final older = plan(
          {'t1': _legacy(loggedOn: '2026-09-01T00:00:00.000Z')},
          {'t1': _private()},
        );

        expect(older.loginTimesPreserved, 0);
        expect(
          older.patch.containsKey('TipperPrivate/t1/acctLoggedOnUTC'),
          isFalse,
        );
        expect(older.isBlocked, isFalse);
      },
    );

    test('the same instant written differently is the same time', () {
      final result = plan(
        {'t1': _legacy(loggedOn: '2026-10-01 02:03:04.000Z')},
        {'t1': _private(loggedOn: '2026-10-01T02:03:04Z')},
      );

      expect(result.isBlocked, isFalse);
      expect(result.loginTimesPreserved, 0);
    });

    test(
      'a creation time written differently is the same time, a different one is not',
      () {
        final same = plan(
          {
            't1': _legacy(
              extra: {'acctCreatedUTC': '2025-01-01 00:00:00.000Z'},
            ),
          },
          {
            't1': _private(
              overrides: {'acctCreatedUTC': '2025-01-01T00:00:00Z'},
            ),
          },
        );
        final different = plan(
          {
            't1': _legacy(
              extra: {'acctCreatedUTC': '2025-01-02T00:00:00.000Z'},
            ),
          },
          {'t1': _private()},
        );

        expect(same.isBlocked, isFalse);
        expect(different.isBlocked, isTrue);
      },
    );

    test('a time that cannot be read blocks, rather than being guessed at', () {
      final result = plan(
        {'t1': _legacy(loggedOn: 'yesterday')},
        {'t1': _private()},
      );

      expect(result.isBlocked, isTrue);
      expect(
        result.blocking.single.problem,
        contains('acctLoggedOnUTC cannot be compared'),
      );
    });

    test('a public time with no private one is in the public record only', () {
      final result = plan({'t1': _legacy()}, {'t1': _private(loggedOn: null)});

      expect(result.isBlocked, isTrue);
      expect(
        result.blocking.single.problem,
        contains('acctLoggedOnUTC is in the public record only'),
      );
    });
  });

  group('an unresolved record blocks the whole plan', () {
    test('a public record with identity fields and no private record', () {
      final result = plan(
        {'t1': _legacy(), 't2': _legacy(name: 'Bob', uid: 'uid-bob')},
        {'t2': _private(uid: 'uid-bob')},
      );

      expect(result.isBlocked, isTrue);
      expect(result.blocking.single.tipperId, 't1');
      expect(result.blocking.single.problem, contains('no private record'));
      expect(result.blocking.single.problem, contains('final backfill'));
    });

    test('a field that differs between the two copies', () {
      for (final field in [
        'tipperRole',
        'email',
        'logon',
        'authuid',
        'isAnonymous',
        'acctCreatedUTC',
      ]) {
        final differing = <String, Object?>{
          'tipperRole': 'admin',
          'email': 'other@example.test',
          'logon': 'other@example.test',
          'authuid': 'uid-other',
          'isAnonymous': true,
          'acctCreatedUTC': '2024-01-01T00:00:00.000Z',
        };
        final result = plan(
          {'t1': _legacy()},
          {
            't1': _private(overrides: {field: differing[field]}),
          },
        );

        expect(result.isBlocked, isTrue, reason: field);
        expect(result.blocking.single.problem, contains('$field differs'));
      }
    });

    test('a field the public record has and the private one lacks', () {
      final result = plan(
        {'t1': _legacy()},
        {'t1': _private()..remove('email')},
      );

      expect(result.isBlocked, isTrue);
      expect(
        result.blocking.single.problem,
        contains('email is in the public record only'),
      );
    });

    test(
      'says everything that is wrong with a record, and every record, by opaque id',
      () {
        final result = plan(
          {
            't1': _legacy(),
            't2': _legacy(name: 'Bob'),
            't3': _legacy(name: 'Cy', uid: 'uid-cy'),
          },
          {
            't1': _private(
              overrides: {'email': 'x@example.test', 'logon': 'y@example.test'},
            ),
            't3': _private(uid: 'uid-cy'),
          },
        );

        expect(result.blocking.map((f) => f.tipperId), ['t1', 't2']);
        expect(
          result.blocking.first.problem,
          allOf(contains('email differs'), contains('logon differs')),
        );
      },
    );
  });

  group('an unlinked historical tipper', () {
    test('the empty public authuid equals a private record with none', () {
      final result = plan(
        {'t1': _legacy(uid: '')},
        {'t1': _private()..remove('authuid')},
      );

      expect(result.isBlocked, isFalse);
      expect(result.patch.containsKey('AllTippers/t1/authuid'), isTrue);
    });

    test(
      'but an empty public authuid against a real private one is a difference',
      () {
        final result = plan({'t1': _legacy(uid: '')}, {'t1': _private()});

        expect(result.isBlocked, isTrue);
      },
    );
  });

  group('what the plan reveals', () {
    test('the patch holds no email address, login or account id', () {
      final result = plan(
        {'t1': _legacy(loggedOn: '2026-11-02T10:00:00.000Z')},
        {'t1': _private()},
      );

      final text = jsonEncode(result.patch);

      expect(text, isNot(contains('example.test')));
      expect(text, isNot(contains('uid-alice')));
    });

    test('a finding names the opaque id and fields, never a value', () {
      final result = plan(
        {'t1': _legacy()},
        {
          't1': _private(overrides: {'email': 'secret@example.test'}),
        },
      );

      expect('${result.blocking.single}', isNot(contains('example.test')));
    });
  });

  group('a tipper who deleted their account', () {
    // What the account deletion leaves: the public record has the placeholder
    // name and an empty authuid (never a missing one), the private record has no
    // authuid, email or login and says when the account went.
    Map<String, Object?> deletedPublic() => <String, Object?>{
      'name': deletedTipperName,
      'compsParticipatedIn': <String>['c1'],
      'authuid': '',
      'tipperRole': 'tipper',
      'isAnonymous': false,
      'acctCreatedUTC': '2025-01-01T00:00:00.000Z',
      'acctLoggedOnUTC': '2026-10-01T02:03:04.000Z',
    };
    Map<String, Object?> deletedPrivate() => <String, Object?>{
      'tipperRole': 'tipper',
      'isAnonymous': false,
      'acctCreatedUTC': '2025-01-01T00:00:00.000Z',
      'acctLoggedOnUTC': '2026-10-01T02:03:04.000Z',
      tipperAccountDeletedField: '2026-11-11 09:00:00.000Z',
    };

    test('is purged like any other and never blocks the plan', () {
      final result = plan(
        <String, Object?>{'t1': deletedPublic()},
        <String, Object?>{'t1': deletedPrivate()},
      );

      expect(result.isBlocked, isFalse, reason: '${result.blocking}');
      final applied = apply(
        <String, Object?>{'t1': deletedPublic()},
        <String, Object?>{'t1': deletedPrivate()},
        result.patch,
      );
      expect(applied.tippers['t1'], <String, Object?>{
        'name': deletedTipperName,
        'compsParticipatedIn': <String>['c1'],
      });
      expect(
        (applied.private['t1']! as Map)[tipperAccountDeletedField],
        '2026-11-11 09:00:00.000Z',
        reason: 'the marker is private and is never moved or lost',
      );
    });

    test('the purge is a no-op once done', () {
      final result = plan(
        <String, Object?>{
          't1': <String, Object?>{
            'name': deletedTipperName,
            'compsParticipatedIn': <String>['c1'],
          },
        },
        <String, Object?>{'t1': deletedPrivate()},
      );
      expect(result.isEmpty, isTrue);
    });
  });

  test('nothing to purge in an empty or missing node', () {
    expect(plan(null, null).isEmpty, isTrue);
    expect(plan(<String, Object?>{}, <String, Object?>{}).isEmpty, isTrue);
  });
}
