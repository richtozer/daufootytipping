// The requests and results of the identity callables, shared by the functions
// that implement them and by the R2 client that calls them, so both sides
// read one definition (DESIGN-database-rules-phase4.md, section 6f).
//
// `fromJson` is strict about shape and throws a [FormatException] naming the
// problem; the functions turn that into an invalid-argument error. Unknown
// extra keys are ignored, so a newer client can add fields.

import 'tipperrole.dart';

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

/// `unlink-my-account`. It takes nothing: the account is the caller's, from the
/// verified token, never from the request. Anything sent is ignored.
class UnlinkMyAccountRequest {
  const UnlinkMyAccountRequest();

  factory UnlinkMyAccountRequest.fromJson(Object? raw) =>
      const UnlinkMyAccountRequest();

  Map<String, Object?> toJson() => const <String, Object?>{};
}

class UnlinkMyAccountResult {
  const UnlinkMyAccountResult({required this.unlinked});

  /// Whether a tipper record was detached. False is not an error: the account
  /// may never have been linked, or an earlier call already did it.
  final bool unlinked;

  factory UnlinkMyAccountResult.fromJson(Object? raw) {
    final unlinked = _asMap(raw, 'the result')['unlinked'];
    if (unlinked is! bool) {
      throw const FormatException('unlinked must be true or false');
    }
    return UnlinkMyAccountResult(unlinked: unlinked);
  }

  Map<String, Object?> toJson() => <String, Object?>{'unlinked': unlinked};
}

/// `admin-update-tipper`: an administrator changes another tipper's name,
/// contact email or role. At least one of the three must be given; one that is
/// not given is left alone. The paid-competition list is not here: an
/// administrator still sets that directly.
class AdminUpdateTipperRequest {
  const AdminUpdateTipperRequest({
    required this.tipperId,
    this.name,
    this.email,
    this.role,
  });

  final String tipperId;
  final String? name;
  final String? email;
  final TipperRole? role;

  factory AdminUpdateTipperRequest.fromJson(Object? raw) {
    final map = _asMap(raw, 'the request');
    final name = _optionalText(map, 'name');
    final email = _optionalText(map, 'email');
    final roleText = _optionalText(map, 'role');
    final TipperRole? role;
    if (roleText == null) {
      role = null;
    } else {
      final match = TipperRole.values.where((r) => r.name == roleText);
      if (match.isEmpty) {
        throw const FormatException('role must be admin or tipper');
      }
      role = match.first;
    }
    if (name == null && email == null && role == null) {
      throw const FormatException('give a name, an email or a role to change');
    }
    return AdminUpdateTipperRequest(
      tipperId: _requiredText(map, 'tipperId'),
      name: name,
      email: email,
      role: role,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'tipperId': tipperId,
    if (name != null) 'name': name,
    if (email != null) 'email': email,
    if (role != null) 'role': role!.name,
  };
}

class AdminUpdateTipperResult {
  const AdminUpdateTipperResult({
    required this.tipperId,
    required this.changed,
  });

  final String tipperId;

  /// The fields that were actually changed (`name`, `email`, `role`); a field
  /// already holding the requested value is not listed.
  final List<String> changed;

  factory AdminUpdateTipperResult.fromJson(Object? raw) {
    final map = _asMap(raw, 'the result');
    final changed = map['changed'];
    if (changed is! List || changed.any((field) => field is! String)) {
      throw const FormatException('changed must be a list of field names');
    }
    return AdminUpdateTipperResult(
      tipperId: _requiredText(map, 'tipperId'),
      changed: List<String>.from(changed),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'tipperId': tipperId,
    'changed': changed,
  };
}

/// `admin-merge-tippers`: merges the `original` tipper record into the `target`
/// and removes the original, as the admin screen's merge has always done.
///
/// - [mergeTips]: the original's tips, in every competition, move to the target.
///   Where both tipped the same game the original's tip replaces the target's,
///   as before. Without it the original's tips are left where they are.
/// - [mergeLogon]: the original's login address becomes the target's.
/// - the original's sign-in account, if it has one, is always moved to the
///   target (the target's own account, if any, stops working for it).
/// - [dryRun]: report what would happen and change nothing.
///
/// The paid-competition list is not merged; the target keeps its own.
class AdminMergeTippersRequest {
  const AdminMergeTippersRequest({
    required this.originalId,
    required this.targetId,
    this.mergeTips = false,
    this.mergeLogon = false,
    this.dryRun = false,
  });

  final String originalId;
  final String targetId;
  final bool mergeTips;
  final bool mergeLogon;
  final bool dryRun;

  factory AdminMergeTippersRequest.fromJson(Object? raw) {
    final map = _asMap(raw, 'the request');
    return AdminMergeTippersRequest(
      originalId: _requiredText(map, 'originalId'),
      targetId: _requiredText(map, 'targetId'),
      mergeTips: _optionalBool(map, 'mergeTips'),
      mergeLogon: _optionalBool(map, 'mergeLogon'),
      dryRun: _optionalBool(map, 'dryRun'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'originalId': originalId,
    'targetId': targetId,
    'mergeTips': mergeTips,
    'mergeLogon': mergeLogon,
    'dryRun': dryRun,
  };
}

class AdminMergeTippersResult {
  const AdminMergeTippersResult({
    required this.targetId,
    required this.tipsMoved,
    required this.tipsReplaced,
    required this.loginMoved,
    required this.accountMoved,
    required this.dryRun,
  });

  final String targetId;

  /// How many tips were (or, in a dry run, would be) moved to the target.
  final int tipsMoved;

  /// Of those, how many replaced a tip the target already had for that game.
  final int tipsReplaced;

  /// Whether the original's login address became the target's.
  final bool loginMoved;

  /// Whether the original's sign-in account was moved to the target.
  final bool accountMoved;

  final bool dryRun;

  factory AdminMergeTippersResult.fromJson(Object? raw) {
    final map = _asMap(raw, 'the result');
    int count(String key) {
      final value = map[key];
      if (value is! int) {
        throw FormatException('$key must be a whole number');
      }
      return value;
    }

    return AdminMergeTippersResult(
      targetId: _requiredText(map, 'targetId'),
      tipsMoved: count('tipsMoved'),
      tipsReplaced: count('tipsReplaced'),
      loginMoved: _requiredBool(map, 'loginMoved'),
      accountMoved: _requiredBool(map, 'accountMoved'),
      dryRun: _requiredBool(map, 'dryRun'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'targetId': targetId,
    'tipsMoved': tipsMoved,
    'tipsReplaced': tipsReplaced,
    'loginMoved': loginMoved,
    'accountMoved': accountMoved,
    'dryRun': dryRun,
  };
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

bool _optionalBool(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return false;
  }
  if (value is! bool) {
    throw FormatException('$key must be true or false');
  }
  return value;
}

bool _requiredBool(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw FormatException('$key must be true or false');
  }
  return value;
}
