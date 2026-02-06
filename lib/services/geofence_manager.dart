import 'dart:async';
import 'package:geofence_service/geofence_service.dart';
import 'package:mybus/services/notification_service.dart'; // Assuming you have this or will implement a simple one here
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Top-level function for background execution
@pragma('vm:entry-point')
Future<void> _onGeofenceStatusChanged(
    Geofence geofence,
    GeofenceRadius geofenceRadius,
    GeofenceStatus geofenceStatus,
    Location location) async {
  
  print('GeofenceManager: ${geofence.id} status: $geofenceStatus');
  
  if (geofenceStatus == GeofenceStatus.ENTER) {
    await GeofenceManager.instance.handleGeofenceEntry(geofence);
  }
}

class GeofenceManager {
  // Singleton
  static final GeofenceManager instance = GeofenceManager._internal();
  GeofenceManager._internal();

  final _geofenceService = GeofenceService.instance.setup(
    interval: 5000,
    accuracy: 100,
    loiteringDelayMs: 60000,
    statusChangeDelayMs: 10000,
    useActivityRecognition: false,
    allowMockLocations: true,
    printDevLog: true,
    geofenceRadiusSortType: GeofenceRadiusSortType.DESC,
  );

  final _notificationPlugin = FlutterLocalNotificationsPlugin();
  
  // State
  List<dynamic> _allStops = [];
  int _destinationIndex = -1;
  int _currentStopIndex = 0;
  
  // Rolling window size
  static const int _windowSize = 3;

  Future<void> initialize() async {
    // Init local notifications for background triggers
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationPlugin.initialize(initSettings);

    _geofenceService.addGeofenceStatusChangeListener(_onGeofenceStatusChanged);
    _geofenceService.addStreamErrorListener((error) {
      print('GeofenceManager Error: $error');
    });
  }

  Future<void> startTrip(List<dynamic> stops, int destinationIndex) async {
    _allStops = stops;
    _destinationIndex = destinationIndex;
    _currentStopIndex = 0; // Assume start from beginning or find closest?
    
    // Logic to find closest monitoring point could be added here, 
    // but usually we start from where the user selected directly.
    
    await _geofenceService.start();
    await _updateGeofences();
  }

  Future<void> stopTrip() async {
    await _geofenceService.stop();
    _geofenceService.clearGeofenceList();
    _allStops = [];
    _destinationIndex = -1;
  }

  Future<void> handleGeofenceEntry(Geofence geofence) async {
    final stopId = geofence.id;
    final index = _allStops.indexWhere((s) => s.id == stopId);
    
    if (index != -1) {
      _currentStopIndex = index + 1; // Moved past this stop
      
      int remaining = _destinationIndex - index;
      
      print("GeofenceManager: Passed stop $index. Remaining: $remaining");

      // Critical: Notification Logic
      // Only notify if 3 or fewer stops remain
      if (remaining <= 3 && remaining >= 0) {
        await _sendNotification(remaining);
      }
      
      // Update window
      await _updateGeofences();
    }
  }

  Future<void> _updateGeofences() async {
    if (_allStops.isEmpty || _destinationIndex == -1) return;

    final geofenceList = <Geofence>[];
    
    // Register next N stops starting from current _currentStopIndex
    // We only need to geofence UP TO the destination.
    int endIndex = (_currentStopIndex + _windowSize).clamp(0, _destinationIndex + 1);
    
    for (int i = _currentStopIndex; i < endIndex; i++) {
      // Don't register if we are already past it (check distance?)
      // For now, simple index logic
      final stop = _allStops[i];
      geofenceList.add(Geofence(
        id: stop.id,
        latitude: stop.lat,
        longitude: stop.lon,
        radius: [
          GeofenceRadius(id: 'radius_100m', length: 150),
        ],
      ));
    }

    _geofenceService.clearGeofenceList();
    if (geofenceList.isNotEmpty) {
      _geofenceService.addGeofenceList(geofenceList);
      print("GeofenceManager: Registered ${geofenceList.length} geofences. Next: ${_allStops[_currentStopIndex].name}");
    }
  }

  Future<void> _sendNotification(int remaining) async {
    String title = "Viagem em Andamento";
    String body = "";
    
    if (remaining == 0) {
      title = "Você chegou!";
      body = "Prepare-se para descer no próximo ponto.";
    } else {
      body = "Faltam $remaining paradas para o seu destino.";
    }

    const androidDetails = AndroidNotificationDetails(
      'mybus_geofence', 
      'Geofence Alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    await _notificationPlugin.show(
      DateTime.now().millisecond, 
      title, 
      body, 
      const NotificationDetails(android: androidDetails),
    );
  }
}
