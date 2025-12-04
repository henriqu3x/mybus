class TimeUtils {
  static const double averageSpeedKmh =
      14.0; // Realistic urban bus speed in Fortaleza

  /// Calculates the travel time in minutes for a given distance in meters
  static int calculateTravelTimeMinutes(double distanceMeters) {
    // Speed in m/min = (25 * 1000) / 60
    const double speedMetersPerMinute = (averageSpeedKmh * 1000) / 60;
    return (distanceMeters / speedMetersPerMinute).round();
  }

  /// Adds minutes to a time string in "HH:mm" format.
  static String addMinutesToTime(String time, int minutesToAdd) {
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final totalMinutes = hour * 60 + minute + minutesToAdd;
      final newHour = (totalMinutes ~/ 60) % 24;
      final newMinute = totalMinutes % 60;

      return '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}';
    } catch (e) {
      return time;
    }
  }
}
