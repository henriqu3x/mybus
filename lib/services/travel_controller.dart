import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'geofence_manager.dart';

class TravelController extends ChangeNotifier {
  StreamSubscription<Position>? _positionStream;
  LatLng? currentPosition;
  
  // Configuração de Foreground Service para Android (Visual apenas)
  final ForegroundNotificationConfig _fgConfig = const ForegroundNotificationConfig(
    notificationTitle: "Viagem em Andamento",
    notificationText: "O app está monitorando sua parada em tempo real.",
    notificationIcon: AndroidResource(name: 'notification_icon', defType: 'drawable'),
    enableWakeLock: true,
  );

  Future<void> startMonitoring({
    required List<dynamic> sortedStops, 
    required dynamic destinationStop,
  }) async {
    // Cancela fluxos anteriores
    stopMonitoring();

    // 1. Iniciar Geofencing (Background Logic)
    await GeofenceManager.instance.initialize();
    int destIndex = sortedStops.indexWhere((s) => s.id == destinationStop.id);
    await GeofenceManager.instance.startTrip(sortedStops, destIndex);

    // 2. Iniciar Foreground Stream (UI Updates apenas)
    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
        foregroundNotificationConfig: _fgConfig,
      ),
    ).listen((Position position) {
      currentPosition = LatLng(position.latitude, position.longitude);
      notifyListeners();
    });
  }

  void stopMonitoring() {
    _positionStream?.cancel();
    GeofenceManager.instance.stopTrip();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}