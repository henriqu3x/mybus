import 'package:flutter/material.dart';
import '../models/linha.dart';
import '../models/itinerario.dart';
import '../models/horario.dart';
import '../models/logradouro.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/graph_utils.dart';
import '../utils/time_utils.dart';

class BusProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Linha> _linhas = [];
  List<Linha> _filteredLinhas = [];
  List<Logradouro> _logradouros = [];
  
  bool _isLoading = false;
  String? _error;

  // Cache for itineraries to build graph
  final Map<int, ItinerarioCompleto> _itinerarioCache = {};
  TransportGraph? _graph;
  bool _isGraphBuilding = false;

  List<Linha> get linhas => _filteredLinhas;
  List<Logradouro> get logradouros => _logradouros;
  bool get isGraphReady => _graph != null;
  bool get isGraphBuilding => _isGraphBuilding;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void>? _linesLoadingFuture;

  Future<void> fetchLinhas({bool forceRefresh = false}) async {
    // If loading is already in progress, return the existing future
    if (_linesLoadingFuture != null) {
      return _linesLoadingFuture;
    }

    // If data exists and we are not forcing refresh, return immediately
    if (_linhas.isNotEmpty && !forceRefresh) return;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Create a new future and assign it
    _linesLoadingFuture = _fetchLinhasInternal();
    
    try {
      await _linesLoadingFuture;
    } finally {
      // Clear the future when done so next call can refresh if needed
      _linesLoadingFuture = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchLinhasInternal() async {
    try {
      _linhas = await _apiService.getLinhas();
      _filteredLinhas = _linhas;
    } catch (e) {
      _error = 'Erro ao carregar linhas. Verifique sua conexão.';
    }
  }

  void filterLinhas(String query) {
    if (query.isEmpty) {
      _filteredLinhas = _linhas;
    } else {
      _filteredLinhas = _linhas.where((linha) {
        return linha.nome.toLowerCase().contains(query.toLowerCase()) ||
            linha.numeroNome.toLowerCase().contains(query.toLowerCase());
      }).toList();
    }
    notifyListeners();
  }

  Linha? getLineByNumber(String number) {
    try {
      final num = int.tryParse(number);
      if (num == null) return null;
      
      return _linhas.firstWhere(
        (l) => l.numero == num,
        orElse: () => Linha(
            numero: num, 
            nome: 'Linha $number', 
            numeroNome: 'Linha $number', 
            tipoLinha: ''
        ),
      );
    } catch (e) {
      return null;
    }
  }

  Future<ItinerarioCompleto> getItinerario(int idLinha) async {
    if (_itinerarioCache.containsKey(idLinha)) {
      return _itinerarioCache[idLinha]!;
    }
    final itinerario = await _apiService.getItinerario(idLinha);
    _itinerarioCache[idLinha] = itinerario;
    return itinerario;
  }

  Future<List<HorarioPosto>> getHorarios(int idLinha, String data) async {
    return await _apiService.getHorarios(idLinha, data);
  }

  Future<void> fetchLogradouros() async {
    try {
      _logradouros = await _apiService.getLogradouros();
      notifyListeners();
    } catch (e) {
    }
  }

  Future<void> buildGraph() async {
    if (_isGraphBuilding || _graph != null) return;
    _isGraphBuilding = true;
    notifyListeners();

    try {
      if (_linhas.isEmpty) {
        await fetchLinhas();
      }

      // Get current date in YYYYMMDD format
      final now = DateTime.now();
      final dateStr =
          "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";

      List<Map<String, dynamic>> allItineraries = [];

      // Process in batches to avoid overwhelming the server but still be faster than sequential
      int batchSize = 5;
      for (var i = 0; i < _linhas.length; i += batchSize) {
        var end = (i + batchSize < _linhas.length)
            ? i + batchSize
            : _linhas.length;
        var batch = _linhas.sublist(i, end);

        await Future.wait(
          batch.map((linha) async {
            try {
              // Check schedule
              bool isActive = false;
              try {
                final horarios = await getHorarios(linha.numero, dateStr);
                if (horarios.isNotEmpty) isActive = true;
              } catch (e) {
                // Ignore error, treat as inactive
              }

              if (isActive) {
                var itinerarioCompleto = await getItinerario(linha.numero);
                  if (itinerarioCompleto.ida != null) {
                  allItineraries.add({
                    'line': '${linha.numeroNome.trim()}_IDA',
                    'itinerario': itinerarioCompleto.ida,
                  });
                }
                if (itinerarioCompleto.volta != null) {
                  allItineraries.add({
                    'line': '${linha.numeroNome.trim()}_VOLTA',
                    'itinerario': itinerarioCompleto.volta,
                  });
                }
              }
            } catch (e) {
            }
          }),
        );
      }

      _graph = TransportGraph();
      _graph!.buildFromItineraries(allItineraries);
    } catch (e) {
    } finally {
      _isGraphBuilding = false;
      notifyListeners();
    }
  }

  /// Finds up to 3 distinct routes between start and end.
  Future<List<List<GraphEdge>>> findRoutes(int startLogId, int endLogId) async {
    final List<List<GraphEdge>> foundRoutes = [];
    if (_graph == null) return foundRoutes;

    final Map<String, int> initialWaitTimes = await _calculateInitialWaitTimes(startLogId); // Refactored helper
    final Set<String> penalizedLines = {};

    // Try to find up to 3 routes
    for (int i = 0; i < 3; i++) {
        final route = await _findSingleValidRoute(
            startLogId, 
            endLogId, 
            initialWaitTimes,
            penalizedLines: penalizedLines // Pass cached penalties
        );

        if (route != null) {
            // Check if this route is significantly different or new?
            // For now, assume penalties make it different enough.
            // But we should check for duplicates in IDs/Structure if needed.
             // Simple duplicate check based on string representation of lines
            final routeStr = route.map((e) => e.lineName).join(',');
            final isDuplicate = foundRoutes.any((r) => r.map((e) => e.lineName).join(',') == routeStr);

            if (!isDuplicate) {
                foundRoutes.add(route);

                // Add lines from this route to penalized set to encourage variety
                for (final edge in route) {
                    penalizedLines.add(edge.lineName);
                }
            } else {
                // If we found a duplicate, maybe stop or try harder? 
                // If current penalty resulted in same route, stop trying.
                break;
            }
        } else {
            // No more routes found
            break;
        }
    }
    
    return foundRoutes;
  }

  // Refactored from previous big method
  Future<List<GraphEdge>?> _findSingleValidRoute(
      int startLogId, 
      int endLogId, 
      Map<String, int> initialWaitTimes,
      {Set<String>? penalizedLines}
  ) async {
     // Iterative validation: find route, validate all segments, exclude bad lines, retry
    final Set<String> excludedLines = {}; // Hard exclude for invalid schedules
    int attempts = 0;
    const maxAttempts = 5;
    
    final today = DateTime.now();
    final dateStr = "${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}";
    final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;
    
    while (attempts < maxAttempts) {
      var route = _graph!.findShortestPath(
        startLogId, 
        endLogId, 
        initialWaitTimes: initialWaitTimes,
        excludedLines: excludedLines,
        penalizedLines: penalizedLines,
      );
      
      if (route == null || route.isEmpty) {
        return null;
      }
      
      // Validate all segments of the route
      final invalidLine = await _validateRouteSegments(route, currentMinutes, dateStr);
      
      if (invalidLine == null) {
        return route;
      }
      
      // Route has invalid segment, exclude that line and retry
      excludedLines.add(invalidLine);
      attempts++;
    }
    
    return null;
  }

  // Helper method extracted from original code to reuse in findRoutes
  // Need to implement this helper as it wasn't separate before
  Future<Map<String, int>> _calculateInitialWaitTimes(int startLogId) async {
    final Map<String, int> initialWaitTimes = {};
    final today = DateTime.now();
    final dateStr = "${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}";
    final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;

      for (var linha in _linhas) {
        if (!_itinerarioCache.containsKey(linha.numero)) continue;
        
        final itinerarioCompleto = _itinerarioCache[linha.numero]!;

        // Check Ida
        if (itinerarioCompleto.ida != null) {
           double dist = 0;
           bool found = false;
           for (var p in itinerarioCompleto.ida!.pontos) {
             if (p.logId == startLogId) {
               found = true;
               break;
             }
             dist += p.distanciaPercorrida;
           }
           
           if (found) {
             final wait = await _calculateNextBusWaitTime(
               linha.numero, 
               dateStr, 
               itinerarioCompleto.ida!.pontoInicial, 
               dist, 
               currentMinutes
             );
             final key = '${linha.numeroNome.trim()}_IDA';
             if (wait != null) {
               if (wait > 45) {
                 initialWaitTimes[key] = 999999;
               } else {
                 initialWaitTimes[key] = wait;
               }
             } else {
               initialWaitTimes[key] = 999999;
             }
           }
        }

        // Check Volta
        if (itinerarioCompleto.volta != null) {
           double dist = 0;
           bool found = false;
           for (var p in itinerarioCompleto.volta!.pontos) {
             if (p.logId == startLogId) {
               found = true;
               break;
             }
             dist += p.distanciaPercorrida;
           }
           
           if (found) {
             final wait = await _calculateNextBusWaitTime(
               linha.numero, 
               dateStr, 
               itinerarioCompleto.volta!.pontoInicial, 
               dist, 
               currentMinutes
             );
             final key = '${linha.numeroNome.trim()}_VOLTA';
             if (wait != null) {
               if (wait > 45) {
                 initialWaitTimes[key] = 999999;
               } else {
                 initialWaitTimes[key] = wait;
               }
             } else {
               initialWaitTimes[key] = 999999;
             }
           }
        }
      }
      return initialWaitTimes;
  }

  /// Validates all segments of a route by simulating the journey timeline.
  /// Returns the line name that failed validation, or null if route is valid.
  Future<String?> _validateRouteSegments(
    List<GraphEdge> route, 
    int startMinutes,
    String dateStr,
  ) async {
    int currentMinutes = startMinutes;
    String? previousLine;
    
    for (int i = 0; i < route.length; i++) {
      final edge = route[i];
      
      // Check if this is a transfer (new line)
      if (edge.lineName != previousLine) {
        // Extract line number from name like "051-Name_IDA"
        String lineNameClean = edge.lineName.replaceAll('_IDA', '').replaceAll('_VOLTA', '').trim();
        final match = RegExp(r'^(\d+)').firstMatch(lineNameClean);
        if (match == null) continue;
        
        int lineNum = int.parse(match.group(1)!);
        
        // Get the boarding stop ID
        // For first segment (i==0), we already validated via initialWaitTimes
        // For transfers (i>0), boarding happens at previous edge's destination
        if (i > 0) {
          int boardingStopId = route[i - 1].destination.id;
          
          // Get itinerary to find this stop
          var itinerarioCompleto = await getItinerario(lineNum);
          var itinerario = edge.lineName.endsWith('_VOLTA') 
              ? itinerarioCompleto.volta 
              : itinerarioCompleto.ida;
          
          if (itinerario == null) {
            return edge.lineName; // No itinerary = invalid
          }
          
          // Find the boarding stop in the itinerary and calculate distance
          double dist = 0;
          bool found = false;
          for (var p in itinerario.pontos) {
            if (p.logId == boardingStopId) {
              found = true;
              break;
            }
            dist += p.distanciaPercorrida;
          }
          
          if (!found) {
            return edge.lineName; // Stop not in itinerary = invalid
          }
          
          // Calculate wait time at this transfer point
          final waitMinutes = await _calculateNextBusWaitTime(
            lineNum,
            dateStr,
            itinerario.pontoInicial,
            dist,
            currentMinutes,
          );
          
          if (waitMinutes == null || waitMinutes > 45) {
            return edge.lineName; // No bus or wait > 45min = invalid
          }
          
          // Add wait time to current time
          currentMinutes += waitMinutes;
        }
      }
      
      // Add travel time for this segment
      int travelMinutes = TimeUtils.calculateTravelTimeMinutes(edge.weight);
      currentMinutes += travelMinutes;
      
      previousLine = edge.lineName;
    }
    
    return null; // All segments valid
  }

  Future<int?> _calculateNextBusWaitTime(
    int linhaId, 
    String date, 
    String pontoInicial, 
    double distanceToStop, 
    int currentMinutes
  ) async {
    try {
      final horarios = await getHorarios(linhaId, date);
      
      // Find matching control point
      HorarioPosto? matchingPosto;
      for (var posto in horarios) {
        if (_areNamesSimilar(posto.postoControle, pontoInicial)) {
          matchingPosto = posto;
          break;
        }
      }
      
      if (matchingPosto == null && horarios.isNotEmpty) {
         // Fallback if only one exists
         if (horarios.length == 1) matchingPosto = horarios.first;
      }

      if (matchingPosto == null) return null;

      final travelMinutes = TimeUtils.calculateTravelTimeMinutes(distanceToStop);
      
      int? bestArrival;
      
      for (var h in matchingPosto.horarios) {
        try {
          final parts = h.horario.split(':');
          final departureMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
          final arrivalMinutes = departureMinutes + travelMinutes;
          
          if (arrivalMinutes > currentMinutes) {
            bestArrival = arrivalMinutes;
            break; // Sorted usually, so first one is next
          }
        } catch (e) {
          // ignore
        }
      }
      
      if (bestArrival != null) {
        return bestArrival - currentMinutes;
      }
    } catch (e) {
    }
    return null;
  }

  bool _areNamesSimilar(String name1, String name2) {
    final n1 = _normalizeName(name1);
    final n2 = _normalizeName(name2);
    
    if (n1.contains(n2) || n2.contains(n1)) return true;
    
    final words1 = n1.split(' ').where((w) => w.length > 2).toSet();
    final words2 = n2.split(' ').where((w) => w.length > 2).toSet();
    
    if (words1.isEmpty || words2.isEmpty) return false;
    
    final intersection = words1.intersection(words2);
    return intersection.length >= words1.length * 0.6 || 
           intersection.length >= words2.length * 0.6;
  }

  String _normalizeName(String name) {
    return name.toLowerCase()
        .replaceAll(RegExp(r'^\d+-'), '')
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'\b(de|da|do|dos|das|e|o|a)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<int?> getPredictedArrivalForStreet(int lineId, String streetName) async {
    try {
      final itinerarioCompleto = await getItinerario(lineId);
      final now = DateTime.now();
      final dateStr = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
      final horarios = await getHorarios(lineId, dateStr);
      final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;

      // Check both directions
      for (var itinerario in [itinerarioCompleto.ida, itinerarioCompleto.volta]) {
        if (itinerario == null) continue;

        // Find the point matching the street
        double cumulativeDist = 0;
        bool found = false;
        for (var ponto in itinerario.pontos) {
          if (_areNamesSimilar(ponto.nome, streetName)) {
            found = true;
            break;
          }
          cumulativeDist += ponto.distanciaPercorrida;
        }

        if (!found) continue;

        // Find matching HorarioPosto
        HorarioPosto? matchingPosto;
        for (var posto in horarios) {
          if (_areNamesSimilar(posto.postoControle, itinerario.pontoInicial)) {
            matchingPosto = posto;
            break;
          }
        }
        if (matchingPosto == null && horarios.length == 1) {
          matchingPosto = horarios.first;
        }
        if (matchingPosto == null) continue;

        // Collect departure minutes
        List<int> allDepartureMinutes = [];
        for (var h in matchingPosto.horarios) {
          try {
            final parts = h.horario.split(':');
            final mins = int.parse(parts[0]) * 60 + int.parse(parts[1]);
            allDepartureMinutes.add(mins);
          } catch (e) {
            // ignore
          }
        }
        allDepartureMinutes.sort();

        // Calculate travel time
        final travelMinutes = TimeUtils.calculateTravelTimeMinutes(cumulativeDist);

        // Find next arrival
        for (var depMins in allDepartureMinutes) {
          final arrivalMins = depMins + travelMinutes;
          if (arrivalMins > currentMinutes) {
            return arrivalMins - currentMinutes;
          }
        }
      }
    } catch (e) {
    }
    return null;
  }
}
