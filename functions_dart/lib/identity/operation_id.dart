import 'dart:math';

/// A new unique id for one identity operation (a request, a merge).
///
/// 128 random bits as 32 lower-case hex characters: a valid database key with
/// no `|`, so it can be a lease owner, a journal key and an in-flight marker.
/// Uses a secure random source unless a [random] is supplied for a test.
String newOperationId({Random? random}) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 4; index++) {
    buffer.write(source.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'));
  }
  return buffer.toString();
}
