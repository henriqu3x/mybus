import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class NominatimService {
  static Future<LatLng?> getCoordinates(String street, {String city = 'fortaleza'}) async {
    final url = Uri.parse('https://nominatim.openstreetmap.org/search?city=$city&street=$street&format=json');
    try {
      final response = await http.get(url, headers: {
        'User-Agent': 'MyBusApp/1.0 (your-email@example.com)'
      });
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          final firstResult = data.first;
          final lat = double.tryParse(firstResult['lat'].toString());
          final lon = double.tryParse(firstResult['lon'].toString());
          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }
    } catch (e) {
      // Handle or log error
    }
    return null;
  }
}
