import 'package:daufootytipping/models/tipperrole.dart';

class Tipper implements Comparable<Tipper> {
  String? dbkey;
  String authuid;
  final String email;
  final String name;
  final String
      tipperID; // to support the lecacy tipping service, this is the priamry key for the tipper
  final bool active;
  final TipperRole tipperRole;

  //constructor
  Tipper(
      {this.dbkey,
      required this.authuid,
      required this.email,
      required this.name,
      required this.tipperID,
      required this.active,
      required this.tipperRole});

  factory Tipper.fromJson(Map<String, dynamic> data, String? key) {
    return Tipper(
        dbkey: key,
        authuid: data['authuid'] ?? '',
        email: data['email'] ?? '',
        name: data['name'] ?? '',
        tipperID: data['tipperID'] ?? '',
        active: data['active'] ?? false,
        tipperRole: TipperRole.values.byName(data['tipperRole']));
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

  toJson() {
    return {
      "authuid": authuid,
      "email": email,
      "name": name,
      "tipperID": tipperID,
      "active": active,
      "tipperRole": tipperRole.name
    };
  }

  @override
  // method used to sort Tippers in a List
  int compareTo(Tipper other) {
    return name.toString().toLowerCase().compareTo(
        other.name.toString().toLowerCase()); //sort by the tipper name
  }
}
