import 'package:daufootytipping/models/game.dart';

class DAUComp implements Comparable<DAUComp> {
  String? dbkey;
  final String name;
  final Uri aflFixtureJsonURL;
  final Uri nrlFixtureJsonURL;
  final bool
      active; // TODO we should regularly download fixture updates for active comps only - 1) honor this flag in the code and 2) allow a way for it to be set to false - either automatically or by admin

  //constructor
  DAUComp({
    this.dbkey,
    required this.name,
    required this.aflFixtureJsonURL,
    required this.nrlFixtureJsonURL,
    this.active = true,
  });

  factory DAUComp.fromJson(Map<String, dynamic> data, String? key) {
    return DAUComp(
      dbkey: key,
      name: data['name'] ?? '',
      aflFixtureJsonURL: Uri.parse(data['aflFixtureJsonURL']),
      nrlFixtureJsonURL: Uri.parse(data['nrlFixtureJsonURL']),
      active: data['active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    // Serialize DAURound list separately

    return {
      'name': name,
      'aflFixtureJsonURL': aflFixtureJsonURL.toString(),
      'nrlFixtureJsonURL': nrlFixtureJsonURL.toString(),
      'active': active,
    };
  }

  @override
  // method used to provide default sort for DAUComp(s) in a List[]
  int compareTo(DAUComp other) {
    return name.compareTo(other.name);
  }
}
