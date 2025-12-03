import '../models/bus_stop.dart';
import '../models/itinerario.dart';
import 'stop_service.dart';

class ItineraryStopMapper {
  final StopService _stopService = StopService();

  /// Groups bus stops by street (Ponto) for a given itinerario
  /// Uses the Street Name from the geocoded data to match stops to streets
  Map<Ponto, List<BusStop>> groupStopsByStreet(
    Itinerario itinerario,
    String lineCode,
    String direction,
  ) {
    final allStops = _stopService.getStopsForLine(lineCode, direction);
    final Map<Ponto, List<BusStop>> grouped = {};

    if (allStops.isEmpty || itinerario.pontos.isEmpty) {
      return grouped;
    }

    // For each street in the itinerario
    for (var ponto in itinerario.pontos) {
      // Normalize the street name from the itinerario
      final pontoName = _normalizeStreetName(ponto.nome);
      
      // Skip if normalized name is empty
      if (pontoName.isEmpty) {
        grouped[ponto] = [];
        continue;
      }
      
      // Find all stops that match this street name
      final matchingStops = allStops.where((stop) {
        final stopStreetName = _normalizeStreetName(stop.streetName);
        
        if (stopStreetName.isEmpty) return false;
        
        // Exact match - always accept
        if (stopStreetName == pontoName) {
          return true;
        }
        
        // For single letter streets (e.g., "b"), be more lenient
        // Match if the stop street starts with that letter
        if (pontoName.length == 1) {
          return stopStreetName.startsWith(pontoName);
        }
        
        // For very short names (2-4 chars), require that one starts with the other
        if (pontoName.length <= 4 || stopStreetName.length <= 4) {
          return stopStreetName.startsWith(pontoName) || pontoName.startsWith(stopStreetName);
        }
        
        // For longer names, use fuzzy matching with threshold
        // Require at least 60% of the shorter string to match
        final minLength = pontoName.length < stopStreetName.length ? pontoName.length : stopStreetName.length;
        
        if (pontoName.contains(stopStreetName)) {
          if (stopStreetName.length >= minLength * 0.6) {
            return true;
          }
        }
        
        if (stopStreetName.contains(pontoName)) {
          if (pontoName.length >= minLength * 0.6) {
            return true;
          }
        }
        
        // Check if the core names match (ignoring titles)
        final pontoCore = _extractCoreName(pontoName);
        final stopCore = _extractCoreName(stopStreetName);
        
        if (pontoCore.isNotEmpty && stopCore.isNotEmpty && 
            pontoCore.length >= 3 && stopCore.length >= 3) {
          if (pontoCore == stopCore) {
            return true;
          }
          
          // Only allow partial core matches if they're substantial
          final coreMinLength = pontoCore.length < stopCore.length ? pontoCore.length : stopCore.length;
          if (pontoCore.contains(stopCore) && stopCore.length >= coreMinLength * 0.7) {
            return true;
          }
          if (stopCore.contains(pontoCore) && pontoName.length >= coreMinLength * 0.7) {
            return true;
          }
        }
        
        return false;
      }).toList();
      
      grouped[ponto] = matchingStops;
    }

    return grouped;
  }

  /// Normalize street names for comparison
  /// Handles API format: "07-Avenida Castro, Cônego de" -> "Castro Conego de"
  String _normalizeStreetName(String name) {
    if (name.isEmpty) return '';
    
    String normalized = name.trim();
    
    // Remove numeric prefix (e.g., "07-")
    normalized = normalized.replaceAll(RegExp(r'^\d+-'), '').trim();
    
    // Remove neighborhood qualifiers in parentheses
    normalized = normalized.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    
    // Convert to lowercase for comparison
    normalized = normalized.toLowerCase();
    
    // Remove common street type prefixes
    final prefixes = [
      'rua', 'avenida', 'av.', 'av', 'travessa', 'trav.', 
      'alameda', 'praça', 'largo', 'rodovia', 'via', 'estrada', 'ciclovia'
    ];
    
    for (var prefix in prefixes) {
      if (normalized.startsWith('$prefix ')) {
        normalized = normalized.substring(prefix.length + 1).trim();
        break;
      }
    }
    
    // Handle inverted names (e.g., "Castro, Cônego de" -> "Conego de Castro")
    if (normalized.contains(',')) {
      final parts = normalized.split(',').map((p) => p.trim()).toList();
      if (parts.length >= 2) {
        normalized = '${parts[1]} ${parts[0]}'.trim();
      }
    }
    
    // Remove accents for better matching
    normalized = _removeAccents(normalized);
    
    return normalized;
  }

  /// Extract core name by removing titles and honorifics
  String _extractCoreName(String name) {
    // Remove common titles
    final titles = [
      'conego', 'general', 'gal', 'dom', 'dona', 'sao', 'santa',
      'prof', 'professor', 'doutor', 'dr', 'eng', 'engenheiro',
      'coronel', 'cel', 'major', 'tenente', 'sargento', 'cabo',
      'visconde', 'barao', 'conde', 'frei', 'padre', 'monsenhor'
    ];
    
    List<String> words = name.split(' ');
    words = words.where((word) => 
      word.isNotEmpty && 
      !titles.contains(word.toLowerCase()) &&
      word != 'de' && word != 'do' && word != 'da' && word != 'dos' && word != 'das'
    ).toList();
    
    return words.join(' ');
  }

  /// Remove accents from string
  String _removeAccents(String str) {
    const withAccents = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
    const withoutAccents = 'aaaaaaeeeeiiiiooooouuuucn';
    
    String result = str;
    for (int i = 0; i < withAccents.length; i++) {
      result = result.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return result;
  }

  /// Get a specific stop by ID
  BusStop? getStopById(String stopId) {
    return _stopService.getStopById(stopId);
  }
}
