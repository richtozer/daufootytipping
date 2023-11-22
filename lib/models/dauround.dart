class DAURound implements Comparable<DAURound> {
  String? dbkey;
  final String dAUroundName;
  final int? aflRoundNumber;
  final int? nrlRoundNumber;
  final DateTime roundKickoffTimeUTC;

  // counstructor
  DAURound(
      {this.dbkey,
      required this.dAUroundName,
      required this.roundKickoffTimeUTC,
      this.aflRoundNumber,
      this.nrlRoundNumber});

  factory DAURound.fromJson(Map<String, dynamic> data, String? key) {
    return DAURound(
      dbkey: key,
      dAUroundName: data['dAUroundName'] ?? '',
      aflRoundNumber: data['aflRoundNumber'] ?? 0,
      nrlRoundNumber: data['nrlRoundNumber'] ?? 0,
      roundKickoffTimeUTC: data['roundKickoffTimeUTC'],
    );
  }

  Map toJson() => {
        'dAUroundName': dAUroundName,
        'roundKickoffTimeUTC': roundKickoffTimeUTC,
        'aflRoundNumber': aflRoundNumber,
        'nrlRoundNumber': nrlRoundNumber,
      };

  @override
  // method used to sort DAURounds in a List
  int compareTo(DAURound other) {
    return roundKickoffTimeUTC.compareTo(other.roundKickoffTimeUTC);
  }
}
