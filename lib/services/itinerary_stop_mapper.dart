import '../models/bus_stop.dart';
import '../models/itinerario.dart';
import 'stop_service.dart';

class ItineraryStopMapper {
  final StopService _stopService = StopService();

  /// Groups bus stops by street (Ponto) for a given itinerary
  /// Returns a map where the key is the Ponto and the value is a list of BusStops on that street
  Map<Ponto, List<BusStop>> groupStopsByStreet(
    Itinerario itinerario,
    String lineCode,
    String direction,
  ) {
    final allStops = _stopService.getStopsForLine(lineCode, direction);
    final Map<Ponto, List<BusStop>> grouped = {};

    // For each street in the itinerary, we'll collect stops
    // Since we don't have a direct mapping, we'll use the order of stops
    // to match them to streets in the itinerary
    
    // This is a simplified approach - in reality, you'd need additional data
    // to properly map stops to streets. For now, we'll distribute stops
    // evenly across the streets based on their order.
    
    if (allStops.isEmpty || itinerario.pontos.isEmpty) {
      return grouped;
    }

    // Calculate how many stops per street (approximate)
    int stopsPerStreet = (allStops.length / itinerario.pontos.length).ceil();
    
    for (int i = 0; i < itinerario.pontos.length; i++) {
      final ponto = itinerario.pontos[i];
      final startIdx = i * stopsPerStreet;
      final endIdx = ((i + 1) * stopsPerStreet).clamp(0, allStops.length);
      
      if (startIdx < allStops.length) {
        grouped[ponto] = allStops.sublist(
          startIdx,
          endIdx,
        );
      } else {
        grouped[ponto] = [];
      }
    }

    return grouped;
  }

  /// Get a specific stop by ID
  BusStop? getStopById(String stopId) {
    return _stopService.getStopById(stopId);
  }
}
