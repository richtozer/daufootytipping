import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipperrole.dart';

class Tipper implements Comparable<Tipper> {
  String? dbkey;
  String authuid; // this is the Firebase auth uid
  String?
      email; // this is the email address used for communication - same as legacy sheet email
  String? logon; // this is the email address used for login
  String? name;
  final TipperRole tipperRole;
  String? photoURL;
  List<DAUComp> compsPaidFor = [];
  final DateTime? acctCreatedUTC;
  final DateTime? acctLoggedOnUTC;

  //constructor
  Tipper({
    this.dbkey,
    required this.compsPaidFor,
    this.photoURL,
    required this.authuid,
    required this.email,
    this.logon,
    this.name,
    required this.tipperRole,
    this.acctCreatedUTC,
    this.acctLoggedOnUTC,
  });

  factory Tipper.fromJson(Map<String, dynamic> data, String? key) {
    return Tipper(
      dbkey: key,
      authuid: data['authuid'],
      email: data['email'],
      logon: data['logon'], // this is the email address used for login
      name: data['name'],
      tipperRole: TipperRole.values.byName(data['tipperRole']),
      photoURL: data['photoURL'],
      compsPaidFor: data['compsParticipatedIn'] != null
          ? DAUComp.fromJsonList(data['compsParticipatedIn'])
          : [],
      acctCreatedUTC: data['acctCreatedUTC'] != null
          ? DateTime.parse(data['acctCreatedUTC'])
          : null,
      acctLoggedOnUTC: data['acctLoggedOnUTC'] != null
          ? DateTime.parse(data['acctLoggedOnUTC'])
          : null,
    );
  }

  bool paidForComp(DAUComp? checkThisComp) {
    if (checkThisComp == null) {
      return false;
    }
    return compsPaidFor.any((compParticipatedIn) =>
        compParticipatedIn.dbkey ==
        checkThisComp.dbkey); //check if the tipper has paid for this comp
  }

  static List<Tipper?> fromJsonList(dynamic json) {
    final allTippers = Map<String, dynamic>.from(json as dynamic);

    List<Tipper?> tippersList = allTippers.entries.map((entry) {
      String key = entry.key; // Retrieve the Firebase key
      dynamic tipperasJSON = entry.value;

      return Tipper.fromJson(Map<String, dynamic>.from(tipperasJSON), key);
    }).toList();

    return tippersList;
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
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Tipper &&
        other.dbkey == dbkey &&
        other.authuid == authuid &&
        other.email == email &&
        other.logon == logon &&
        other.name == name &&
        other.tipperRole == tipperRole &&
        other.photoURL == photoURL &&
        other.compsPaidFor == compsPaidFor &&
        other.acctCreatedUTC == acctCreatedUTC &&
        other.acctLoggedOnUTC == acctLoggedOnUTC;
  }

  @override
  int get hashCode {
    return dbkey.hashCode ^
        authuid.hashCode ^
        email.hashCode ^
        logon.hashCode ^
        name.hashCode ^
        tipperRole.hashCode ^
        photoURL.hashCode ^
        compsPaidFor.hashCode ^
        acctCreatedUTC.hashCode ^
        acctLoggedOnUTC.hashCode;
  }

  @override
  // method used to sort Tippers in a List
  int compareTo(Tipper other) {
    return name.toString().toLowerCase().compareTo(
        other.name.toString().toLowerCase()); //sort by the tipper name
  }
}
