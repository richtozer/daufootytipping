/// The longest alias (display name) a tipper may have, in characters.
const int maxAliasLength = 64;

final RegExp _notLetterNumberOrSpace = RegExp(
  r'[^\p{Letter}\p{Number}\s]',
  unicode: true,
);
final RegExp _whitespace = RegExp(r'\s+');

/// Reduces an alias to the key used to compare and index it.
///
/// Strips emoji, symbols and punctuation, removes every space and lowercases,
/// so "R e i s y", "Reisy🏈" and "reisy" all give "reisy". Accents are kept:
/// "Réisy" gives "réisy". The result contains only letters and digits, so it
/// is a valid Realtime Database key (`/AliasIndex/{key}`), unless it is empty
/// (an alias made only of symbols), which [isValidAlias] rejects.
String normaliseAlias(String alias) {
  return alias
      .replaceAll(_notLetterNumberOrSpace, '')
      .replaceAll(_whitespace, '')
      .toLowerCase();
}

/// Whether [alias] can be a tipper's name: not blank, at most
/// [maxAliasLength] characters, and with at least one letter or digit left
/// once normalised (so it can be claimed in the alias index).
bool isValidAlias(String alias) {
  final trimmed = alias.trim();
  if (trimmed.isEmpty || trimmed.runes.length > maxAliasLength) {
    return false;
  }
  return normaliseAlias(trimmed).isNotEmpty;
}

/// Reduces a login email address to the form used to compare and index it.
String normaliseEmail(String email) => email.trim().toLowerCase();
