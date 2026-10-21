import 'tipperrole.dart';

/// The fields of a tipper record that every signed-in user may read. They stay
/// at `/AllTippers/{tipperId}`.
const List<String> tipperPublicFieldNames = <String>[
  'name',
  'photoURL',
  'compsParticipatedIn',
];

/// The fields only the tipper and administrators may read. They live at
/// `/TipperPrivate/{tipperId}`. The purge and restore steps move whole lists.
/// Every field the app writes is in exactly one of the two lists; the legacy
/// fields in [tipperLegacyFieldNames] are in neither.
const List<String> tipperPrivateFieldNames = <String>[
  'authuid',
  'tipperRole',
  'email',
  'logon',
  'isAnonymous',
  'acctCreatedUTC',
  'acctLoggedOnUTC',
];

/// Two legacy fields that some production records still carry (`active` on 84 of
/// 214, `tipperID` on 134, on 20 October 2026). Nothing reads them. They are in
/// neither list above and the purge deletes them.
const List<String> tipperLegacyFieldNames = <String>['active', 'tipperID'];

/// The public name a tipper is given at the purge when their record has none of
/// the public fields, so that the record is not left empty (the database keeps
/// no empty node and the tipper would disappear). One production tipper signed
/// up in 2025 without entering an alias. The tail of the id keeps two such
/// tippers apart; it is never claimed as an alias.
String placeholderTipperName(String tipperId) {
  const tailLength = 6;
  final tail = tipperId.length > tailLength
      ? tipperId.substring(tipperId.length - tailLength)
      : tipperId;
  return 'Unnamed tipper $tail';
}

/// The private part of a tipper record (DESIGN-database-rules.md, D6).
///
/// [authuid] is null for a historical tipper who has not yet signed in with a
/// real account. A missing or unrecognised [tipperRole] is an ordinary tipper;
/// nothing here can grant administrator rights by accident.
class TipperPrivate {
  const TipperPrivate({
    this.authuid,
    this.tipperRole = TipperRole.tipper,
    this.email,
    this.logon,
    this.isAnonymous = false,
    this.acctCreatedUTC,
    this.acctLoggedOnUTC,
  });

  final String? authuid;
  final TipperRole tipperRole;
  final String? email;
  final String? logon;
  final bool isAnonymous;
  final DateTime? acctCreatedUTC;
  final DateTime? acctLoggedOnUTC;

  factory TipperPrivate.fromJson(Map<String, Object?> json) {
    return TipperPrivate(
      authuid: _text(json['authuid']),
      tipperRole: _role(json['tipperRole']),
      email: _text(json['email']),
      logon: _text(json['logon']),
      isAnonymous: json['isAnonymous'] == true,
      acctCreatedUTC: _time(json['acctCreatedUTC']),
      acctLoggedOnUTC: _time(json['acctLoggedOnUTC']),
    );
  }

  /// The record as stored. Absent values are left out, as the database would
  /// drop them anyway.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (authuid != null) 'authuid': authuid,
      'tipperRole': tipperRole.name,
      if (email != null) 'email': email,
      if (logon != null) 'logon': logon,
      'isAnonymous': isAnonymous,
      if (acctCreatedUTC != null)
        'acctCreatedUTC': acctCreatedUTC!.toUtc().toIso8601String(),
      if (acctLoggedOnUTC != null)
        'acctLoggedOnUTC': acctLoggedOnUTC!.toUtc().toIso8601String(),
    };
  }

  static String? _text(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

  static DateTime? _time(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  static TipperRole _role(Object? raw) {
    for (final role in TipperRole.values) {
      if (role.name == raw) {
        return role;
      }
    }
    return TipperRole.tipper;
  }
}
