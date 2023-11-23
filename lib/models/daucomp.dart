import 'package:daufootytipping/models/dauround.dart';

class DAUComp implements Comparable<DAUComp> {
  String? dbkey;
  final String name;
  final Uri aflFixtureJsonURL;
  final Uri nrlFixtureJsonURL;
  List<DAURound>? dauRounds = [];

  //constructor
  DAUComp({
    this.dbkey,
    required this.name,
    required this.aflFixtureJsonURL,
    required this.nrlFixtureJsonURL,
    this.dauRounds,
  });

  factory DAUComp.fromJson(Map<String, dynamic> data, String? key) {
    // Deserialize DAURound list separately
    List<dynamic>? dauRoundsData = data['dauRounds'];
    List<DAURound>? dauRounds = dauRoundsData != null
        ? List<DAURound>.from(dauRoundsData
            .map((roundData) => DAURound.fromJson(roundData, null)))
        : null;

    return DAUComp(
      dbkey: key,
      name: data['name'] ?? '',
      aflFixtureJsonURL: Uri.parse(data['aflFixtureJsonURL']),
      //Uri.parse(Uri.decodeComponent(data['aflFixtureJsonURL'])),
      nrlFixtureJsonURL: Uri.parse(data['nrlFixtureJsonURL']),
      //Uri.parse(Uri.decodeComponent(data['nrlFixtureJsonURL'])),
      dauRounds: dauRounds,
    );
  }

  Map<String, dynamic> toJson() {
    // Serialize DAURound list separately
    List<Map<String, dynamic>>? dauRoundsData = dauRounds
        ?.map((round) => round.toJson() as Map<String, dynamic>)
        .toList();

    return {
      'name': name,
      //'aflFixtureJsonURL': Uri.encodeComponent(aflFixtureJsonURL.toString()),
      //'nrlFixtureJsonURL': Uri.encodeComponent(nrlFixtureJsonURL.toString()),
      'aflFixtureJsonURL': aflFixtureJsonURL.toString(),
      'nrlFixtureJsonURL': nrlFixtureJsonURL.toString(),
      if (dauRoundsData != null) 'dauRounds': dauRoundsData,
    };
  }

  @override
  // method used to provide default sort for DAUComp(s) in a List[]
  int compareTo(DAUComp other) {
    return name.compareTo(other.name);
  }
}
