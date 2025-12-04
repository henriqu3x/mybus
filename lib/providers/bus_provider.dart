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

  // Cache for itineraries to build graph
  final Map<int, ItinerarioCompleto> _itinerarioCache = {};
  TransportGraph? _graph;
  bool _isGraphBuilding = false;

  List<Linha> get linhas => _filteredLinhas;
  List<Logradouro> get logradouros => _logradouros;
  bool get isGraphReady => _graph != null;
  bool get isGraphBuilding => _isGraphBuilding;

  Future<void> fetchLinhas() async {
    try {
      _linhas = await _apiService.getLinhas();
      _filteredLinhas = _linhas;
      notifyListeners();
    } catch (e) {
      print('Error fetching linhas: $e');
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
      print('Error fetching logradouros: $e');
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
                    'line': linha.numeroNome,
                    'itinerario': itinerarioCompleto.ida,
                  });
                }
                if (itinerarioCompleto.volta != null) {
                  allItineraries.add({
                    'line': linha.numeroNome,
                    'itinerario': itinerarioCompleto.volta,
                  });
                }
              }
            } catch (e) {
              print('Error processing line ${linha.numero}: $e');
            }
          }),
        );
      }

      _graph = TransportGraph();
      _graph!.buildFromItineraries(allItineraries);
    } catch (e) {
      print('Error building graph: $e');
    } finally {
      _isGraphBuilding = false;
      notifyListeners();
    }
  }

  Future<List<GraphEdge>?> findRoute(int startLogId, int endLogId) async {
    if (_graph == null) return null;

    // Calculate initial wait times for lines at the start node
    final Map<String, int> initialWaitTimes = {};
    
    try {
      // Get all lines starting from this node
      // We can't easily get edges from the graph without exposing adjacencyList, 
      // but we can iterate over _linhas and check if they pass through startLogId
      // OR better: expose neighbors from TransportGraph.
      // Since we can't change TransportGraph easily here without re-reading, 
      // let's use the cached itineraries which we have.
      
      final today = DateTime.now();
      final dateStr = "${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}";
      final currentMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;

      // Find lines passing through startLogId
      for (var linha in _linhas) {
        if (!_itinerarioCache.containsKey(linha.numero)) continue;
        
        final itinerarioCompleto = _itinerarioCache[linha.numero]!;
        int? waitTimeIda;
        int? waitTimeVolta;

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
             // Calculate wait time for Ida
             waitTimeIda = await _calculateNextBusWaitTime(
               linha.numero, 
               dateStr, 
               itinerarioCompleto.ida!.pontoInicial, 
               dist, 
               currentMinutes
             );
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
             // Calculate wait time for Volta
             waitTimeVolta = await _calculateNextBusWaitTime(
               linha.numero, 
               dateStr, 
               itinerarioCompleto.volta!.pontoInicial, 
               dist, 
               currentMinutes
             );
           }
        }

        // Take the minimum valid wait time
        int? bestWait;
        if (waitTimeIda != null && waitTimeVolta != null) {
          bestWait = waitTimeIda < waitTimeVolta ? waitTimeIda : waitTimeVolta;
        } else {
          bestWait = waitTimeIda ?? waitTimeVolta;
        }

        // If there's a valid wait time, use it. Otherwise, penalize heavily.
        if (bestWait != null) {
          initialWaitTimes[linha.numeroNome] = bestWait;
        } else {
          // No buses available - make this line extremely expensive (but not infinite to avoid breaking Dijkstra)
          initialWaitTimes[linha.numeroNome] = 999999; // ~694 days in minutes
        }
      }
    } catch (e) {
      print('Error calculating wait times: $e');
    }

    // Find initial route
    var route = _graph!.findShortestPath(startLogId, endLogId, initialWaitTimes: initialWaitTimes);
    
    // Validate that all lines in the route have buses available
    if (route != null && route.isNotEmpty) {
      bool needsRecalculation = false;
      final Set<String> linesToExclude = {};
      
      for (var edge in route) {
        // Check if this line has buses available
        if (!initialWaitTimes.containsKey(edge.lineName) || initialWaitTimes[edge.lineName] == 999999) {
          linesToExclude.add(edge.lineName);
          needsRecalculation = true;
        }
      }
      
      // If we found lines without buses, penalize them and recalculate
      if (needsRecalculation) {
        for (var lineName in linesToExclude) {
          initialWaitTimes[lineName] = 999999;
        }
        route = _graph!.findShortestPath(startLogId, endLogId, initialWaitTimes: initialWaitTimes);
      }
    }
    
    return route;
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
        if (posto.postoControle.toLowerCase() == pontoInicial.toLowerCase() ||
            posto.postoControle.toLowerCase().contains(pontoInicial.toLowerCase()) ||
            pontoInicial.toLowerCase().contains(posto.postoControle.toLowerCase())) {
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
      print('Error getting schedule for wait time: $e');
    }
    return null;
  }
}
