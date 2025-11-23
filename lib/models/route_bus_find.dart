import 'dart:collection';
import 'dart:math';

// =========================================================================
// 1. MODELOS DE DADOS E ESTRUTURAS (Requeridos pelo algoritmo)
// Você precisará garantir que sua API retorne dados mapeáveis para estas classes.
// =========================================================================

/// Representa um ponto geográfico ou logradouro no mapa (Origem/Destino/Parada).
class Logradouro {
  final int id;
  final String nome;
  final String tipo;
  final double latitude;
  final double longitude;

  const Logradouro({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() => nome;
}

/// Representa um ponto de parada dentro de um itinerário.
class ItineraryPoint extends Logradouro {
  final int logId;
  final String name;
  final double distanciaPercorrida; 

  ItineraryPoint({
    required this.logId,
    required this.name,
    required this.distanciaPercorrida,
    required double latitude,
    required double longitude,
  }) : super(
          id: logId,
          nome: name,
          tipo: 'Parada',
          latitude: latitude,
          longitude: longitude,
        );
}

/// Representa uma linha de ônibus.
class Line {
  final int id;
  final String name;
  final String numeroNome;
  final String tipoLinha;
  // Lista de todas as paradas sequenciais da linha (usadas para expansão de ônibus)
  final List<Logradouro> stops; 

  Line({
    required this.id,
    required this.name,
    required this.numeroNome,
    required this.tipoLinha,
    required this.stops,
  });
}

// =========================================================================
// 2. ESTRUTURAS AUXILIARES DO GRAFO E SERVIÇOS
// Estas classes são a estrutura do resultado do algoritmo.
// =========================================================================

enum SegmentType {
  walk, 
  bus, 
}

class RouteNode {
  final int logId;
  final double cost; 
  final RouteNode? predecessor;
  final int lineId; 
  final String lineName;
  final double segmentDistance; 
  final double segmentTime; 
  final String lineType;
  final Logradouro? stop; 
  final double latitude;
  final double longitude;

  RouteNode({
    required this.logId,
    required this.cost,
    required this.predecessor,
    required this.lineId,
    required this.lineName,
    required this.lineType,
    required this.stop,
    this.segmentDistance = 0.0,
    this.segmentTime = 0.0,
    double? latitude,
    double? longitude,
  })  : latitude = latitude ?? stop!.latitude,
        longitude = longitude ?? stop!.longitude;
}

class RouteSegment {
  final SegmentType type; 
  final Line? line; 
  final Logradouro startPoint;
  final Logradouro endPoint;
  final double distanceKm;
  final double durationMinutes;
  final double? waitTimeMinutes;

  RouteSegment({
    required this.type,
    required this.startPoint,
    required this.endPoint,
    required this.distanceKm,
    required this.durationMinutes,
    this.line,
    this.waitTimeMinutes,
  });

  factory RouteSegment.walk({
    required Logradouro startPoint,
    required Logradouro endPoint,
    required double distanceKm,
    required double durationMinutes,
  }) {
    return RouteSegment(
      type: SegmentType.walk,
      startPoint: startPoint,
      endPoint: endPoint,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      line: null,
      waitTimeMinutes: 0.0,
    );
  }

  factory RouteSegment.bus({
    required Line line,
    required Logradouro startPoint,
    required Logradouro endPoint,
    required double distanceKm,
    required double travelTimeMinutes,
    required double waitTimeMinutes,
  }) {
    return RouteSegment(
      type: SegmentType.bus,
      line: line,
      startPoint: startPoint,
      endPoint: endPoint,
      distanceKm: distanceKm,
      durationMinutes: travelTimeMinutes + waitTimeMinutes, 
      waitTimeMinutes: waitTimeMinutes,
    );
  }
}

class RouteSuggestion {
  final List<RouteSegment> segments;
  final double totalDistance;
  final double totalTime;
  final int transferCount;

  RouteSuggestion({
    required this.segments,
    required this.totalDistance,
    required this.totalTime,
    required this.transferCount,
  });

  factory RouteSuggestion.walkingOnly(double distanceKm, Logradouro origin, Logradouro destination) {
    final time = HaversineCalculator.distanceToWalkingTimeMinutes(distanceKm);
    return RouteSuggestion(
      segments: [
        RouteSegment.walk(
          startPoint: origin,
          endPoint: destination,
          distanceKm: distanceKm,
          durationMinutes: time,
        ),
      ],
      totalDistance: distanceKm,
      totalTime: time,
      transferCount: 0,
    );
  }
}

class HaversineCalculator {
  static const double R = 6371.0; 
  static const double walkingSpeedKmH = 4.5; 

  static double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);
    final a = pow(sin(dLat / 2), 2) +
        pow(sin(dLon / 2), 2) * cos(lat1Rad) * cos(lat2Rad);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c; 
  }

  static double distanceToWalkingTimeMinutes(double distanceKm) {
    final timeHours = distanceKm / walkingSpeedKmH;
    return timeHours * 60; 
  }

  static double distanceToBusTravelTimeMinutes(double distanceKm, double busSpeedKmh) {
    if (busSpeedKmh <= 0) return 0.0;
    final timeHours = distanceKm / busSpeedKmh;
    return timeHours * 60; 
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}

// =========================================================================
// 3. API PROVIDER (Lógica de Inicialização e Dijkstra)
// =========================================================================

class ApiProvider {
  // Configurações e custos do grafo
  static const double _busSpeedKmh = 15.0; 
  static const double _busWaitTimeMinutes = 10.0;
  static const double _walkPenaltyFactor = 1.0; 

  // Cache de dados (serão preenchidos pela sua API)
  Map<int, Line> _linesMap = {}; 
  Map<int, Logradouro> _logradourosMap = {};
  
  // Grafo de conexões de ônibus
  final Map<int, Map<int, List<int>>> _busGraphConnections = {};
  
  // Cache de itinerários (necessário para processar as conexões de paradas)
  // O tipo é ajustado para refletir o que sua API deve retornar: 
  // Map<lineId, {direcao: [pontos de itinerário]}>
  Map<int, Map<String, List<ItineraryPoint>>> _itinerariesCache = {};

  bool _isDataInitialized = false;

  /// Inicializa o cache de dados, chamando a sua API.
  Future<void> initializeData() async {
    if (_isDataInitialized) return;

    // ---------------------------------------------------------------------
    // 🛑 SEÇÃO DE INTEGRAÇÃO COM API REAL 🛑
    // Substitua o código abaixo pelas suas chamadas de API:
    // ---------------------------------------------------------------------

    // 1. Chame sua API para buscar TODOS os Logradouros/Paradas
    // Exemplo: final logradouros = await yourApi.fetchLogradouros();
    // Use uma lista de Logradouro vazia por enquanto:
    final List<Logradouro> logradouros = [];
    _logradourosMap = {for (var log in logradouros) log.id: log};

    // 2. Chame sua API para buscar TODAS as Linhas
    // Exemplo: final lines = await yourApi.fetchLines();
    final List<Line> lines = [];
    _linesMap = {for (var line in lines) line.id: line};

    // 3. Chame sua API para buscar TODOS os Itinerários
    // Exemplo: _itinerariesCache = await yourApi.fetchItineraries();

    // ---------------------------------------------------------------------
    
    // Constrói o grafo (conectando paradas sequenciais)
    for (final line in _linesMap.values) {
      final itineraries = _itinerariesCache[line.id];
      if (itineraries != null) {
        _processItinerary(line.id, itineraries['ida'] ?? []);
        _processItinerary(line.id, itineraries['volta'] ?? []);
      }
    }

    _isDataInitialized = true;
    print('Dados do grafo de rotas inicializados.');
  }

  /// Processa a sequência de paradas de um itinerário, construindo o grafo de conexões.
  void _processItinerary(int lineId, List<ItineraryPoint> stops) { 
    if (stops.isEmpty) return;

    final stopIds = stops.map((item) => item.logId).toList(); 

    for (int i = 0; i < stopIds.length - 1; i++) {
      final currentStopId = stopIds[i];
      final nextStopId = stopIds[i + 1];

      if (currentStopId <= 0 || nextStopId <= 0) continue; 

      _busGraphConnections.putIfAbsent(currentStopId, () => {});
      _busGraphConnections[currentStopId]!.putIfAbsent(lineId, () => []).add(nextStopId);
    }
  }

  /// Encontra a rota de ônibus mais rápida entre dois logradouros usando o algoritmo de Dijkstra.
  Future<RouteSuggestion?> fetchRouteSuggestion(int originLogId, int destinationLogId) async {
    await initializeData();

    final originLog = _logradourosMap[originLogId];
    final destinationLog = _logradourosMap[destinationLogId];

    if (originLog == null || destinationLog == null) {
      print('Origem ou destino não encontrados.');
      return null;
    }

    // Usando SplayTreeMap para simular a fila de prioridade
    final SplayTreeMap<double, List<RouteNode>> priorityMap = SplayTreeMap();
    void addToPriority(RouteNode node) {
      priorityMap.putIfAbsent(node.cost, () => []).add(node);
    }

    final Map<int, RouteNode> bestNodes = {};

    final startNode = RouteNode(
      logId: originLogId,
      cost: 0.0,
      predecessor: null,
      lineId: -1, 
      lineName: 'Início da Rota',
      latitude: originLog.latitude,
      longitude: originLog.longitude,
      stop: originLog,
      lineType: 'Caminhada',
    );

    addToPriority(startNode);
    bestNodes[originLogId] = startNode;

    RouteNode? destinationNode;

    while (priorityMap.isNotEmpty) {
      final bestCost = priorityMap.keys.first;
      final nodesWithBestCost = priorityMap[bestCost]!;
      final current = nodesWithBestCost.removeAt(0);
      
      if (nodesWithBestCost.isEmpty) {
        priorityMap.remove(bestCost);
      }

      final currentLogId = current.logId;

      if (currentLogId == destinationLogId) {
        destinationNode = current;
        break;
      }

      if (current.cost > bestNodes[currentLogId]!.cost) continue;

      // Expansão por Caminhada (Walk)
      _expandWalkConnections(current, destinationLog, addToPriority, bestNodes);

      // Expansão por Ônibus (Bus)
      if (current.lineId != -1) {
        _expandBusConnections(current, currentLogId, addToPriority, bestNodes);
      }
    }

    if (destinationNode != null) {
      return _buildRouteSuggestion(destinationNode, originLog);
    } else {
      // Fallback para rota SÓ de caminhada
      final distanceKm = HaversineCalculator.calculateDistance(
        originLog.latitude, originLog.longitude,
        destinationLog.latitude, destinationLog.longitude,
      );
      return RouteSuggestion.walkingOnly(distanceKm, originLog, destinationLog);
    }
  }

  void _expandBusConnections(
    RouteNode current,
    int currentLogId,
    Function(RouteNode) addToPriority,
    Map<int, RouteNode> bestNodes,
  ) {
    final line = _linesMap[current.lineId];
    if (line == null) return;

    final currentStopIndex = line.stops.indexWhere((stop) => stop.id == currentLogId);
    if (currentStopIndex == -1) return;

    if (currentStopIndex + 1 < line.stops.length) {
      final nextStop = line.stops[currentStopIndex + 1];
      final nextLogId = nextStop.id;

      final routeDistanceKm = HaversineCalculator.calculateDistance(
        current.latitude, current.longitude,
        nextStop.latitude, nextStop.longitude,
      );

      final travelTime = HaversineCalculator.distanceToBusTravelTimeMinutes(routeDistanceKm, _busSpeedKmh);
      final newCost = current.cost + travelTime;

      if (newCost < (bestNodes[nextLogId]?.cost ?? double.infinity)) {
        final newNode = RouteNode(
          logId: nextLogId,
          cost: newCost,
          predecessor: current,
          lineId: line.id,
          lineName: line.numeroNome,
          segmentDistance: routeDistanceKm,
          segmentTime: travelTime,
          lineType: line.tipoLinha,
          stop: nextStop,
        );
        bestNodes[nextLogId] = newNode;
        addToPriority(newNode);
      }
    }
  }

  void _expandWalkConnections(
    RouteNode current,
    Logradouro destinationLog,
    Function(RouteNode) addToPriority,
    Map<int, RouteNode> bestNodes,
  ) {
    final currentLog = _logradourosMap[current.logId] ?? current.stop;
    if (currentLog == null) return;

    final potentialDestinations = [destinationLog, ..._logradourosMap.values];

    for (final nextLog in potentialDestinations) {
      if (nextLog.id == current.logId) continue;

      final walkDistanceKm = HaversineCalculator.calculateDistance(
        currentLog.latitude, currentLog.longitude,
        nextLog.latitude, nextLog.longitude,
      );

      if (walkDistanceKm > 1.5) continue; 

      final walkTime = HaversineCalculator.distanceToWalkingTimeMinutes(walkDistanceKm) * _walkPenaltyFactor;
      
      final isBusStop = _busGraphConnections.containsKey(nextLog.id);
      
      final waitCost = (isBusStop && nextLog.id != destinationLog.id && current.lineId != _linesMap.keys.firstWhere((id) => _busGraphConnections[nextLog.id]!.containsKey(id), orElse: () => -2))
        ? _busWaitTimeMinutes
        : 0.0;
      
      final newCost = current.cost + walkTime + waitCost;

      // 1. Expande Caminhada para o Próximo Logradouro
      if (newCost < (bestNodes[nextLog.id]?.cost ?? double.infinity)) {
        final newNode = RouteNode(
          logId: nextLog.id,
          cost: newCost,
          predecessor: current,
          lineId: -1, 
          lineName: 'Caminhada',
          segmentDistance: walkDistanceKm,
          segmentTime: walkTime + waitCost, 
          lineType: 'Caminhada',
          stop: nextLog,
        );
        bestNodes[nextLog.id] = newNode;
        addToPriority(newNode);
      }
      
      // 2. Se o destino da caminhada (nextLog) é uma parada de ônibus, 
      // criamos um nó de transição para iniciar a expansão de ônibus.
      if (isBusStop && nextLog.id != destinationLog.id) {
        _busGraphConnections[nextLog.id]!.forEach((lineId, nextStops) {
          final line = _linesMap[lineId];
          if (line == null) return;
          
          final transitionNode = RouteNode(
            logId: nextLog.id,
            cost: newCost, 
            predecessor: bestNodes[nextLog.id], 
            lineId: line.id,
            lineName: line.numeroNome,
            segmentDistance: 0.0,
            segmentTime: 0.0,
            lineType: line.tipoLinha,
            stop: nextLog,
          );
          
          if (newCost < (bestNodes[nextLog.id]?.cost ?? double.infinity)) {
             bestNodes[nextLog.id] = transitionNode;
             addToPriority(transitionNode);
          }
        });
      }
    }
  }

  RouteSuggestion _buildRouteSuggestion(RouteNode destinationNode, Logradouro originLog) {
    final List<RouteNode> path = [];
    RouteNode? current = destinationNode;

    while (current != null) {
      path.add(current);
      current = current.predecessor;
    }

    final segments = <RouteSegment>[];
    double totalDistance = 0.0;
    int transferCount = 0;
    
    for (int i = path.length - 1; i > 0; i--) {
      final fromNode = path[i];
      final toNode = path[i - 1];
      
      final fromLog = fromNode.stop!;
      final toLog = toNode.stop!;
      
      final isWalk = toNode.lineId == -1 || toNode.lineId != fromNode.lineId;
      
      if (isWalk) {
        final walkSegment = RouteSegment.walk(
          startPoint: fromLog,
          endPoint: toLog,
          distanceKm: toNode.segmentDistance,
          durationMinutes: toNode.segmentTime,
        );
        segments.add(walkSegment);
      } else {
        final line = _linesMap[toNode.lineId]!;
        final busSegment = RouteSegment.bus(
          line: line,
          startPoint: fromLog,
          endPoint: toLog,
          distanceKm: toNode.segmentDistance,
          travelTimeMinutes: toNode.segmentTime,
          waitTimeMinutes: 0.0, 
        );
        segments.add(busSegment);
        
        if (segments.length > 1 && segments[segments.length - 2].type != SegmentType.bus) {
          transferCount++;
        }
      }
      
      totalDistance += toNode.segmentDistance;
    }
    
    return RouteSuggestion(
      segments: segments,
      totalDistance: totalDistance,
      totalTime: destinationNode.cost, 
      transferCount: transferCount,
    );
  }
}