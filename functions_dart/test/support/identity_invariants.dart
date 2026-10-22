import 'dart:convert';

import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:test/test.dart';

/// The whole database as nested maps.
Future<Map<String, Object?>> readRoot(RestDatabase database) async {
  final value = (await database.ref('/').once()).value;
  return value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
}

Map<String, Object?> _node(Map<String, Object?> root, String key) {
  final value = root[key];
  return value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
}

/// A canonical text of [value], so two databases can be compared exactly.
String canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final key in (value.keys.map((k) => '$k').toList()..sort()))
        key: _sorted(value[key]),
    };
  }
  if (value is List) {
    return value.map(_sorted).toList();
  }
  return value;
}

/// Everything that must hold in the identity data whenever no operation is
/// running (the properties the scheduled audit will check): the two directions
/// of the account link agree, every claim points at an existing record that
/// still has that alias or login, no tipper has two accounts, and nothing is
/// left half done. [allowPending] permits a leftover intent, journal or lease,
/// for the moment right after a simulated crash.
void expectIdentityConsistent(
  Map<String, Object?> root, {
  bool allowPending = false,
}) {
  final tippers = _node(root, 'AllTippers');
  final private = _node(root, 'TipperPrivate');
  final authIndex = _node(root, 'AuthIndex');
  final aliasIndex = _node(root, 'AliasIndex');
  final logonIndex = _node(root, 'LogonIndex');

  final accountOf = <String, String>{};
  for (final entry in authIndex.entries) {
    final id = '${entry.value}';
    final record = private[id];
    expect(
      record,
      isA<Map>(),
      reason: 'AuthIndex[${entry.key}] -> $id has no private record',
    );
    expect(
      (record as Map)['authuid'],
      entry.key,
      reason: 'private authuid of $id disagrees with the index',
    );
    expect(
      tippers[id],
      isA<Map>(),
      reason: '$id is indexed but has no public record',
    );
    expect(accountOf.containsKey(id), false, reason: '$id has two accounts');
    accountOf[id] = entry.key;
  }

  for (final entry in aliasIndex.entries) {
    final id = '${entry.value}';
    final record = tippers[id];
    if (allowPending && record == null) {
      continue; // a create claimed it and crashed before writing the record
    }
    expect(
      record,
      isA<Map>(),
      reason: 'alias ${entry.key} points at missing $id',
    );
    final name = (record as Map)['name'];
    if (!allowPending) {
      expect(name, isA<String>(), reason: '$id has an alias claim but no name');
      expect(
        aliasIndexKey(name as String),
        entry.key,
        reason: 'alias claim of $id does not match its name',
      );
    }
  }

  for (final entry in logonIndex.entries) {
    final id = '${entry.value}';
    final record = private[id];
    if (allowPending && record == null) {
      continue;
    }
    expect(
      record,
      isA<Map>(),
      reason: 'login ${entry.key} points at missing $id',
    );
    final logon = (record as Map)['logon'];
    if (!allowPending) {
      expect(
        logon,
        isA<String>(),
        reason: '$id has a login claim but no login',
      );
      expect(
        logonIndexKey(logon as String),
        entry.key,
        reason: 'login claim of $id does not match its login',
      );
    }
  }

  if (!allowPending) {
    expect(
      _node(root, 'ClaimMoves'),
      isEmpty,
      reason: 'a claim move was left half done',
    );
    expect(
      _node(root, 'CreateIntents'),
      isEmpty,
      reason: 'a create intent was left behind',
    );
    expect(
      _node(root, 'IdentityLocks'),
      isEmpty,
      reason: 'a lease was left behind',
    );
  }
}
