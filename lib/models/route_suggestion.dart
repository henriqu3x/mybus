import '../models/line.dart';
import '../models/logradouro.dart';
import '../services/haversine_calculator.dart';

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

class RouteStep {
  final Logradouro? from;
  final Logradouro? to;
  final Line? line;
  final bool isWalking;

  RouteStep({
    this.from,
    this.to,
    this.line,
    required this.isWalking,
  });
}

class RouteSuggestion {
  final String description;
  final int connections;
  final List<RouteStep> steps;
  final double totalCostMinutes;

  RouteSuggestion({
    required this.description,
    required this.connections,
    required this.steps,
    required this.totalCostMinutes,
  });

  factory RouteSuggestion.walkingOnly(double distanceKm, Logradouro origin, Logradouro destination) {
    final time = HaversineCalculator.distanceToWalkingTimeMinutes(distanceKm);
    return RouteSuggestion(
      description: 'Caminhada (direta)',
      connections: 0,
      steps: [
        RouteStep(
          from: origin,
          to: destination,
          line: null,
          isWalking: true,
        ),
      ],
      totalCostMinutes: time,
    );
  }

  // Getters for compatibility
  List<RouteSegment> get segments => steps.map((step) => RouteSegment(
    type: step.isWalking ? 'walking' : 'bus',
    description: step.isWalking ? 'Caminhe' : 'Pegue o ônibus ${step.line?.numeroNome ?? ''}',
    distance: step.from != null && step.to != null ? HaversineCalculator.calculateDistance(step.from!.latitude, step.from!.longitude, step.to!.latitude, step.to!.longitude) : 0.0,
    time: step.isWalking ? HaversineCalculator.distanceToWalkingTimeMinutes(step.from != null && step.to != null ? HaversineCalculator.calculateDistance(step.from!.latitude, step.from!.longitude, step.to!.latitude, step.to!.longitude) : 0.0) : HaversineCalculator.distanceToBusTravelTimeMinutes(step.from != null && step.to != null ? HaversineCalculator.calculateDistance(step.from!.latitude, step.from!.longitude, step.to!.latitude, step.to!.longitude) : 0.0, 20.0),
    line: step.line,
    from: step.from,
    to: step.to,
  )).toList();

  double get totalDistance => steps.fold(0.0, (sum, step) => sum + (step.from != null && step.to != null ? HaversineCalculator.calculateDistance(step.from!.latitude, step.from!.longitude, step.to!.latitude, step.to!.longitude) : 0.0));

  double get totalTime => totalCostMinutes;

  int get transferCount => connections;
}
