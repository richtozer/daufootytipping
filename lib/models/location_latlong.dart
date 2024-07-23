class LatLng {
  final double lat;
  final double lng;

  const LatLng({required this.lat, required this.lng});

  LatLng.fromJson(Map<String, dynamic> json)
      : lat = json['lat'].toDouble(),
        lng = json['lng'].toDouble();

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
      };
}
