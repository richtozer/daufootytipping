import 'package:daufootytipping/models/location_latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class GoogleGeoCodingService {
  final Map<String, LatLng> _cache = {};

  Future<LatLng> getLatLng(String location) async {
    if (_cache.containsKey(location)) {
      return _cache[location]!;
    }

    final String locationParsed = location
        .replaceAll('SCG', 'Sydney Cricket Ground')
        .replaceAll('MCG', 'Melbourne Cricket Ground')
        .replaceAll('GMHBA', 'GMHBA Stadium')
        .replaceAll('Marvel', 'Marvel Stadium')
        .replaceAll('Gabba', 'The Gabba');

    const String apiKey =
        'AIzaSyBeRL8Mg6Ddi7puncMleKQKR_FZKrBf92g'; // TODO remove hard coding
    final String url =
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(locationParsed)}&key=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['results'] is List && data['results'].isNotEmpty) {
        final lat = data['results'][0]['geometry']['location']['lat'];
        final lng = data['results'][0]['geometry']['location']['lng'];
        final latLng = LatLng(lat: lat, lng: lng);
        _cache[location] = latLng;
        return latLng;
      }
    }

    throw Exception('Failed to get lat long for $location');
  }
}
