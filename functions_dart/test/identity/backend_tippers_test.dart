import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/backend_tippers.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

import '../support/tipper_view.dart';

class _Snapshot {
  _Snapshot(this.value);

  final Object? value;
}

class _Ref {
  _Ref(this._value);

  final Object? _value;

  Future<_Snapshot> once() async => _Snapshot(_value);
}

/// The two calls the backend loaders make on any database handle:
/// `ref(path).once()` and `.value`.
class _Database {
  _Database(this._root);

  final Map<String, Object?> _root;

  _Ref ref(String path) {
    Object? node = _root;
    for (final segment in path.split('/').where((s) => s.isNotEmpty)) {
      node = node is Map ? node[segment] : null;
    }
    return _Ref(node);
  }
}

Map<String, Object?> _publicFields(Map<String, Object?> full) => {
  for (final field in tipperPublicFieldNames)
    if (full.containsKey(field)) field: full[field],
};

Map<String, Object?> _privateFields(Map<String, Object?> full) => {
  for (final field in tipperPrivateFieldNames)
    if (full.containsKey(field)) field: full[field],
};

const String _publicNode = 'AllTippers';
const String _privateNode = 'TipperPrivate';

final Map<String, Map<String, Object?>> _legacyTippers = {
  'paid': {
    'name': 'Paid Pat',
    'photoURL': 'https://example.com/pat.png',
    'compsParticipatedIn': ['comp-1', 'comp-2'],
    'authuid': 'auth-paid',
    'tipperRole': 'admin',
    'email': 'pat@example.com',
    'logon': 'pat.login@example.com',
    'isAnonymous': false,
    'acctCreatedUTC': '2025-02-01T03:04:05.000Z',
    'acctLoggedOnUTC': '2026-03-01T04:05:06.000Z',
  },
  'anon': {
    'name': 'Guest',
    'authuid': 'auth-anon',
    'tipperRole': 'tipper',
    'isAnonymous': true,
  },
  'unpaid': {
    'name': 'Unpaid Uma',
    'authuid': 'auth-unpaid',
    'tipperRole': 'tipper',
    'email': 'uma@example.com',
    'isAnonymous': false,
  },
};

/// Today: everything in the public record, no private record at all.
_Database _legacyShape() =>
    _Database({_publicNode: Map<String, Object?>.of(_legacyTippers)});

/// Coexistence: the legacy public record plus the private record beside it.
_Database _coexistingShape() => _Database({
  _publicNode: Map<String, Object?>.of(_legacyTippers),
  _privateNode: {
    for (final entry in _legacyTippers.entries)
      entry.key: _privateFields(entry.value),
  },
});

/// After the purge: public record holds only the public fields.
_Database _purgedShape() => _Database({
  _publicNode: {
    for (final entry in _legacyTippers.entries)
      entry.key: _publicFields(entry.value),
  },
  _privateNode: {
    for (final entry in _legacyTippers.entries)
      entry.key: _privateFields(entry.value),
  },
});

Future<Map<String, Map<String, Object?>>> _loadAll(_Database db) async => {
  for (final tipper in await loadBackendTippers(db))
    tipper.dbkey!: tipperView(tipper),
};

void main() {
  group('mergeTipperRecords', () {
    test('a field the public record carries wins over the private copy', () {
      final merged = mergeTipperRecords(
        {'name': 'Pat', 'isAnonymous': false},
        {'isAnonymous': true, 'email': 'pat@example.com'},
      );
      expect(merged['isAnonymous'], false);
      expect(merged['email'], 'pat@example.com');
    });

    test('the private record fills what the purge removed', () {
      final merged = mergeTipperRecords(
        {
          'name': 'Pat',
          'compsParticipatedIn': ['comp-1'],
        },
        {'isAnonymous': true, 'authuid': 'auth-pat', 'tipperRole': 'admin'},
      );
      expect(merged, {
        'name': 'Pat',
        'compsParticipatedIn': ['comp-1'],
        'isAnonymous': true,
        'authuid': 'auth-pat',
        'tipperRole': 'admin',
      });
    });

    test(
      'a missing or malformed private record leaves the public one as it is',
      () {
        expect(mergeTipperRecords({'name': 'Pat'}, null), {'name': 'Pat'});
        expect(mergeTipperRecords({'name': 'Pat'}, 'oops'), {'name': 'Pat'});
      },
    );

    test('only the private field names are ever copied across', () {
      final merged = mergeTipperRecords(
        {'name': 'Pat'},
        {
          'name': 'Someone else',
          'compsParticipatedIn': ['comp-9'],
          'stray': 1,
        },
      );
      expect(merged, {'name': 'Pat'});
    });
  });

  group('loadBackendTippers sees the same tippers in every data shape', () {
    test('coexisting records read the same as legacy ones', () async {
      expect(
        await _loadAll(_coexistingShape()),
        await _loadAll(_legacyShape()),
      );
    });

    test('purged records read the same as legacy ones', () async {
      expect(await _loadAll(_purgedShape()), await _loadAll(_legacyShape()));
    });

    test(
      'an anonymous tipper stays anonymous and paid after the purge',
      () async {
        final tippers = await _loadAll(_purgedShape());
        expect(tippers['anon']!['isAnonymous'], true);
        final anonymous = (await loadBackendTippers(
          _purgedShape(),
        )).firstWhere((tipper) => tipper.dbkey == 'anon');
        expect(anonymous.paidForComp(null), true);
      },
    );

    test(
      'without the private record a purged tipper would read as ordinary',
      () async {
        final withoutPrivate = _Database({
          _publicNode: {
            for (final entry in _legacyTippers.entries)
              entry.key: _publicFields(entry.value),
          },
        });
        final tippers = await _loadAll(withoutPrivate);
        expect(tippers['anon']!['isAnonymous'], false);
      },
    );

    test('a newer public write wins until the purge removes it', () async {
      final records = Map<String, Object?>.of(_legacyTippers);
      records['anon'] = {..._legacyTippers['anon']!, 'isAnonymous': false};
      final db = _Database({
        _publicNode: records,
        _privateNode: {
          for (final entry in _legacyTippers.entries)
            entry.key: _privateFields(entry.value),
        },
      });
      expect((await _loadAll(db))['anon']!['isAnonymous'], false);
    });

    test('no tippers, no public list or a non-record entry', () async {
      expect(await loadBackendTippers(_Database({})), isEmpty);
      expect(
        await loadBackendTippers(
          _Database({
            _publicNode: {'bad': 'not a record'},
          }),
        ),
        isEmpty,
      );
    });

    test('a private record with no public record is not a tipper', () async {
      final db = _Database({
        _publicNode: {'paid': _publicFields(_legacyTippers['paid']!)},
        _privateNode: {
          'paid': _privateFields(_legacyTippers['paid']!),
          'orphan': {'authuid': 'auth-orphan', 'isAnonymous': true},
        },
      });
      expect((await _loadAll(db)).keys, ['paid']);
    });

    test(
      'an unknown role or a stray type is an ordinary tipper, not a crash',
      () async {
        final db = _Database({
          _publicNode: {
            'odd': {'name': 'Odd', 'compsParticipatedIn': 'comp-1'},
          },
          _privateNode: {
            'odd': {'tipperRole': 'superuser', 'isAnonymous': 'yes'},
          },
        });
        final odd = (await loadBackendTippers(db)).single;
        expect(odd.tipperRole, TipperRole.tipper);
        expect(odd.isAnonymous, false);
        expect(odd.compsPaidFor, isEmpty);
      },
    );

    test('compsParticipatedIn may be a list or a map of keys', () async {
      final db = _Database({
        _publicNode: {
          'list': {
            'name': 'L',
            'compsParticipatedIn': ['a', ' b ', ''],
          },
          'map': {
            'name': 'M',
            'compsParticipatedIn': {'0': 'c', '1': 'd'},
          },
        },
      });
      final byKey = await _loadAll(db);
      expect(byKey['list']!['compsPaidFor'], ['a', 'b']);
      expect(byKey['map']!['compsPaidFor'], ['c', 'd']);
    });
  });

  group('loadBackendTipper', () {
    test('reads one tipper the same way in every data shape', () async {
      final legacy = tipperView(
        await loadBackendTipper(_legacyShape(), 'anon'),
      );
      expect(
        tipperView(await loadBackendTipper(_coexistingShape(), 'anon')),
        legacy,
      );
      expect(
        tipperView(await loadBackendTipper(_purgedShape(), 'anon')),
        legacy,
      );
      expect(legacy['isAnonymous'], true);
    });

    test('a missing tipper is a not-found error', () async {
      await expectLater(
        loadBackendTipper(_purgedShape(), 'nobody'),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('a private record alone is not enough to find a tipper', () async {
      final db = _Database({
        _privateNode: {
          'orphan': {'authuid': 'auth-orphan'},
        },
      });
      await expectLater(
        loadBackendTipper(db, 'orphan'),
        throwsA(isA<NotFoundError>()),
      );
    });
  });
}
