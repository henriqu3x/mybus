class BusStop {
  final String routeCode;
  final String direction; // "Ida" or "Volta"
  final String stopId;
  final double latitude;
  final double longitude;

  BusStop({
    required this.routeCode,
    required this.direction,
    required this.stopId,
    required this.latitude,
    required this.longitude,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) {
    // Extract direction from "Route Code and Direction" field
    String fullDirection = json['Route Code and Direction'] ?? '';
    String direction = 'Ida';
    if (fullDirection.contains('Volta')) {
      direction = 'Volta';
    }

    // Convert coordinates from integer format to decimal degrees
    // Example: -3729017 -> -3.729017
    double lat = double.parse(json['Latitude'].toString()) / 1000000;
    double lon = double.parse(json['Longitude'].toString()) / 1000000;

    return BusStop(
      routeCode: json['Route Code'].toString(),
      direction: direction,
      stopId: json['[Pontos de Ônibus].ID'].toString(),
      latitude: lat,
      longitude: lon,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'routeCode': routeCode,
      'direction': direction,
      'stopId': stopId,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
