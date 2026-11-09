import 'daucomp.dart';
import 'tipperrole.dart';

class Tipper implements Comparable<Tipper> {
  String? dbkey;
  String authuid; // this is the Firebase auth uid
  String?
  email; // this is the email address used for communication - same as legacy sheet email
  String? logon; // this is the email address used for login
  String name;
  final TipperRole tipperRole;
  String? photoURL;
  List<DAUComp> compsPaidFor = [];
  final DateTime? acctCreatedUTC;
  final DateTime? acctLoggedOnUTC;
  final bool isAnonymous;

  //constructor
  Tipper({
    this.dbkey,
    required this.compsPaidFor,
    this.photoURL,
    required this.authuid,
    required this.email,
    this.logon,
    required this.name,
    required this.tipperRole,
    this.acctCreatedUTC,
    this.acctLoggedOnUTC,
    this.isAnonymous = false,
  });

  /// Reads a tipper record. Every field but [name] may be missing: after the
  /// purge the public record carries only `name`, `photoURL` and
  /// `compsParticipatedIn`, and the account id, role, email, login and the
  /// anonymous flag live in the private record. A missing `authuid` reads as `''`
  /// ("not known here", the legacy way of saying there is no account on record),
  /// a missing role as a tipper, a missing anonymous flag as false.
  factory Tipper.fromJson(Map<String, dynamic> data, String? key) {
    return Tipper(
      dbkey: key,
      authuid: (data['authuid'] as String?) ?? '',
      email: data['email'],
      logon: data['logon'], // this is the email address used for login
      name: data['name'] ?? '',
      tipperRole: data['tipperRole'] != null
          ? TipperRole.values.byName(data['tipperRole'])
          : TipperRole.tipper,
      photoURL: data['photoURL'],
      compsPaidFor: [],
      acctCreatedUTC: data['acctCreatedUTC'] != null
          ? DateTime.parse(data['acctCreatedUTC'])
          : null,
      acctLoggedOnUTC: data['acctLoggedOnUTC'] != null
          ? DateTime.parse(data['acctLoggedOnUTC'])
          : null,
      isAnonymous: data['isAnonymous'] ?? false,
    );
  }

  /// Populates [compsPaidFor] from raw JSON data using the provided resolver callback.
  Future<void> loadCompsPaidFor(
    dynamic compsParticipatedIn,
    Future<List<DAUComp>> Function(List) resolveComps,
  ) async {
    if (compsParticipatedIn != null) {
      compsPaidFor = await resolveComps(compsParticipatedIn as List);
    }
  }

  bool paidForComp(DAUComp? checkThisComp) {
    if (isAnonymous) {
      return true; // anonymous tippers are assumed to have paid for all comps
    }
    if (checkThisComp == null) {
      return false;
    }
    return compsPaidFor.any(
      (compParticipatedIn) => compParticipatedIn.dbkey == checkThisComp.dbkey,
    ); //check if the tipper has paid for this comp
  }

  /// The signed-in user's own tipper: the public record with the private one laid
  /// over it, because the private record is the validated source for the fields
  /// that identify the account (role, login, email). [authuid] is the signed-in
  /// account's own id, which the caller has just verified against the link.
  factory Tipper.fromRecords({
    required String key,
    required String authuid,
    required Map<String, dynamic> publicRecord,
    Map<String, dynamic>? privateRecord,
  }) {
    return Tipper.fromJson(<String, dynamic>{
      ...publicRecord,
      ...?privateRecord,
      'authuid': authuid,
    }, key);
  }

  /// This tipper's public fields (record key, name, photo, paid competitions) with
  /// the identity fields of [own]: account id, role, email, login, the anonymous
  /// flag and the account times. For refreshing the signed-in tipper from the
  /// public list, whose copy no longer carries those fields.
  Tipper withIdentityOf(Tipper own) {
    return Tipper(
      dbkey: dbkey,
      compsPaidFor: compsPaidFor,
      photoURL: photoURL,
      name: name,
      authuid: own.authuid,
      email: own.email,
      logon: own.logon,
      tipperRole: own.tipperRole,
      acctCreatedUTC: own.acctCreatedUTC,
      acctLoggedOnUTC: own.acctLoggedOnUTC,
      isAnonymous: own.isAnonymous,
    );
  }

  static Future<List<Tipper?>> fromJsonList(
    dynamic json,
    Future<List<DAUComp>> Function(List) resolveComps,
  ) async {
    final allTippers = Map<String, dynamic>.from(json as dynamic);

    List<Tipper?> tippersList = [];
    for (final entry in allTippers.entries) {
      final String key = entry.key;
      final dynamic tipperAsJSON = entry.value;
      final Map<String, dynamic> data = Map<String, dynamic>.from(tipperAsJSON);
      final Tipper tipper = Tipper.fromJson(data, key);
      await tipper.loadCompsPaidFor(data['compsParticipatedIn'], resolveComps);
      tippersList.add(tipper);
    }

    return tippersList;
  }

  /// Serializes for local cache. Includes [dbkey] and omits
  /// [compsPaidFor] (which requires DAUCompsViewModel to deserialize).
  Map<String, dynamic> toCacheJson() {
    return {
      'dbkey': dbkey,
      'authuid': authuid,
      'email': email,
      'logon': logon,
      'name': name,
      'tipperRole': tipperRole.name,
      'photoURL': photoURL,
      'acctCreatedUTC': acctCreatedUTC?.toIso8601String(),
      'acctLoggedOnUTC': acctLoggedOnUTC?.toIso8601String(),
      'isAnonymous': isAnonymous,
    };
  }

  /// Restores a [Tipper] from local cache. [compsPaidFor] starts
  /// empty and is populated once the Firebase stream arrives.
  factory Tipper.fromCacheJson(Map<String, dynamic> data) {
    return Tipper(
      dbkey: data['dbkey'] as String?,
      authuid: data['authuid'] as String,
      email: data['email'] as String?,
      logon: data['logon'] as String?,
      name: (data['name'] as String?) ?? '',
      tipperRole: data['tipperRole'] != null
          ? TipperRole.values.byName(data['tipperRole'] as String)
          : TipperRole.tipper,
      photoURL: data['photoURL'] as String?,
      compsPaidFor: [],
      acctCreatedUTC: data['acctCreatedUTC'] != null
          ? DateTime.parse(data['acctCreatedUTC'] as String)
          : null,
      acctLoggedOnUTC: data['acctLoggedOnUTC'] != null
          ? DateTime.parse(data['acctLoggedOnUTC'] as String)
          : null,
      isAnonymous: (data['isAnonymous'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "authuid": authuid,
      "email": email,
      "logon": logon, // this is the email address used for login
      "name": name,
      "tipperRole": tipperRole.name,
      "photoURL": photoURL,
      "compsParticipatedIn": compsPaidFor.map((comp) => comp.dbkey).toList(),
      "acctCreatedUTC": acctCreatedUTC?.toString(),
      "acctLoggedOnUTC": acctLoggedOnUTC?.toString(),
      "isAnonymous": isAnonymous,
    };
  }

  /// Two tippers are the same tipper when they have the same record key. The
  /// account id is not compared when both have a key, because only the signed-in
  /// tipper's own object knows it (everyone else's is private). A tipper with no
  /// key yet (a guest, which is never saved) is identified by its account id.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Tipper) return false;
    if (dbkey != null && other.dbkey != null) return dbkey == other.dbkey;
    return dbkey == other.dbkey && authuid == other.authuid;
  }

  @override
  int get hashCode => dbkey != null ? dbkey.hashCode : Object.hash('', authuid);

  @override
  // method used to sort Tippers in a List
  int compareTo(Tipper other) {
    return name.toString().toLowerCase().compareTo(
      other.name.toString().toLowerCase(),
    ); //sort by the tipper name
  }
}
