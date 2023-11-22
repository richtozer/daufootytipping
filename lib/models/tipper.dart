import 'package:daufootytipping/models/tipperrole.dart';

class Tipper implements Comparable<Tipper> {
  String? dbkey;
  final String authuid;
  final String email;
  final String name;
  final bool active;
  final TipperRole tipperRole;

  //constructor
  Tipper(
      {this.dbkey,
      required this.authuid,
      required this.email,
      required this.name,
      required this.active,
      required this.tipperRole});

  factory Tipper.fromJson(Map<String, dynamic> data, String? key) {
    return Tipper(
        dbkey: key,
        authuid: data['authuid'] ?? '',
        email: data['email'] ?? '',
        name: data['name'] ?? '',
        active: data['active'] ?? false,
        tipperRole: TipperRole.values.byName(data['tipperRole']));
  }

  toJson() {
    return {
      "authuid": authuid,
      "email": email,
      "name": name,
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
