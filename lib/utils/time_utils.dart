class TimeUtils {
  static const double averageSpeedKmh = 13.0;

  static int calculateTravelTimeMinutes(double distanceMeters) {
    const double speedMetersPerMinute = (averageSpeedKmh * 1000) / 60;
    return (distanceMeters / speedMetersPerMinute).round();
  }

  /// Retorna um intervalo de tempo, ex: "10:13 - 10:17"
  static String getTimeInterval(String baseTime, int travelTimeMinutes) {
    // Calculamos o tempo central (previsão exata)
    // Se quiser dar uma margem maior para trânsito, 
    // você pode variar esses 2 minutos para mais ou para menos aqui.
    
    final startTime = addMinutesToTime(baseTime, travelTimeMinutes - 2);
    final endTime = addMinutesToTime(baseTime, travelTimeMinutes + 2);
    
    return '$startTime - $endTime';
  }

  static String addMinutesToTime(String time, int minutesToAdd) {
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      // Usamos DateTime para facilitar cálculos de virada de dia/hora
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day, hour, minute);
      final newDate = date.add(Duration(minutes: minutesToAdd));

      return '${newDate.hour.toString().padLeft(2, '0')}:${newDate.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return time;
    }
  }
}