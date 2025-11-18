class RouteNode {
  final int logId;
  final double cost; // Total accumulated cost in minutes
  final RouteNode? predecessor;
  final int lineId; // -1 for walking
  final String lineName;
  final double segmentDistance; // Distance of this segment in km
  final double segmentTime; // Time for this segment in minutes

  RouteNode({
    required this.logId,
    required this.cost,
    this.predecessor,
    required this.lineId,
    required this.lineName,
    this.segmentDistance = 0.0,
    this.segmentTime = 0.0,
  });
}