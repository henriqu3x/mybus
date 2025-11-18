import '../models/line.dart';
import '../models/logradouro.dart';
import '../services/haversine_calculator.dart';

/// Representa uma etapa de uma rota
class RouteSegment {
  final String type; // 'walking' or 'bus'
  final String description;
  final double distance; // in km
  final double time; // in minutes
  final Line? line;
  final Logradouro? from;
  final Logradouro? to;

  RouteSegment({
    required this.type,
    required this.description,
    required this.distance,
    required this.time,
    this.line,
    this.from,
    this.to,
  });
}

class RouteSuggestion {
  final List<RouteSegment> segments;
  final double totalDistance;
  final double totalTime;
  final int transferCount;

  RouteSuggestion({
    required this.segments,
    required this.totalDistance,
    required this.totalTime,
    required this.transferCount,
  });

  // Factory for walking-only route
  factory RouteSuggestion.walkingOnly(double distanceKm) {
    final time = HaversineCalculator.distanceToWalkingTimeMinutes(distanceKm);
    return RouteSuggestion(
      segments: [
        RouteSegment(
          type: 'walking',
          description: 'Caminhe ${distanceKm.toStringAsFixed(2)} km',
          distance: distanceKm,
          time: time,
        ),
      ],
      totalDistance: distanceKm,
      totalTime: time,
      transferCount: 0,
    );
  }

  // Factory for route with connections
  factory RouteSuggestion.withConnection({
    required Line? firstLine,
    required Logradouro transferPoint,
    required Line? secondLine,
    required double totalCost,
  }) {
    // This is a simplified version - the actual implementation would build
    // detailed segments in the _reconstructRoute method
    return RouteSuggestion(
      segments: [
        if (firstLine != null)
          RouteSegment(
            type: 'bus',
            description: 'Pegue a linha ${firstLine.numeroNome}',
            distance: 0, // Will be calculated
            time: 0, // Will be calculated
            line: firstLine,
          ),
        if (secondLine != null)
          RouteSegment(
            type: 'bus',
            description: 'Transborde para a linha ${secondLine.numeroNome}',
            distance: 0, // Will be calculated
            time: 0, // Will be calculated
            line: secondLine,
          ),
      ],
      totalDistance: 0, // Will be calculated
      totalTime: totalCost,
      transferCount: secondLine != null ? 1 : 0,
    );
  }

  // Getters for compatibility with screens
  List<RouteSegment> get steps => segments;
  int get connections => transferCount;
  String get description => 'Rota com ${transferCount} conexão${transferCount != 1 ? 'ões' : ''}';
}
