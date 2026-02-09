import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geofence_service/geofence_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// ================= BACKGROUND ENTRY POINT =================
@pragma('vm:entry-point')
Future<void> onGeofenceStatusChanged(
  Geofence geofence,
  GeofenceRadius geofenceRadius,
  GeofenceStatus geofenceStatus,
  Location location,
) async {
  if (geofenceStatus == GeofenceStatus.ENTER) {
    await GeofenceManager.instance._handleGeofenceEntry(geofence);
  }
}

/// ================= MANAGER =================
class GeofenceManager {
  static final GeofenceManager instance = GeofenceManager._internal();
  GeofenceManager._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final GeofenceService _geofenceService = GeofenceService.instance.setup(
    interval: 5000,
    accuracy: 100,
    loiteringDelayMs: 0, // ❗ parada de ônibus ≠ permanência
    statusChangeDelayMs: 5000,
    useActivityRecognition: false,
    allowMockLocations: true,
    printDevLog: kDebugMode,
    geofenceRadiusSortType: GeofenceRadiusSortType.ASC,
  );

  // ================= STATE =================

  List<dynamic> _stops = [];
  int _destinationIndex = -1;
  int _currentIndex = 0;

  static const int _windowSize = 3;
  bool _initialized = false;

  // ================= INIT =================

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(settings);

    _geofenceService.addGeofenceStatusChangeListener(
      onGeofenceStatusChanged,
    );

    _geofenceService.addStreamErrorListener((error) {
      debugPrint('Geofence error: $error');
    });

    _initialized = true;
  }

  // ================= TRIP =================

  Future<void> startTrip(
    List<dynamic> orderedStops,
    int destinationIndex,
  ) async {
    if (orderedStops.isEmpty || destinationIndex < 0) return;

    _stops = orderedStops;
    _destinationIndex = destinationIndex;
    _currentIndex = 0;

    await _geofenceService.start();
    await _registerWindow();
  }

  Future<void> stopTrip() async {
    await _geofenceService.stop();
    _geofenceService.clearGeofenceList();

    _stops = [];
    _destinationIndex = -1;
    _currentIndex = 0;
  }

  // ================= CORE =================

  Future<void> _handleGeofenceEntry(Geofence geofence) async {
    final index = _stops.indexWhere((s) => s.id == geofence.id);
    if (index == -1) return;

    // Proteção contra eventos duplicados
    if (index < _currentIndex) return;

    _currentIndex = index + 1;
    final remaining = _destinationIndex - index;

    debugPrint(
      'Geofence ENTER: ${geofence.id} | Remaining: $remaining',
    );

    if (remaining <= 3 && remaining >= 0) {
      await _notify(remaining);
    }

    await _registerWindow();
  }

  // ================= WINDOW =================

  Future<void> _registerWindow() async {
    if (_stops.isEmpty || _destinationIndex < 0) return;

    final List<Geofence> geofences = [];

    final end = (_currentIndex + _windowSize)
        .clamp(0, _destinationIndex + 1);

    for (int i = _currentIndex; i < end; i++) {
      final stop = _stops[i];

      geofences.add(
        Geofence(
          id: stop.id,
          latitude: stop.lat,
          longitude: stop.lon,
          radius: [
            GeofenceRadius(
              id: '150m',
              length: 150,
            ),
          ],
        ),
      );
    }

    _geofenceService.clearGeofenceList();

    if (geofences.isNotEmpty) {
      _geofenceService.addGeofenceList(geofences);
      debugPrint(
        'Registered ${geofences.length} geofences. '
        'Next index: $_currentIndex',
      );
    }
  }

  // ================= NOTIFY =================

  Future<void> _notify(int remaining) async {
    final String title;
    final String body;

    if (remaining == 0) {
      title = 'Você chegou!';
      body = 'Prepare-se para descer no próximo ponto.';
    } else {
      title = 'Viagem em andamento';
      body = 'Faltam $remaining paradas para o seu destino.';
    }

    const androidDetails = AndroidNotificationDetails(
      'mybus_geofence',
      'Alertas de Parada',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }
}
