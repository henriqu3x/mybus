import 'dart:math';

class HaversineCalculator {
  // Raio da Terra em quilômetros
  static const double R = 6371.0; 
  // Velocidade média de caminhada em km/h (4.5 km/h é um bom padrão)
  static const double walkingSpeedKmH = 4.5; 

  /// Calcula a distância Haversine entre dois pontos em quilômetros.
  static double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);

    final a = pow(sin(dLat / 2), 2) +
        pow(sin(dLon / 2), 2) * cos(lat1Rad) * cos(lat2Rad);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return R * c; 
  }

  /// Converte uma distância em quilômetros para o tempo de caminhada em minutos.
  static double distanceToWalkingTimeMinutes(double distanceKm) {
    // Tempo (horas) = Distância (km) / Velocidade (km/h)
    final timeHours = distanceKm / walkingSpeedKmH;
    return timeHours * 60; // Retorna em minutos
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}