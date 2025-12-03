import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/bus_stop.dart';

class StopService {
  static final StopService _instance = StopService._internal();
  factory StopService() => _instance;
  StopService._internal();

  List<BusStop>? _allStops;
  bool _isLoaded = false;

  /// Load and parse the bus stops JSON file
  Future<void> loadStops() async {
    if (_isLoaded) return;

    try {
      final String jsonString = await rootBundle.loadString('paradas.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      
      _allStops = jsonList.map((json) => BusStop.fromJson(json)).toList();
      _isLoaded = true;
    } catch (e) {
      print('Error loading stops: $e');
      _allStops = [];
      _isLoaded = true;
    }
  }

  /// Get all stops for a specific line and direction
  List<BusStop> getStopsForLine(String lineCode, String direction) {
    if (_allStops == null) return [];
    
    return _allStops!
        .where((stop) => 
            stop.routeCode == lineCode && 
            stop.direction == direction)
        .toList();
  }

  /// Get coordinates for a specific stop ID
  BusStop? getStopById(String stopId) {
    if (_allStops == null) return null;
    
    try {
      return _allStops!.firstWhere((stop) => stop.stopId == stopId);
    } catch (e) {
      return null;
    }
  }

  /// Get all unique line codes
  Set<String> getAllLineCodes() {
    if (_allStops == null) return {};
    return _allStops!.map((stop) => stop.routeCode).toSet();
  }
}
