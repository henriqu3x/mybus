import 'package:flutter/foundation.dart';
import 'dart:collection'; // Para PriorityQueue do Dijkstra
import 'dart:async';

// Seus imports
import '../services/api_services.dart';
import '../models/itinerary.dart';
import '../models/line.dart';
import '../models/schedule.dart';
import '../models/logradouro.dart';
import '../models/route_suggestion.dart'; 

// Novos imports necessários (Implemente estas classes)
import '../services/nominatim_service.dart';
import '../services/haversine_calculator.dart';
import '../models/route_node.dart'; // Classe simples para o nó do grafo (Logradouro + Custo)
// import '../models/route_result.dart'; // Usado para mapeamento final, mas não essencial aqui.

// Constantes
const double _maxWalkingDistanceKm = 0.5; // 500 metros para acesso/saída
const double _busSpeedKmh = 20.0; // Velocidade média do ônibus para cálculo de tempo
const double _walkTransferRadiusKm = 0.2; // 200m para transbordo a pé

class ApiProvider with ChangeNotifier {
  final ApiServices _api = ApiServices();
  final NominatimService _nominatimService = NominatimService();

  // ------------------------------------------------------------
  // ESTRUTURAS DO GRAFO E CACHE
  // ------------------------------------------------------------
  Map<int, Logradouro> _logradourosMap = {};
  final Map<int, Map<String, Itinerary>> _itineraryCache = {};
  final Map<int, List<Line>> _linesByLogradouroCache = {};
  List<Line>? _allLinesCache;

  // Mapa de Logradouro ID para a lista de paradas subsequentes por linha
  final Map<int, Map<int, List<int>>> _busGraphConnections = {}; 

  // ------------------------------------------------------------
  // ESTADOS PADRÃO
  // ------------------------------------------------------------

  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Line>? _lines;
  List<Schedule>? _schedules;
  List<Logradouro>? _logradouros;
  List<Line>? _linesByLogradouro;

  List<Line>? get lines => _lines;
  List<Schedule>? get schedules => _schedules;
  List<Logradouro>? get logradouros => _logradouros;
  List<Line>? get linesByLogradouro => _linesByLogradouro;

  Map<String, Itinerary>? _currentItinerary;
  Map<String, Itinerary>? get itinerary => _currentItinerary;

  final List<Line> _favoriteLines = [];
  List<Line> get favoriteLines => _favoriteLines;

  bool isFavorite(Line line) =>
      _favoriteLines.any((l) => l.id == line.id);

  void addToFavorites(Line line) {
    if (!isFavorite(line)) {
      _favoriteLines.add(line);
      notifyListeners();
    }
  }

  void removeFromFavorites(Line line) {
    _favoriteLines.removeWhere((l) => l.id == line.id);
    notifyListeners();
  }

  // ------------------------------------------------------------
  // INICIALIZAÇÃO E CONSTRUÇÃO DO GRAFO (NOVO)
  // ------------------------------------------------------------
  
  Future<void> initializeData() async {
    await _safeFetch(() async {
      // 1. Fetch e Geocodificação de Logradouros
      List<Logradouro> fetchedLogradouros = await _api.fetchLogradouros();
      _logradourosMap = {for (var l in fetchedLogradouros) l.id: l};
      _logradouros = fetchedLogradouros;
      
      await _geocodeAllLogradouros(fetchedLogradouros);
      
      // 2. Fetch e Cache de Linhas
      _allLinesCache = await _api.fetchLines();

      // 3. Construção das Arestas de Ônibus
      await _buildBusGraphConnections();
    });
  }

  Future<void> _geocodeAllLogradouros(List<Logradouro> logradouros) async {
    for (var logradouro in logradouros) {
        if (logradouro.latitude == 0.0 && logradouro.longitude == 0.0) { 
            final coords = await _nominatimService.geocodeAddress(logradouro.nome);
            if (coords != null) {
                logradouro.latitude = coords['latitude']!;
                logradouro.longitude = coords['longitude']!;
            }
        }
    }
  }

  Future<void> _buildBusGraphConnections() async {
    for (var line in _allLinesCache!) {
      final itineraries = await _fetchItineraryCached(line.id);
      
      // As paradas do itinerário devem ter sido preenchidas com Lat/Lon no Logradouro
      _processItinerary(line.id, itineraries['ida']?.points ?? []);
      _processItinerary(line.id, itineraries['volta']?.points ?? []);
    }
  }

  // Corrigi o uso de ItineraryItem (presumi que 'points' contém ItineraryItem)
  void _processItinerary(int lineId, List<dynamic> stops) { 
    if (stops.isEmpty) return;

    // Extrai diretamente o logId, garantindo que o objeto possua este campo.
    // Se 'stops' já vier como List<Logradouro>, o cast abaixo deve funcionar.
    // Se vier como ItineraryPoint, o cast deve ser para ItineraryPoint.
    
    // SOLUÇÃO MAIS ROBUSTA (Assumindo que o objeto do itinerário possui um campo 'logId'):
    final stopIds = stops.map((item) => (item as dynamic).logId as int).toList(); 

    for (int i = 0; i < stopIds.length - 1; i++) {
      final currentStopId = stopIds[i];
      final nextStopId = stopIds[i + 1];

      _busGraphConnections.putIfAbsent(currentStopId, () => {});
      _busGraphConnections[currentStopId]!.putIfAbsent(lineId, () => []).add(nextStopId);
    }
  }


  // ------------------------------------------------------------
  // BUSCA DE ROTAS COM DIJKSTRA (SUBSTITUINDO OS COMBINATÓRIOS)
  // ------------------------------------------------------------

  @override
  Future<List<RouteSuggestion>> fetchRouteSuggestions(
      Logradouro origin,
      Logradouro destination) async {
    
    if (_logradourosMap.isEmpty) await initializeData(); 

    // 1. Encontrar pontos de acesso/saída
    final nearestOriginStops = _findNearestStops(origin.latitude, origin.longitude, _maxWalkingDistanceKm);
    final nearestDestinationStops = _findNearestStops(destination.latitude, destination.longitude, _maxWalkingDistanceKm);

    if (nearestOriginStops.isEmpty && nearestDestinationStops.isEmpty) {
        final distance = HaversineCalculator.calculateDistance(origin.latitude, origin.longitude, destination.latitude, destination.longitude);
        return [RouteSuggestion.walkingOnly(distance)];
    }

    // Estruturas de Dijkstra
    final distances = <int, double>{};
    final priorityQueue = PriorityQueue<RouteNode>((a, b) => a.cost.compareTo(b.cost));
    final virtualOriginId = -1; 
    RouteNode? finalNode;

    // 2. Inicializar o Dijkstra com as pernas de caminhada de acesso
    for (var stop in nearestOriginStops) {
      final distanceKm = HaversineCalculator.calculateDistance(
          origin.latitude, origin.longitude, stop.latitude, stop.longitude);
      final costMinutes = HaversineCalculator.distanceToWalkingTimeMinutes(distanceKm);

      final startNode = RouteNode(
        logId: stop.id, 
        cost: costMinutes,
        // Predecessor é o nó virtual da origem
        predecessor: RouteNode(logId: virtualOriginId, cost: 0.0, lineId: -1, lineName: 'Caminhada'),
        lineId: -1, // -1 indica caminhada/acesso
        lineName: 'Caminhada',
      );

      distances[stop.id] = costMinutes;
      priorityQueue.add(startNode);
    }
    
    // 3. Loop Principal do Dijkstra
    while (priorityQueue.isNotEmpty) {
      final current = priorityQueue.removeFirst();
      final currentLogId = current.logId;
      
      if (current.cost > (distances[currentLogId] ?? double.infinity)) continue;

      // Se encontrou uma parada próxima ao Destino
      if (nearestDestinationStops.any((s) => s.id == currentLogId)) {
        // Armazena a melhor rota encontrada até o momento
        if (finalNode == null || current.cost < finalNode.cost) {
             finalNode = current;
        }
      }

      // 4. Expandir as arestas (Vizinhos)
      // A) Arestas de Ônibus
      _expandBusConnections(current, currentLogId, distances, priorityQueue);

      // B) Arestas de Caminhada (Transbordo)
      _expandWalkingTransfers(current, currentLogId, distances, priorityQueue);
    }

    // 5. Reconstruir a rota
    if (finalNode != null) {
      return [_reconstructRoute(finalNode, destination)];
    }
    return [];
  }

  // ------------------------------------------------------------
  // MÉTODOS AUXILIARES E DE EXPANSÃO
  // ------------------------------------------------------------

  List<Logradouro> _findNearestStops(double lat, double lon, double maxDistanceKm) {
    final nearest = <Logradouro>[];
    
    final availableStops = _logradourosMap.values
        .where((l) => l.latitude != 0.0 || l.longitude != 0.0);

    for (var stop in availableStops) {
      final distance = HaversineCalculator.calculateDistance(
          lat, lon, stop.latitude, stop.longitude);

      if (distance <= maxDistanceKm) {
        nearest.add(stop);
      }
    }
    return nearest;
  }

  void _expandBusConnections(RouteNode current, int currentLogId, 
      Map<int, double> distances, PriorityQueue<RouteNode> priorityQueue) {
    
    final busConnections = _busGraphConnections[currentLogId] ?? {};
    
    for (var lineId in busConnections.keys) {
      final lineStops = busConnections[lineId]!;
      
      for (var nextLogId in lineStops) {
        final currentStop = _logradourosMap[currentLogId]!;
        final nextStop = _logradourosMap[nextLogId]!;
        
        final distanceKm = HaversineCalculator.calculateDistance(
            currentStop.latitude, currentStop.longitude, nextStop.latitude, nextStop.longitude);
        final travelTimeMinutes = (distanceKm / _busSpeedKmh) * 60;

        // Tempo de Espera: Apenas se houver transbordo (troca de linha)
        final waitTimeMinutes = current.lineId != lineId ? 5.0 : 0.0; 

        final newCost = current.cost + travelTimeMinutes + waitTimeMinutes;
        
        if (newCost < (distances[nextLogId] ?? double.infinity)) {
          distances[nextLogId] = newCost;
          final newLine = _allLinesCache?.firstWhere((l) => l.id == lineId);

          final nextNode = RouteNode(
            logId: nextLogId,
            cost: newCost,
            predecessor: current,
            lineId: lineId,
            lineName: newLine?.nome ?? 'Linha $lineId',
          );

          priorityQueue.add(nextNode);
        }
      }
    }
  }

  void _expandWalkingTransfers(RouteNode current, int currentLogId,
      Map<int, double> distances, PriorityQueue<RouteNode> priorityQueue) {
    
    final currentStop = _logradourosMap[currentLogId]!;
    
    // Transbordo a pé entre paradas próximas
    final nearbyStops = _findNearestStops(currentStop.latitude, currentStop.longitude, _walkTransferRadiusKm);
    
    for (var nextStop in nearbyStops) {
      if (nextStop.id == currentLogId) continue;
      
      final distanceKm = HaversineCalculator.calculateDistance(
          currentStop.latitude, currentStop.longitude, nextStop.latitude, nextStop.longitude);
      final walkTimeMinutes = HaversineCalculator.distanceToWalkingTimeMinutes(distanceKm);
      
      final newCost = current.cost + walkTimeMinutes;
      
      if (newCost < (distances[nextStop.id] ?? double.infinity)) {
        distances[nextStop.id] = newCost;

        final nextNode = RouteNode(
          logId: nextStop.id,
          cost: newCost,
          predecessor: current,
          lineId: -1, // Transbordo a pé
          lineName: 'Caminhada (${distanceKm.toStringAsFixed(2)} km)',
        );
        
        priorityQueue.add(nextNode);
      }
    }
  }

  RouteSuggestion _reconstructRoute(RouteNode finalStopNode, Logradouro destination) {
    // 1. Perna final de caminhada
    final lastStop = _logradourosMap[finalStopNode.logId]!;
    final finalWalkKm = HaversineCalculator.calculateDistance(
        lastStop.latitude, lastStop.longitude, destination.latitude, destination.longitude);
    final finalWalkMinutes = HaversineCalculator.distanceToWalkingTimeMinutes(finalWalkKm);

    // 2. Reconstruir o caminho
    final path = <RouteNode>[];
    RouteNode? current = finalStopNode;

    while (current != null && current.logId != -1) {
      path.add(current);
      current = current.predecessor;
    }
    
    final orderedPath = path.reversed.toList();
    
    // **Ajuste:** Aqui você geraria a lista de Segmentos de Rota (Caminhada -> Ônibus -> Caminhada)
    // Usando o RouteSuggestion.withConnection como mock por falta da estrutura Segmentos detalhada:
    
    // Encontra a primeira linha real e a última linha real
    final firstLineNode = orderedPath.firstWhere((n) => n.lineId != -1, orElse: () => orderedPath.first);
    final lastLineNode = orderedPath.lastWhere((n) => n.lineId != -1, orElse: () => orderedPath.last);

    return RouteSuggestion.withConnection(
        firstLine: _allLinesCache?.firstWhere((l) => l.id == firstLineNode.lineId, orElse: () => Line(id: -1, nome: 'Acesso a Pé', numero: 0, numeroNome: '0', tipoLinha: 'Acesso')),
        transferPoint: _logradourosMap[lastLineNode.logId] ?? destination, // Ponto de transbordo final
        secondLine: _allLinesCache?.firstWhere((l) => l.id == lastLineNode.lineId, orElse: () => Line(id: -1, nome: 'Saída a Pé', numero: 0, numeroNome: '0', tipoLinha: 'Saída')),
        totalCost: finalStopNode.cost + finalWalkMinutes
    );
  }

  // ------------------------------------------------------------
  // FUNÇÕES DE FETCH PADRÃO E CACHE (Mantidas)
  // ------------------------------------------------------------

  Future<void> fetchLines() async {
    await _safeFetch(() async {
      _lines = await _api.fetchLines();
      _allLinesCache = _lines;
    });
  }

  Future<void> fetchSchedules(int idLinha, String date) async {
    await _safeFetch(() async {
      _schedules = await _api.fetchSchedules(idLinha, date);
    });
  }

  Future<void> fetchLogradouros() async {
    await _safeFetch(() async {
      _logradouros = await _api.fetchLogradouros();
    });
  }

  Future<void> fetchLinesByLogradouro(int id) async {
    await _safeFetch(() async {
      _linesByLogradouro = await _fetchLinesByLogradouroCached(id);
    });
  }

  Future<Map<String, Itinerary>> _fetchItineraryCached(int id) async {
    if (_itineraryCache.containsKey(id)) return _itineraryCache[id]!;
    final result = await _api.fetchItinerary(id);
    _itineraryCache[id] = result;
    return result;
  }

  Future<List<Line>> _fetchLinesByLogradouroCached(int id) async {
    if (_linesByLogradouroCache.containsKey(id)) {
      return _linesByLogradouroCache[id]!;
    }
    final result = await _api.fetchLinesByLogradouro(id);
    _linesByLogradouroCache[id] = result;
    return result;
  }

  Future<List<Line>> _fetchAllLinesCached() async {
    if (_allLinesCache != null) return _allLinesCache!;
    _allLinesCache = await _api.fetchLines();
    return _allLinesCache!;
  }

  Future<void> _safeFetch(Future<void> Function() body) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await body();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  bool _itineraryContainsLogradouro(
      Map<String, Itinerary> itinerary,
      Logradouro log) {
    // ... (Sua lógica original de _itineraryContainsLogradouro) ...
    return false; // Retorno mock para evitar erros de compilação
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
  }
}