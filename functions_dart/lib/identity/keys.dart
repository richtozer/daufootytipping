import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dau_shared/dau_shared.dart';

/// The `/LogonIndex` key for a login email address:
/// `base64url(SHA-256(normaliseEmail(email)))`, without padding.
///
/// Email addresses cannot be database keys (they contain `.`), and hashing
/// also keeps addresses out of keys and logs. A 32-byte digest encodes to 43
/// characters from `A-Z a-z 0-9 - _`, always a valid key.
String logonIndexKey(String email) {
  final normalised = normaliseEmail(email);
  if (normalised.isEmpty) {
    throw ArgumentError.value(email, 'email', 'must not be blank');
  }
  final digest = sha256.convert(utf8.encode(normalised));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

/// The `/AliasIndex` key for an alias. Throws if the alias is not allowed, so
/// callers cannot claim an empty or over-long key.
String aliasIndexKey(String alias) {
  if (!isValidAlias(alias)) {
    throw ArgumentError.value(alias, 'alias', 'is not a valid alias');
  }
  return normaliseAlias(alias.trim());
}
