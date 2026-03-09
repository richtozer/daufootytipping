import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipperrole.dart';

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

  factory Tipper.fromJson(Map<String, dynamic> data, String? key) {
    return Tipper(
      dbkey: key,
      authuid: data['authuid'],
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

  /// Populates [compsPaidFor] from raw JSON data. Must be called after
  /// construction since [DAUComp.fromJsonList] is async.
  Future<void> loadCompsPaidFor(dynamic compsParticipatedIn) async {
    if (compsParticipatedIn != null) {
      compsPaidFor = await DAUComp.fromJsonList(
        compsParticipatedIn as List,
      );
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

  static Future<List<Tipper?>> fromJsonList(dynamic json) async {
    final allTippers = Map<String, dynamic>.from(json as dynamic);

    List<Tipper?> tippersList = [];
    for (final entry in allTippers.entries) {
      final String key = entry.key;
      final dynamic tipperAsJSON = entry.value;
      final Map<String, dynamic> data = Map<String, dynamic>.from(tipperAsJSON);
      final Tipper tipper = Tipper.fromJson(data, key);
      await tipper.loadCompsPaidFor(data['compsParticipatedIn']);
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Tipper && other.dbkey == dbkey && other.authuid == authuid;
  }

  @override
  int get hashCode => Object.hash(
    dbkey ?? '', // Use an empty string if dbkey is null
    authuid,
  );

  @override
  // method used to sort Tippers in a List
  int compareTo(Tipper other) {
    return name.toString().toLowerCase().compareTo(
      other.name.toString().toLowerCase(),
    ); //sort by the tipper name
  }
}
