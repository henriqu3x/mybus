import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'kml_service.dart';

class PersistenceService {
  static const String keyActiveTrip = 'active_trip';

  // Singleton pattern
  static final PersistenceService _instance = PersistenceService._internal();
  factory PersistenceService() => _instance;
  PersistenceService._internal();

  /// Saves the current trip details
  Future<void> saveActiveTrip(
    String lineName,
    StopInfo destination, {
    required bool enableNotifications,
    required bool enableBackground,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    final data = {
      'lineName': lineName,
      'destination': {
        'id': destination.id,
        'name': destination.name,
        'lat': destination.lat,
        'lon': destination.lon,
        'lines': destination.lines,
      },
      'enableNotifications': enableNotifications,
      'enableBackground': enableBackground,
    };
    
    await prefs.setString(keyActiveTrip, jsonEncode(data));
  }

  /// Retrieves the active trip details if any
  Future<Map<String, dynamic>?> getActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(keyActiveTrip);
    
    if (jsonStr == null) return null;
    
    try {
      final data = jsonDecode(jsonStr);
      // Reconstruct StopInfo
      final destData = data['destination'];
      final destination = StopInfo(
        id: destData['id'],
        name: destData['name'],
        lat: destData['lat'],
        lon: destData['lon'],
        lines: List<String>.from(destData['lines']),
      );
      
      return {
        'lineName': data['lineName'],
        'destination': destination,
        'enableNotifications': data['enableNotifications'] == true,
        'enableBackground': data['enableBackground'] == true,
      };
    } catch (e) {
      return null; // Corrupted data
    }
  }

  /// Clears the active trip
  Future<void> clearActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyActiveTrip);
  }
}
