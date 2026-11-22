import 'dart:math';

const String _alphabet =
    '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

/// A new tipper id in the Firebase push-id format: 8 characters of time, so ids
/// sort by creation, then 12 random characters (72 bits), so two made in the
/// same millisecond do not collide. Existing tipper ids look like this.
String newPushId(int nowMs, {Random? random}) {
  final source = random ?? Random.secure();
  final time = List<String>.filled(8, '');
  var remaining = nowMs;
  for (var index = 7; index >= 0; index--) {
    time[index] = _alphabet[remaining % 64];
    remaining ~/= 64;
  }
  final buffer = StringBuffer(time.join());
  for (var index = 0; index < 12; index++) {
    buffer.write(_alphabet[source.nextInt(64)]);
  }
  return buffer.toString();
}
