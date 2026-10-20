import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

void main() {
  group('isValidRtdbKey', () {
    test('accepts ids the database and Firebase Auth generate', () {
      for (final key in [
        '-OK4hy0GM78N5hHC7zGH',
        'wL5RTfZrN2MBUkQvC0S7HyUJ3fE2',
        'bigfan',
        '老虎',
        'a_b-c=d',
        'x' * maxRtdbKeyBytes,
      ]) {
        expect(isValidRtdbKey(key), isTrue, reason: key);
      }
    });

    test('rejects characters the database forbids', () {
      for (final key in ['a.b', r'a$b', 'a#b', 'a[0]', 'a]b', 'a/b', '/']) {
        expect(isValidRtdbKey(key), isFalse, reason: key);
      }
    });

    test('rejects empty keys and control characters', () {
      for (final key in ['', 'a\nb', 'a\u0000b', 'a\u007fb', '\t']) {
        expect(isValidRtdbKey(key), isFalse, reason: key.codeUnits.toString());
      }
    });

    test('rejects keys over the byte limit, counting bytes not characters', () {
      expect(isValidRtdbKey('x' * (maxRtdbKeyBytes + 1)), isFalse);
      expect(isValidRtdbKey('é' * (maxRtdbKeyBytes ~/ 2 + 1)), isFalse);
      expect(isValidRtdbKey('é' * (maxRtdbKeyBytes ~/ 2)), isTrue);
    });
  });
}
