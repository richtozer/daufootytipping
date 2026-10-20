import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/keys.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

List<Map<String, Object?>> _vectors(String section) {
  final file = File('../config/identity-vectors.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return (json[section]! as List).cast<Map<String, Object?>>();
}

void main() {
  group('logonIndexKey', () {
    test('matches the hashes Node computed for the shared vectors', () {
      final vectors = _vectors('emails');
      expect(vectors, isNotEmpty);
      for (final vector in vectors) {
        expect(
          logonIndexKey(vector['input']! as String),
          vector['logonIndexKey'],
          reason: 'input: ${vector['input']}',
        );
      }
    });

    test('is the same for every spelling of one address', () {
      final keys = {
        logonIndexKey('tipper@example.com'),
        logonIndexKey('Tipper@Example.COM'),
        logonIndexKey('  tipper@example.com  '),
      };
      expect(keys, hasLength(1));
    });

    test('differs for different addresses', () {
      expect(
        logonIndexKey('a@example.com'),
        isNot(logonIndexKey('b@example.com')),
      );
    });

    test('is always a valid 43 character database key without the address', () {
      for (final email in ['a@b.c', 'first.last+tag@sub.example.co.uk']) {
        final key = logonIndexKey(email);
        expect(key, hasLength(43));
        expect(isValidRtdbKey(key), isTrue);
        expect(key, isNot(contains('@')));
        expect(key, isNot(contains('=')));
      }
    });

    test('refuses a blank address instead of hashing the empty string', () {
      expect(() => logonIndexKey(''), throwsArgumentError);
      expect(() => logonIndexKey('   '), throwsArgumentError);
    });
  });

  group('aliasIndexKey', () {
    test('is the normalised alias', () {
      expect(aliasIndexKey('  Big  Fan '), 'bigfan');
    });

    test('matches the shared vectors for every allowed alias', () {
      for (final vector in _vectors('aliases')) {
        final input = vector['input']! as String;
        if (!isValidAlias(input)) {
          expect(
            () => aliasIndexKey(input),
            throwsArgumentError,
            reason: 'input: $input',
          );
          continue;
        }
        expect(
          aliasIndexKey(input),
          vector['normalised'],
          reason: 'input: $input',
        );
      }
    });

    test('refuses aliases that cannot be claimed', () {
      for (final alias in ['', '   ', '😀😀', 'x' * (maxAliasLength + 1)]) {
        expect(() => aliasIndexKey(alias), throwsArgumentError, reason: alias);
      }
    });
  });
}
