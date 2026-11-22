import 'dart:convert';

/// The longest key the Realtime Database accepts, in UTF-8 bytes.
const int maxRtdbKeyBytes = 768;

const String _forbiddenKeyCharacters = '.\$#[]/';

/// Whether [key] can be used as a single Realtime Database path segment.
///
/// Keys may not be empty, may not contain `. $ # [ ] /` or ASCII control
/// characters, and may not exceed [maxRtdbKeyBytes] bytes. Identity code
/// builds paths from values such as uids, so it checks this before using one.
bool isValidRtdbKey(String key) {
  if (key.isEmpty || utf8.encode(key).length > maxRtdbKeyBytes) {
    return false;
  }
  for (final unit in key.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) {
      return false;
    }
    if (_forbiddenKeyCharacters.codeUnits.contains(unit)) {
      return false;
    }
  }
  return true;
}
