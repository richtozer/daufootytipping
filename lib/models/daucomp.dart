import 'package:daufootytipping/models/dauround.dart';

class DAUComp {
  String? dbkey;
  final String name;
  final Uri aflFixtureJsonURL;
  final Uri nrlFixtureJsonURL;
  List<DAURound> dauRounds = [];

  //constructor
  DAUComp(
      this.dbkey, this.name, this.aflFixtureJsonURL, this.nrlFixtureJsonURL);
}
