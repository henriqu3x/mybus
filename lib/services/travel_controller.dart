import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
// Importe seus serviços de notificação e modelos aqui

class TravelController extends ChangeNotifier {
  StreamSubscription<Position>? _positionStream;
  int? _lastNotifiedRemaining;
  LatLng? currentPosition;
  
  // Configuração de Foreground Service para Android
  final ForegroundNotificationConfig _fgConfig = const ForegroundNotificationConfig(
    notificationTitle: "Viagem em Andamento",
    notificationText: "O app está monitorando sua parada em tempo real.",
    notificationIcon: AndroidResource(name: 'notification_icon', defType: 'drawable'), // certifique-se de ter um ícone
    enableWakeLock: true,
  );

  void startMonitoring({
    required List<dynamic> sortedStops, 
    required dynamic destinationStop,
    required Function(int) onNotifyProgressive,
    required Function() onNotifyArrival,
  }) {
    // Cancela stream anterior se existir
    _positionStream?.cancel();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Atualiza a cada 10 metros
        foregroundNotificationConfig: _fgConfig,
      ),
    ).listen((Position position) {
      currentPosition = LatLng(position.latitude, position.longitude);
      notifyListeners();

      _checkProximity(
        position, 
        sortedStops, 
        destinationStop, 
        onNotifyProgressive, 
        onNotifyArrival
      );
    });
  }

  void _checkProximity(Position pos, List<dynamic> stops, dynamic dest, Function(int) onProgress, Function() onArrival) {
    int destIndex = stops.indexWhere((s) => s.id == dest.id);
    if (destIndex == -1) return;

    // Achar parada mais próxima do GPS atual
    int closestIndex = 0;
    double minDistance = double.infinity;
    const distanceCalc = Distance();

    for (int i = 0; i < stops.length; i++) {
      final d = distanceCalc.as(LengthUnit.Meter, LatLng(pos.latitude, pos.longitude), LatLng(stops[i].lat, stops[i].lon));
      if (d < minDistance) {
        minDistance = d;
        closestIndex = i;
      }
    }

    if (closestIndex > destIndex) return; // Já passou da parada

    int remaining = destIndex - closestIndex;

    // Lógica de Notificação Progressiva (3, 2, 1 paradas)
    if (remaining <= 3 && remaining > 0) {
      if (_lastNotifiedRemaining != remaining) {
        onProgress(remaining);
        _lastNotifiedRemaining = remaining;
      }
    } 
    // Lógica de Chegada (Distância < 200m da parada final)
    else if (remaining == 0 && minDistance < 200) {
      if (_lastNotifiedRemaining != 0) {
        onArrival();
        _lastNotifiedRemaining = 0;
      }
    }
  }

  void stopMonitoring() {
    _positionStream?.cancel();
    _lastNotifiedRemaining = null;
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}