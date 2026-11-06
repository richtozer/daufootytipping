import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/caller_token.dart';
import 'package:dart_functions/identity/faults.dart';
import 'package:dart_functions/identity/keys.dart';
import 'package:dart_functions/identity/operation_id.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:firebase_functions/firebase_functions.dart'
    show HttpResponseException;
import 'package:test/test.dart';

/// Builds the database a test starts from.
class IdentitySeed {
  final Map<String, Object?> data = <String, Object?>{
    'AppConfig': {'createLinkedTipper': true},
  };

  Map<String, Object?> _root(String key) =>
      (data[key] ??= <String, Object?>{}) as Map<String, Object?>;

  /// A tipper. By default fully audited: public and private records, and the
  /// alias and login claims. [indexAccount] also links [authuid] in `/AuthIndex`.
  void tipper(
    String id, {
    String? name,
    String? authuid,
    String? logon,
    String? email,
    bool hasPublic = true,
    bool hasPrivate = true,
    bool claimAlias = true,
    bool claimLogon = true,
    bool indexAccount = false,
    String? placeholder,
    bool legacyPublic = true,
  }) {
    if (hasPublic) {
      _root('AllTippers')[id] = <String, Object?>{
        'name': ?name,
        if (legacyPublic) ...<String, Object?>{
          'authuid': ?authuid,
          'logon': ?logon,
          'email': ?email,
          'tipperRole': 'tipper',
          'isAnonymous': false,
        },
      };
    }
    if (hasPrivate) {
      _root('TipperPrivate')[id] = <String, Object?>{
        'authuid': ?authuid,
        'logon': ?logon,
        'email': ?email,
        'tipperRole': 'tipper',
        'isAnonymous': false,
        'acctCreatedUTC': '2025-02-01 03:04:05.000Z',
      };
    }
    if (claimAlias && name != null) {
      _root('AliasIndex')[aliasIndexKey(name)] = id;
    }
    if (claimLogon && logon != null && hasPrivate) {
      _root('LogonIndex')[logonIndexKey(logon)] = id;
    }
    if (indexAccount && authuid != null) {
      _root('AuthIndex')[authuid] = id;
    }
    if (placeholder != null) {
      _root('Placeholders')[id] = placeholder;
    }
  }
}

CallerToken callerToken(
  String uid,
  String? email, {
  bool verified = true,
  String provider = 'password',
  String? picture,
}) => CallerToken(
  uid: uid,
  email: email,
  emailVerified: verified,
  signInProvider: provider,
  pictureUrl: picture,
);

Admission admissionFor({IdentityMode mode = IdentityMode.coexist}) => Admission(
  operationId: newOperationId(),
  config: ServerModeConfig(mode: mode),
);

/// A checkpoint that makes the operation "crash" right after [step].
Checkpoint crashAfter(String step) =>
    (reached) async => reached == step ? throw SimulatedCrash(step) : null;

String? reasonOf(Object error) {
  if (error is! HttpResponseException) {
    return null;
  }
  final details = error.details;
  return details == null || details.isEmpty
      ? null
      : details.first['reason'] as String?;
}

/// Matches a refusal with this reason.
Matcher refusedAs(String reason) => throwsA(
  predicate<Object>(
    (error) => reasonOf(error) == reason,
    'refused with reason $reason',
  ),
);

Map<String, Object?> rowAt(Map<String, Object?> root, String node, String id) {
  final value = (root[node] as Map?)?[id];
  return value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
}
