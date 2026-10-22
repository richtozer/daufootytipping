// The requests and results of the identity callables, shared by the functions
// that implement them and by the R2 client that calls them, so both sides
// read one definition (DESIGN-database-rules-phase4.md, section 6f).
//
// `fromJson` is strict about shape and throws a [FormatException] naming the
// problem; the functions turn that into an invalid-argument error. Unknown
// extra keys are ignored, so a newer client can add fields.

/// The longest push token accepted. Real tokens are about 160 characters; the
/// limit keeps a token usable as a database key (768 bytes at most).
const int maxDeviceTokenLength = 512;

/// How a call to `link-or-create-tipper` ended.
enum LinkOutcome {
  /// The account was already linked; the call only refreshed its details.
  existing,

  /// The account was linked to a tipper record that already existed.
  linked,

  /// A new tipper record was created for the account.
  created;

  /// The value sent over the wire.
  String get wire => name;

  static LinkOutcome parse(Object? raw) {
    for (final outcome in LinkOutcome.values) {
      if (outcome.wire == raw) {
        return outcome;
      }
    }
    throw FormatException('Unknown link outcome: $raw');
  }
}

/// `link-or-create-tipper`. [alias] is only needed when a new record has to be
/// created; a call that links or refreshes ignores it.
class LinkOrCreateTipperRequest {
  const LinkOrCreateTipperRequest({this.alias});

  final String? alias;

  factory LinkOrCreateTipperRequest.fromJson(Object? raw) {
    if (raw == null) {
      return const LinkOrCreateTipperRequest();
    }
    final map = _asMap(raw, 'the request');
    return LinkOrCreateTipperRequest(alias: _optionalText(map, 'alias'));
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (alias != null) 'alias': alias,
  };
}

class LinkOrCreateTipperResult {
  const LinkOrCreateTipperResult({
    required this.tipperId,
    required this.outcome,
  });

  final String tipperId;
  final LinkOutcome outcome;

  factory LinkOrCreateTipperResult.fromJson(Object? raw) {
    final map = _asMap(raw, 'the result');
    return LinkOrCreateTipperResult(
      tipperId: _requiredText(map, 'tipperId'),
      outcome: LinkOutcome.parse(map['outcome']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'tipperId': tipperId,
    'outcome': outcome.wire,
  };
}

/// `update-tipper-alias`.
class UpdateTipperAliasRequest {
  const UpdateTipperAliasRequest({required this.alias});

  final String alias;

  factory UpdateTipperAliasRequest.fromJson(Object? raw) {
    final map = _asMap(raw, 'the request');
    return UpdateTipperAliasRequest(alias: _requiredText(map, 'alias'));
  }

  Map<String, Object?> toJson() => <String, Object?>{'alias': alias};
}

class UpdateTipperAliasResult {
  const UpdateTipperAliasResult({required this.tipperId, required this.alias});

  final String tipperId;

  /// The alias as stored.
  final String alias;

  factory UpdateTipperAliasResult.fromJson(Object? raw) {
    final map = _asMap(raw, 'the result');
    return UpdateTipperAliasResult(
      tipperId: _requiredText(map, 'tipperId'),
      alias: _requiredText(map, 'alias'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'tipperId': tipperId,
    'alias': alias,
  };
}

/// `register-device-token` and `unregister-device-token`.
class DeviceTokenRequest {
  const DeviceTokenRequest({required this.token});

  final String token;

  factory DeviceTokenRequest.fromJson(Object? raw) {
    final map = _asMap(raw, 'the request');
    final token = _requiredText(map, 'token');
    if (token.length > maxDeviceTokenLength) {
      throw const FormatException(
        'token is longer than $maxDeviceTokenLength characters',
      );
    }
    return DeviceTokenRequest(token: token);
  }

  Map<String, Object?> toJson() => <String, Object?>{'token': token};
}

class RegisterDeviceTokenResult {
  const RegisterDeviceTokenResult({required this.tipperId});

  final String tipperId;

  factory RegisterDeviceTokenResult.fromJson(Object? raw) =>
      RegisterDeviceTokenResult(
        tipperId: _requiredText(_asMap(raw, 'the result'), 'tipperId'),
      );

  Map<String, Object?> toJson() => <String, Object?>{'tipperId': tipperId};
}

class UnregisterDeviceTokenResult {
  const UnregisterDeviceTokenResult({required this.removed});

  /// Whether this tipper held the token and it was removed. False is not an
  /// error: the token may already have gone, or belong to someone else now.
  final bool removed;

  factory UnregisterDeviceTokenResult.fromJson(Object? raw) {
    final removed = _asMap(raw, 'the result')['removed'];
    if (removed is! bool) {
      throw const FormatException('removed must be true or false');
    }
    return UnregisterDeviceTokenResult(removed: removed);
  }

  Map<String, Object?> toJson() => <String, Object?>{'removed': removed};
}

Map<Object?, Object?> _asMap(Object? raw, String what) {
  if (raw is! Map) {
    throw FormatException('$what must be an object');
  }
  return raw;
}

String _requiredText(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key is required and must be text');
  }
  return value;
}

String? _optionalText(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('$key must be text');
  }
  return value;
}
