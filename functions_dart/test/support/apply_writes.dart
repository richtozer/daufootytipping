import 'dart:convert';

/// Applies a multi-path update to a copy of a nested database, the way the
/// database applies one: each key is a path, each value replaces that place.
Map<String, Object?> applyWrites(
  Map<String, Object?> database,
  Map<String, Object?> writes,
) {
  final copy = jsonDecode(jsonEncode(database)) as Map<String, Object?>;
  for (final entry in writes.entries) {
    final segments = entry.key.split('/');
    var node = copy;
    for (final segment in segments.take(segments.length - 1)) {
      final next = node[segment];
      node = next is Map<String, Object?>
          ? next
          : (node[segment] = <String, Object?>{});
    }
    node[segments.last] = jsonDecode(jsonEncode(entry.value));
  }
  return copy;
}
