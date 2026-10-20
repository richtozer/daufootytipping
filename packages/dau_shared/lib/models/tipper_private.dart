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
/// Every field the app writes is in exactly one of the two lists. Production
/// data also has two legacy fields, `active` and `tipperID`, on some records;
/// nothing reads them and they are in neither list.
const List<String> tipperPrivateFieldNames = <String>[
  'authuid',
  'tipperRole',
  'email',
  'logon',
  'isAnonymous',
  'acctCreatedUTC',
  'acctLoggedOnUTC',
];

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
