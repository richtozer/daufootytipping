import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipperrole.dart';

class Tipper implements Comparable<Tipper> {
  String? dbkey;
  String authuid;
  String?
      email; // this is the email address used for communication - same as legacy sheet email
  String? logon; // this is the email address used for login
  final String name;
  final String
      tipperID; // to support the lecacy tipping service, this is the priamry key for the tipper
  //final bool active;  //no longer used
  final TipperRole tipperRole;
  String? photoURL;
  List<DAUComp> compsParticipatedIn = [];

  //constructor
  Tipper(
      {this.dbkey,
      required this.compsParticipatedIn,
      this.photoURL,
      required this.authuid,
      required this.email,
      this.logon,
      required this.name,
      required this.tipperID,
      required this.tipperRole});

  factory Tipper.fromJson(Map<String, dynamic> data, String? key) {
/*     // Handle deviceTokens list
    dynamic deviceTokensData = data['deviceTokens'];
    List<DeviceToken?> deviceTokensList = [];

    if (deviceTokensData != null) {
      deviceTokensList =
          data['deviceTokens'].map<DeviceToken?>((deviceTokensasJSON) {
        return DeviceToken.fromJson(
            Map<String, dynamic>.from(deviceTokensasJSON));
      }).toList();
    } */

    return Tipper(
      dbkey: key,
      //deviceTokens: deviceTokensList,
      authuid: data['authuid'],
      email: data['email'],
      logon: data['logon'], // this is the email address used for login
      name: data['name'] ?? '',
      tipperID: data['tipperID'] ?? '',
      //active: data['active'] ?? false,
      tipperRole: TipperRole.values.byName(data['tipperRole']),
      photoURL: data['photoURL'] ?? '',
      compsParticipatedIn: data['compsParticipatedIn'] != null
          ? DAUComp.fromJsonList(data['compsParticipatedIn'])
          : [],
    );
  }

  bool activeInComp(String checkThisCompDbKey) {
    return compsParticipatedIn.any((compParticipatedIn) =>
        compParticipatedIn.dbkey ==
        checkThisCompDbKey); //check if the tipper is active in the comp
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
/*     List deviceTokenList =
        deviceTokens?.map((deviceToken) => deviceToken!.toJson()).toList() ??
            []; */
    return {
      "authuid": authuid,
      "email": email,
      "logon": logon, // this is the email address used for login
      "name": name,
      "tipperID": tipperID,
      //"active": active,
      "tipperRole": tipperRole.name,
      //"deviceTokens": deviceTokenList,
      "photoURL": photoURL,
      "compsParticipatedIn":
          compsParticipatedIn.map((comp) => comp.dbkey).toList(),
    };
  }

  @override
  // method used to sort Tippers in a List
  int compareTo(Tipper other) {
    return name.toString().toLowerCase().compareTo(
        other.name.toString().toLowerCase()); //sort by the tipper name
  }
}
