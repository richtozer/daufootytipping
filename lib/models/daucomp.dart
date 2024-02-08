import 'package:daufootytipping/models/dauround.dart';

class DAUComp implements Comparable<DAUComp> {
  String? dbkey;
  final String name;
  final Uri aflFixtureJsonURL;
  final Uri nrlFixtureJsonURL;
  List<DAURound>? daurounds = [];
  final bool
      active; // TODO we should regularly download fixture updates for active comps only - 1) honor this flag in the code and 2) allow a way for it to be set to false - either automatically or by admin

  //constructor
  DAUComp({
    this.dbkey,
    required this.name,
    required this.aflFixtureJsonURL,
    required this.nrlFixtureJsonURL,
    this.active = true,
    this.daurounds,
  });

  factory DAUComp.fromJson(
      Map<String, dynamic> data, String? key, List<DAURound>? daurounds) {
    return DAUComp(
      dbkey: key,
      name: data['name'] ?? '',
      aflFixtureJsonURL: Uri.parse(data['aflFixtureJsonURL']),
      nrlFixtureJsonURL: Uri.parse(data['nrlFixtureJsonURL']),
      daurounds: daurounds,
    );
  }

  Map<String, dynamic> toJsonForCompare() {
    // Serialize DAURound list separately
    List<Map<String, dynamic>> dauroundsJson = [];
    if (daurounds != null) {
      for (var dauround in daurounds!) {
        dauroundsJson.add(dauround.toJsonForCompare());
      }
    }
    return {
      'name': name,
      'aflFixtureJsonURL': aflFixtureJsonURL.toString(),
      'nrlFixtureJsonURL': nrlFixtureJsonURL.toString(),
      'active': active,
      'daurounds': dauroundsJson,
    };
  }

  @override
  // method used to provide default sort for DAUComp(s) in a List[]
  int compareTo(DAUComp other) {
    return name.compareTo(other.name);
  }
}
