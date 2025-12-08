class TripSegment {
  final String type; // 'BUS'
  final String lineName;
  final String startStreetName;
  final String endStreetName;
  final double distance;
  final int startStopId;
  final int endStopId;

  TripSegment({
    required this.type,
    required this.lineName,
    required this.startStreetName,
    required this.endStreetName,
    required this.distance,
    this.startStopId = 0,
    this.endStopId = 0,
  });
}
