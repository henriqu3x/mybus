class TripSegment {
  final String type; // 'BUS'
  final String lineName;
  final String startStreetName;
  final String endStreetName;
  final double distance;
  
  TripSegment({
    required this.type,
    required this.lineName,
    required this.startStreetName,
    required this.endStreetName,
    required this.distance,
  });
}
