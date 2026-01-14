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

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'lineName': lineName,
      'startStreetName': startStreetName,
      'endStreetName': endStreetName,
      'distance': distance,
      'startStopId': startStopId,
      'endStopId': endStopId,
    };
  }

  factory TripSegment.fromJson(Map<String, dynamic> json) {
    return TripSegment(
      type: json['type'] as String,
      lineName: json['lineName'] as String,
      startStreetName: json['startStreetName'] as String,
      endStreetName: json['endStreetName'] as String,
      distance: (json['distance'] as num).toDouble(),
      startStopId: json['startStopId'] as int? ?? 0,
      endStopId: json['endStopId'] as int? ?? 0,
    );
  }
}
