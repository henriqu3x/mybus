import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart'; // Para PriorityQueue do Dijkstra
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
import '../services/kd_tree.dart'; // Para busca eficiente de vizinhos próximos
// Add this import at the top of api_provider.dart

// import '../models/route_result.dart'; // Usado para mapeamento final, mas não essencial aqui.

// Constantes
const double _maxWalkingDistanceKm = 0.5; // 500 metros para acesso/saída
const double _busSpeedKmh = 20.0; // Velocidade média do ônibus para cálculo de tempo
const double _walkTransferRadiusKm = 0.2; // 200m para transbordo a pé
const double _transferPenaltyMinutes = 10.0; // Penalidade por transbordo (tempo de espera/troca)

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

  // ApiProvider.dart - Seção de Constantes

  // NOVAS ESTRUTURAS CRUCIAIS PARA DIJKSTRA:
  // 1. Mapa de Logradouro ID (Stop) para as Linhas que passam por ele
  final Map<int, List<Line>> _stopsLinesMap = {}; 
  // 2. Mapa de Line ID para o objeto Line (necessário para a reconstrução da rota)
  Map<int, Line> _linesMap = {};
  // 3. KdTree para busca eficiente de vizinhos próximos
  KdTree _kdTree = KdTree();
  // 4. Mapa de distâncias por aresta (quando a API fornece 'distanciaPercorrida')
  // Estrutura: fromStopId -> lineId -> toStopId -> distanceMeters
  final Map<int, Map<int, Map<int, double>>> _edgeDistances = {};
  // ... (existente: final Map<int, Map<int, List<int>>> _busGraphConnections = {};)

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

  /// Constrói um grafo parcial em torno de um conjunto de logradouros seeds.
  ///
  /// Estratégia:
  /// - Encontra paradas próximas às seeds (usando KD-tree),
  /// - Para cada parada, busca as linhas que passam por ela (`LinhasDologradouro`),
  /// - Busca os itinerários dessas linhas e processa-os para popular o grafo.
  Future<void> _buildPartialGraphForStops(List<Logradouro> seeds) async {
    final stopIds = <int>{};
    // 1) Coletar paradas próximas às seeds (até 1km)
    for (final s in seeds) {
      if (s.latitude != 0.0 && s.longitude != 0.0) {
        final nearby = _kdTree.rangeQuery(s.latitude, s.longitude, 1.0);
        stopIds.addAll(nearby);
      }
      // também inclua o próprio logradouro se estiver no mapa
      if (_logradourosMap.containsKey(s.id)) stopIds.add(s.id);
      // Tentativa direta: buscar linhas que passam pelo próprio logradouro (sem depender da KD-tree)
      try {
        final directLines = await _fetchLinesByLogradouroCached(s.id);
        if (directLines.isNotEmpty) {
          if (kDebugMode) print('_buildPartialGraphForStops: found ${directLines.length} direct lines for seed ${s.id}');
          stopIds.add(s.id);
        }
      } catch (e) {
        if (kDebugMode) print('_buildPartialGraphForStops: failed to fetch lines for seed ${s.id}: $e');
      }
    }

    if (stopIds.isEmpty) {
      if (kDebugMode) print('_buildPartialGraphForStops: no nearby stops found for seeds');
      return;
    }
    if (kDebugMode) print('_buildPartialGraphForStops: building around ${stopIds.length} stops');

    final processedLines = <int>{};

    for (final stopId in stopIds) {
      List<Line> lines;
      try {
        lines = await _fetchLinesByLogradouroCached(stopId);
      } catch (e) {
        if (kDebugMode) print('  _buildPartialGraphForStops: failed to fetch lines for stop $stopId: $e');
        continue;
      }

      for (final line in lines) {
        if (processedLines.contains(line.id)) continue;
        processedLines.add(line.id);

        try {
          final itineraries = await _fetchItineraryCached(line.id);
          final idaStops = itineraries['ida']?.points ?? [];
          final voltaStops = itineraries['volta']?.points ?? [];
          _processItinerary(line, idaStops);
          _processItinerary(line, voltaStops);
        } catch (e) {
          if (kDebugMode) print('  _buildPartialGraphForStops: failed to fetch/process itinerary for line ${line.id}: $e');
          continue;
        }

        // Pequena pausa para evitar sobrecarregar o backend
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }
  }

  void removeFromFavorites(Line line) {
    _favoriteLines.removeWhere((l) => l.id == line.id);
    notifyListeners();
  }

  // ------------------------------------------------------------
  // INICIALIZAÇÃO E CONSTRUÇÃO DO GRAFO (NOVO)
  // ------------------------------------------------------------

  void _buildKdTree() {
    List<KdNode> nodes = [];
    for (var logradouro in _logradourosMap.values) {
      if (logradouro.latitude != 0.0 && logradouro.longitude != 0.0) {
        nodes.add(KdNode(
          latitude: logradouro.latitude,
          longitude: logradouro.longitude,
          logId: logradouro.id,
        ));
      }
    }
    if (kDebugMode) print('_buildKdTree: building kd-tree with ${nodes.length} nodes');
    _kdTree.build(nodes);
  }

  Future<void> initializeData() async {
  await _safeFetch(() async {
    // 1. Fetch e Geocodificação de Logradouros
    List<Logradouro> fetchedLogradouros = await _api.fetchLogradouros();
    _logradourosMap = {for (var l in fetchedLogradouros) l.id: l};
    _logradouros = fetchedLogradouros;
    
    await _geocodeAllLogradouros(fetchedLogradouros);
    
    // 2. Fetch e Cache de Linhas
    _allLinesCache = await _api.fetchLines();
    // POPULANDO _linesMap (CORREÇÃO 1)
    _linesMap = {for (var line in _allLinesCache!) line.id: line}; 

    // 3. Construção das Arestas de Ônibus
    await _buildBusGraphConnections();

    // 4. Construir KdTree para busca eficiente
    _buildKdTree();

    // CORREÇÃO 2: A função _buildBusGraphConnections() deve popular _stopsLinesMap,
    // mas a lógica atual está em _processItinerary. Vamos consolidar.
  });
}

  Future<void> _geocodeAllLogradouros(List<Logradouro> logradouros) async {
    for (var logradouro in logradouros) {
      if (logradouro.latitude == 0.0 && logradouro.longitude == 0.0) {
        // Clean the name before geocoding: remove parenthesis (neighborhood),
        // and content after commas or hyphens to improve Nominatim results.
        final queryName = _cleanLogradouroName(logradouro.nome);
        final coords = await _nominatimService.geocodeAddress(queryName);
        if (coords != null) {
          logradouro.latitude = coords['latitude']!;
          logradouro.longitude = coords['longitude']!;
        } else {
          if (kDebugMode) print('  -> geocode returned null for "$queryName"');
        }
      }
    }
  }

  // ApiProvider.dart - _buildBusGraphConnections()
  Future<void> _buildBusGraphConnections() async {
  _stopsLinesMap.clear(); // Limpa antes de popular
  if (kDebugMode) print('Starting _buildBusGraphConnections for ${_allLinesCache?.length ?? 0} lines');

  for (var line in _allLinesCache!) {
    Map<String, Itinerary> itineraries;
    try {
      itineraries = await _fetchItineraryCached(line.id);
    } catch (e) {
      if (kDebugMode) print('  _buildBusGraphConnections: failed to fetch itinerary for line ${line.id}: $e');
      continue; // pula esta linha e segue com as próximas
    }
    if (kDebugMode) {
      final idaCount = itineraries['ida']?.points.length ?? 0;
      final voltaCount = itineraries['volta']?.points.length ?? 0;
      print('Line ${line.id} (${line.name}): ida=$idaCount volta=$voltaCount');
      if (idaCount > 0) print('  sample ida[0]=${itineraries['ida']?.points.first}');
      if (voltaCount > 0) print('  sample volta[0]=${itineraries['volta']?.points.first}');
    }

    final idaStops = itineraries['ida']?.points ?? [];
    final voltaStops = itineraries['volta']?.points ?? [];

    _processItinerary(line, idaStops); // Passa o objeto Line
    _processItinerary(line, voltaStops);
  }
  if (kDebugMode) {
    print('Finished _buildBusGraphConnections: stopsLines=${_stopsLinesMap.length}, busGraph=${_busGraphConnections.length}');
    int totalEdgeDistanceEntries = 0;
    for (var m in _edgeDistances.values) {
      for (var inner in m.values) {
        totalEdgeDistanceEntries += inner.length;
      }
    }
    print('Finished _buildBusGraphConnections: edgeDistancesEntries=$totalEdgeDistanceEntries');
    if (_stopsLinesMap.isEmpty) print('WARNING: _stopsLinesMap is empty after building connections - verify fetchItinerary and itinerary parsing.');
  }
}

  // Corrigi o uso de ItineraryPoint
  void _processItinerary(Line line, List<ItineraryPoint> stops) {
  if (stops.isEmpty) {
    if (kDebugMode) print('  _processItinerary: line ${line.id} has empty stops');
    return;
  }
  final stopIds = stops.map((item) => item.logId).toList();

  for (int i = 0; i < stops.length; i++) {
      final point = stops[i];
      final currentStopId = point.logId;
      if (currentStopId <= 0) continue;

      // Atualiza coordenadas do Logradouro a partir do ItineraryPoint, quando disponíveis
      if (_logradourosMap.containsKey(currentStopId)) {
        final existing = _logradourosMap[currentStopId]!;
        if (point.latitude != 0.0 && point.longitude != 0.0 &&
            (existing.latitude == 0.0 && existing.longitude == 0.0)) {
          existing.latitude = point.latitude;
          existing.longitude = point.longitude;
          _logradourosMap[currentStopId] = existing;
        }
      } else {
        // Se não existir no mapa principal, cria uma entrada mínima para garantir
        // que a parada fique disponível para buscas espaciais (KD-tree)
        if (point.latitude != 0.0 && point.longitude != 0.0) {
          final newL = Logradouro(
            id: currentStopId,
            nome: point.name,
            tipo: '',
            latitude: point.latitude,
            longitude: point.longitude,
          );
          _logradourosMap[currentStopId] = newL;
          _logradouros ??= [];
          _logradouros!.add(newL);
        }
      }

      // 1. POPULAÇÃO DE _stopsLinesMap (Linhas por Parada)
      _stopsLinesMap.putIfAbsent(currentStopId, () => []).add(line);

      // 2. POPULAÇÃO DE CONEXÕES DIRETAS (Arestas do Grafo)
      if (i < stopIds.length - 1) {
          final nextStopId = stopIds[i + 1];

          if (nextStopId <= 0) continue;

          _busGraphConnections.putIfAbsent(currentStopId, () => {});
          _busGraphConnections[currentStopId]!.putIfAbsent(line.id, () => []).add(nextStopId);

          // Se a API fornece 'distanciaPercorrida' para o segmento, armazena como distância da aresta (metros)
          double segmentMeters = 0.0;
          try {
            final nextPoint = stops[i + 1];
            // Assume que 'distanciaPercorrida' neste JSON representa o comprimento do segmento
            segmentMeters = (nextPoint.distanciaPercorrida is num)
                ? (nextPoint.distanciaPercorrida as num).toDouble()
                : 0.0;
          } catch (_) {
            segmentMeters = 0.0;
          }

          if (segmentMeters > 0.0) {
            _edgeDistances.putIfAbsent(currentStopId, () => {});
            _edgeDistances[currentStopId]!.putIfAbsent(line.id, () => {});
            _edgeDistances[currentStopId]![line.id]![nextStopId] = segmentMeters;
          }
      }
  }
  if (kDebugMode) print('  _processItinerary: processed line ${line.id}, stops=${stopIds.length}');
}

  // ------------------------------------------------------------
  // BUSCA DE ROTAS COM DIJKSTRA (SUBSTITUINDO OS COMBINATÓRIOS)
  // ------------------------------------------------------------

  @override
  Future<List<RouteSuggestion>> fetchRouteSuggestions(
      Logradouro origin,
      Logradouro destination) async {
    
    if (_logradourosMap.isEmpty) await initializeData(); 

    // Se, após a inicialização, os dados essenciais não foram carregados,
    // provavelmente houve um erro de rede ou a API não respondeu.
    // Neste caso, lance uma exceção para que a camada de UI possa mostrar
    // uma mensagem de erro em vez de retornar silenciosamente uma rota
    // de caminhada (o que confunde o usuário).
    if (_logradourosMap.isEmpty || _allLinesCache == null || _allLinesCache!.isEmpty) {
      if (kDebugMode) print('fetchRouteSuggestions: data not loaded (logradouros=${_logradourosMap.length}, lines=${_allLinesCache?.length ?? 0})');
      throw Exception('Não foi possível carregar dados de linhas/logradouros. Verifique sua conexão e tente novamente.');
    }

    // Se origem/destino não têm coordenadas, tente geocodificá-los imediatamente
    if ((origin.latitude == 0.0 && origin.longitude == 0.0) || (destination.latitude == 0.0 && destination.longitude == 0.0)) {
      if (kDebugMode) print('One or both endpoints missing coordinates -> attempting geocode');
      try {
        if (origin.latitude == 0.0 && origin.longitude == 0.0) {
          await _ensureCoordinates(origin);
        }
        if (destination.latitude == 0.0 && destination.longitude == 0.0) {
          await _ensureCoordinates(destination);
        }
      } catch (e) {
        if (kDebugMode) print('Geocoding endpoints failed: $e');
      }
    }

    if (kDebugMode) {
      print('fetchRouteSuggestions: origin=${origin.id} ${origin.nome} (${origin.latitude},${origin.longitude}), '
            'destination=${destination.id} ${destination.nome} (${destination.latitude},${destination.longitude})');
      print('Caches: logradouros=${_logradourosMap.length}, lines=${_allLinesCache?.length ?? 0}, stopsLines=${_stopsLinesMap.length}, busGraph=${_busGraphConnections.length}');
    }

    // 1. Encontrar pontos de acesso/saída (por raio) — inicial
    List<Logradouro> nearestOriginStops = _findNearestStops(origin.latitude, origin.longitude, _maxWalkingDistanceKm);
    List<Logradouro> nearestDestinationStops = _findNearestStops(destination.latitude, destination.longitude, _maxWalkingDistanceKm);

    // Fallback defensivo: se o grafo global não foi construído (ex.: falha ao
    // buscar itinerários em massa), tente construir um grafo parcial apenas
    // em torno das paradas próximas à origem e destino para permitir planejamento
    // de rota on-demand sem dependência de pré-carregamento completo.
    if (_stopsLinesMap.isEmpty) {
      if (kDebugMode) print('stopsLinesMap empty -> building partial graph around origin/destination');
      await _buildPartialGraphForStops([origin, destination]);
      if (kDebugMode) print('After partial graph build: stopsLines=${_stopsLinesMap.length}, busGraph=${_busGraphConnections.length}');

      // Como o grafo mudou, recompute os candidatos por raio
      nearestOriginStops = _findNearestStops(origin.latitude, origin.longitude, _maxWalkingDistanceKm);
      nearestDestinationStops = _findNearestStops(destination.latitude, destination.longitude, _maxWalkingDistanceKm);
      if (kDebugMode) print('Recomputed nearest after partial build: origin=${nearestOriginStops.map((s) => s.id).toList()}, destination=${nearestDestinationStops.map((s) => s.id).toList()}');
    }

    if (kDebugMode) {
      print('Nearest by radius: originCandidates=${nearestOriginStops.map((s) => s.id).toList()}, destinationCandidates=${nearestDestinationStops.map((s) => s.id).toList()}');
    }

    // Se KD-Tree/coords não retornarem nada, mas o próprio Logradouro selecionado
    // for efetivamente uma parada (aparece no grafo _stopsLinesMap), use-o diretamente.
    if (nearestOriginStops.isEmpty && _stopsLinesMap.containsKey(origin.id)) {
      final l = _logradourosMap[origin.id];
      if (l != null) nearestOriginStops = [l];
    }
    if (nearestDestinationStops.isEmpty && _stopsLinesMap.containsKey(destination.id)) {
      final l = _logradourosMap[destination.id];
      if (l != null) nearestDestinationStops = [l];
    }

    // Se ainda estiver vazio, tente localizar paradas pela distância "manual"
    // varrendo as chaves de `_stopsLinesMap` (ignora KD-tree falha/cachê)
    if (nearestOriginStops.isEmpty) {
      final scanned = _findNearestStopsByScan(origin.latitude, origin.longitude, _maxWalkingDistanceKm);
      if (scanned.isNotEmpty) nearestOriginStops = scanned;
    }
    if (nearestDestinationStops.isEmpty) {
      final scanned = _findNearestStopsByScan(destination.latitude, destination.longitude, _maxWalkingDistanceKm);
      if (scanned.isNotEmpty) nearestDestinationStops = scanned;
    }

     // Se ainda estiver vazio para ambos, devolve sugestão de caminhada direta
     if (nearestOriginStops.isEmpty && nearestDestinationStops.isEmpty) {
       final distance = HaversineCalculator.calculateDistance(origin.latitude, origin.longitude, destination.latitude, destination.longitude);
       if (kDebugMode) print('No candidates on either side -> walkingOnly (distanceKm=$distance)');
       return [RouteSuggestion.walkingOnly(distance, origin, destination)];
     }

    // Se apenas um dos lados estiver vazio, tente usar o stop mais próximo globalmente
    if (nearestOriginStops.isEmpty && _logradourosMap.isNotEmpty) {
      Logradouro? nearest;
      double bestKm = double.infinity;
      for (final l in _logradourosMap.values) {
        if (l.latitude == 0.0 && l.longitude == 0.0) continue;
        final d = HaversineCalculator.calculateDistance(origin.latitude, origin.longitude, l.latitude, l.longitude);
        if (d < bestKm) {
          bestKm = d;
          nearest = l;
        }
      }
      if (nearest != null) nearestOriginStops = [nearest];
    }

    if (nearestDestinationStops.isEmpty && _logradourosMap.isNotEmpty) {
      Logradouro? nearest;
      double bestKm = double.infinity;
      for (final l in _logradourosMap.values) {
        if (l.latitude == 0.0 && l.longitude == 0.0) continue;
        final d = HaversineCalculator.calculateDistance(destination.latitude, destination.longitude, l.latitude, l.longitude);
        if (d < bestKm) {
          bestKm = d;
          nearest = l;
        }
      }
      if (nearest != null) nearestDestinationStops = [nearest];
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
    
    // Se não houver start nodes (por segurança), tente achar o stop mais próximo globalmente
    if (priorityQueue.isEmpty && _logradourosMap.isNotEmpty) {
      Logradouro? nearest;
      double bestKm = double.infinity;
      for (final l in _logradourosMap.values) {
        if (l.latitude == 0.0 && l.longitude == 0.0) continue;
        final d = HaversineCalculator.calculateDistance(origin.latitude, origin.longitude, l.latitude, l.longitude);
        if (d < bestKm) {
          bestKm = d;
          nearest = l;
        }
      }
      if (nearest != null) {
        final costMinutes = HaversineCalculator.distanceToWalkingTimeMinutes(bestKm);
        final startNode = RouteNode(
          logId: nearest.id,
          cost: costMinutes,
          predecessor: RouteNode(logId: virtualOriginId, cost: 0.0, lineId: -1, lineName: 'Caminhada'),
          lineId: -1,
          lineName: 'Caminhada',
          latitude: nearest.latitude,
          longitude: nearest.longitude,
        );
        distances[nearest.id] = costMinutes;
        priorityQueue.add(startNode);
        if (kDebugMode) print('Added global nearest start node: ${nearest.id} costMinutes=${costMinutes.toStringAsFixed(2)}');
      }
    }
    
    // 3. Loop Principal do Dijkstra
    int expandedNodes = 0;
    while (priorityQueue.isNotEmpty) {
      final current = priorityQueue.removeFirst();
      final currentLogId = current.logId;
      
      if (current.cost > (distances[currentLogId] ?? double.infinity)) continue;

      // Se encontrou uma parada próxima ao Destino
      if (nearestDestinationStops.any((s) => s.id == currentLogId)) {
        // Armazena a melhor rota encontrada até o momento
        if (finalNode == null || current.cost < finalNode.cost) {
             finalNode = current;
             if (kDebugMode) print('Found candidate finalNode at logId=${currentLogId} cost=${current.cost.toStringAsFixed(2)}');
        }
      }

      // 4. Expandir as arestas (Vizinhos)
      // A) Arestas de Ônibus
      _expandBusConnections(current, currentLogId, distances, priorityQueue);

      // B) Arestas de Caminhada (Transbordo)
      _expandWalkingTransfers(current, currentLogId, distances, priorityQueue);

      expandedNodes++;
      if (kDebugMode && expandedNodes % 500 == 0) {
        print('Dijkstra expanded nodes: $expandedNodes queueSize=${priorityQueue.length}');
      }
    }

    // 5. Reconstruir a rota
    if (kDebugMode) print('Dijkstra finished, expandedNodes=$expandedNodes finalNode=${finalNode?.logId}');
    if (finalNode != null) {
      if (kDebugMode) print('Reconstructing route from finalNode ${finalNode.logId}');
      final suggestion = _reconstructRoute(finalNode, destination, origin);
      if (kDebugMode) {
        final busSteps = suggestion.steps.where((s) => s.line != null).length;
        print('fetchRouteSuggestions: returning suggestion steps=${suggestion.steps.length} busSteps=$busSteps description=${suggestion.description} totalCost=${suggestion.totalCostMinutes.toStringAsFixed(2)}');
      }
      return [suggestion];
    }

    // Se não encontrou rota, devolve sugestão de caminhada direta como fallback.
    final directKm = HaversineCalculator.calculateDistance(origin.latitude, origin.longitude, destination.latitude, destination.longitude);
    if (kDebugMode) print('No route found -> walkingOnly (distanceKm=$directKm)');
    return [RouteSuggestion.walkingOnly(directKm, origin, destination)];
  }

  // ------------------------------------------------------------
  // MÉTODOS AUXILIARES E DE EXPANSÃO
  // ------------------------------------------------------------

  List<Logradouro> _findNearestStops(double lat, double lon, double maxDistanceKm) {
     // Usa a KdTree para encontrar paradas de ACESSO/SAÍDA (500m)
     final nearbyIds = _kdTree.rangeQuery(lat, lon, maxDistanceKm);
     return nearbyIds.map((id) => _logradourosMap[id]).where((l) => l != null).cast<Logradouro>().toList();
   }

  /// Varre `_stopsLinesMap` para encontrar paradas próximas quando a KD-tree
  /// não retorna resultados (fallback mais robusto).
  List<Logradouro> _findNearestStopsByScan(double lat, double lon, double maxDistanceKm) {
    final result = <Logradouro>[];
    for (final stopId in _stopsLinesMap.keys) {
      final l = _logradourosMap[stopId];
      if (l == null) continue;
      if (l.latitude == 0.0 && l.longitude == 0.0) continue;
      final d = HaversineCalculator.calculateDistance(lat, lon, l.latitude, l.longitude);
      if (d <= maxDistanceKm) result.add(l);
    }
    return result;
  }

  /// Garante que um `Logradouro` tenha coordenadas, tentando geocodificá-lo
  /// via Nominatim se necessário. Atualiza o `_logradourosMap` e reconstrói a KD-tree
  /// quando novas coordenadas forem obtidas.
  Future<void> _ensureCoordinates(Logradouro log) async {
    if (log.latitude != 0.0 || log.longitude != 0.0) return;
    final queryName = _cleanLogradouroName(log.nome);
    final coords = await _nominatimService.geocodeAddress(queryName);
    if (coords != null) {
      log.latitude = coords['latitude']!;
      log.longitude = coords['longitude']!;
      _logradourosMap[log.id] = log;
      // Reconstrói a árvore — simples e seguro para manter consistência
      _buildKdTree();
      if (kDebugMode) print('  _ensureCoordinates: geocoded ${log.id} -> ${log.latitude},${log.longitude}');
    } else {
      if (kDebugMode) print('  _ensureCoordinates: geocode returned null for ${log.nome}');
    }
  }

  // Arestas de Ônibus
void _expandBusConnections(
  RouteNode current,
  int currentLogId,
  Map<int, double> distances,
  PriorityQueue<RouteNode> priorityQueue,
) {
    // 1. Encontrar todas as linhas que passam por esta parada
    final lines = _stopsLinesMap[currentLogId] ?? <Line>[];

    for (var line in lines) {
        // Ignora transbordo de ônibus para o mesmo ônibus (se o predecessor não era caminhada)
        if (current.lineId == line.id && current.lineId != -1) continue; 

        // OTIMIZAÇÃO: Usa a estrutura de conexões pré-calculada (O(1) acesso)
        // Obtém o(s) próximo(s) stop(s) diretamente do grafo.
        final nextStopIds = _busGraphConnections[currentLogId]?[line.id] ?? [];

        for (final nextLogId in nextStopIds) {
            final nextStop = _logradourosMap[nextLogId];
            if (nextStop == null) continue;

            // Custo da aresta:
            // A) Penalidade de Transbordo: Aplicada se a linha muda.
            final transferPenalty = (current.lineId == line.id) ? 0.0 : _transferPenaltyMinutes;

            // B) Tempo de Viagem
            // Primeiro, tente usar coordenadas se existirem; caso contrário, use a distância
            // do segmento vinda da API (`_edgeDistances`) quando disponível (metros -> km).
            double routeDistanceKm;
            final currentStopForCalc = _logradourosMap[currentLogId];
            if ((currentStopForCalc == null || currentStopForCalc.latitude == 0.0 || currentStopForCalc.longitude == 0.0) ||
                (nextStop.latitude == 0.0 || nextStop.longitude == 0.0)) {
              final edgeMeters = _edgeDistances[currentLogId]?[line.id]?[nextLogId];
              if (edgeMeters != null && edgeMeters > 0) {
                routeDistanceKm = edgeMeters / 1000.0;
              } else {
                // Fallback para calcular via Haversine (pode retornar 0.0 se faltarem coords)
                routeDistanceKm = HaversineCalculator.calculateDistance(
                    currentStopForCalc?.latitude ?? 0.0,
                    currentStopForCalc?.longitude ?? 0.0,
                    nextStop.latitude,
                    nextStop.longitude);
              }
            } else {
              routeDistanceKm = HaversineCalculator.calculateDistance(
                  currentStopForCalc.latitude, currentStopForCalc.longitude, nextStop.latitude, nextStop.longitude);
            }
            final travelTime = HaversineCalculator.distanceToBusTravelTimeMinutes(routeDistanceKm, _busSpeedKmh);

            // Custo total acumulado
            final newCost = current.cost + travelTime + transferPenalty;

            // 4. Relaxamento da aresta
            if (newCost < (distances[nextLogId] ?? double.infinity)) {
                distances[nextLogId] = newCost;

                final nextNode = RouteNode(
                    logId: nextLogId,
                    cost: newCost,
                    predecessor: current,
                    lineId: line.id,
                    lineName: line.numeroNome,
                    lineType: line.tipoLinha,
                    stop: nextStop,
                    latitude: nextStop.latitude, 
                    longitude: nextStop.longitude,
                );
                // O próprio nó contém o predecessor (encadeamento), portanto não
                // é necessário manter um mapa separado de predecessores.
                priorityQueue.add(nextNode);
            }
        }
    }
}

  void _expandWalkingTransfers(
      RouteNode current,
      int currentLogId,
      Map<int, double> distances,
      PriorityQueue<RouteNode> priorityQueue,
) {
     final currentStop = _logradourosMap[currentLogId];
     if (currentStop == null) return; 

     // 🛑 Variável nearbyIds definida aqui
     final nearbyIds = _kdTree.rangeQuery(
          currentStop.latitude, 
          currentStop.longitude, 
          _walkTransferRadiusKm // Raio de 200m
     );

     for (var nextLogId in nearbyIds) {
          // Evita transbordo para o mesmo ponto
          if (nextLogId == currentLogId) continue; 
          
          // 🛑 Variável logradouro definida aqui
          final logradouro = _logradourosMap[nextLogId]; 
          if (logradouro == null) continue;

          // 2. Calcular distância e custo da caminhada
          final distanceKm = HaversineCalculator.calculateDistance(
               currentStop.latitude, currentStop.longitude, logradouro.latitude, logradouro.longitude);
          
          final walkTime = HaversineCalculator.distanceToWalkingTimeMinutes(distanceKm);
          // 🛑 Variável newCost definida aqui
          final newCost = current.cost + walkTime; 

          // 3. Relaxamento da aresta
          if (newCost < (distances[nextLogId] ?? double.infinity)) {
               distances[nextLogId] = newCost;

               final nextNode = RouteNode(
                    logId: nextLogId,
                    cost: newCost,
                    predecessor: current,
                    lineId: -1, // -1 indica caminhada
                    lineName: 'Caminhada',
                    lineType: 'Caminhada',
                    stop: logradouro,
                    latitude: logradouro.latitude,
                    longitude: logradouro.longitude,
               );
              // O encadeamento é mantido em `nextNode.predecessor`.
              // Não há necessidade de um mapa separado de predecessores.
               priorityQueue.add(nextNode);
          }
     }
}

  // ... (Métodos de expansão acima)

  RouteSuggestion _reconstructRoute(RouteNode finalNode, Logradouro destination, Logradouro origin) {
     final steps = <RouteStep>[];
     RouteNode? current = finalNode;
     Logradouro? finalWalkStartLogradouro = _logradourosMap[finalNode.logId];
    
    // VARIÁVEL LOCAL PARA CALCULAR O CUSTO TOTAL CORRETO
    double finalWalkCostMinutes = 0.0;

    // =========================================================
    // ETAPA 1: ADICIONA A CAMINHADA DE SAÍDA (Destino Real)
    // =========================================================
    if (finalWalkStartLogradouro != null) {
        final finalWalkStep = RouteStep(
            from: finalWalkStartLogradouro,
            to: destination,
            line: null, // Caminhada
            isWalking: true,
        );
        steps.add(finalWalkStep);
        
        // Calcula o custo dessa última perna para o total final
        finalWalkCostMinutes = HaversineCalculator.distanceToWalkingTimeMinutes(
            HaversineCalculator.calculateDistance(
                finalWalkStartLogradouro.latitude, finalWalkStartLogradouro.longitude, 
                destination.latitude, destination.longitude
            )
        );
    }


    // =========================================================
    // ETAPA 2: RECONSTROI O CAMINHO INTERMEDIÁRIO (Destino -> Origem)
    // O loop termina quando encontra o predecessor virtual (-1)
    // =========================================================
     while (current != null && current.logId != -1) {
          final predecessor = current.predecessor;

          if (predecessor == null || predecessor.logId == -1) {
               // 'current' é a primeira parada de ônibus. Paramos aqui e cuidamos da etapa inicial a seguir.
               break; 
          }

          final startLogradouro = _logradourosMap[predecessor.logId];
          final endLogradouro = _logradourosMap[current.logId];

          if (startLogradouro == null || endLogradouro == null) {
               current = predecessor;
               continue;
          }

          // Tenta resolver a linha pelo id. Se não estiver no mapa, tenta
          // localizar pela lista de linhas que passam pela parada
          Line? line;
          if (current.lineId != -1) {
            line = _linesMap[current.lineId];
            if (line == null) {
              // Procura na lista de linhas que passam pela parada 'startLogradouro'
              final candidates = _stopsLinesMap[predecessor.logId] ?? [];
              line = candidates.firstWhereOrNull((l) => l.id == current.lineId);
            }
            if (line == null && _allLinesCache != null) {
              line = _allLinesCache!.firstWhereOrNull((l) => l.id == current.lineId);
            }
            if (line != null) {
              // Cache localmente para próximas reconstruções
              _linesMap[current.lineId] = line;
            } else {
              if (kDebugMode) print('_reconstructRoute: missing Line for lineId=${current.lineId} at edge ${predecessor.logId}->${current.logId}');
            }
          }
          // Cria a etapa reversa (do fim para o início)
          final step = RouteStep(
               from: startLogradouro,
               to: endLogradouro,
               line: line,
               isWalking: current.lineId == -1,
          );

          steps.add(step);
          current = predecessor;
     }

    // =========================================================
    // ETAPA 3: ADICIONA A CAMINHADA DE ACESSO (Origem Real)
    // 'current' é a primeira parada de ônibus da rota.
    // =========================================================
    if (current != null && current.logId != -1) { 
        final firstStop = _logradourosMap[current.logId];
        
        if (firstStop != null) {
            final initialWalkStep = RouteStep(
                from: origin, // USA A ORIGEM REAL PASSADA
                to: firstStop,
                line: null, // Caminhada
                isWalking: true,
            );
            steps.add(initialWalkStep);
        }
    }


    // =========================================================
    // ETAPA 4: INVERTE A ORDEM E FINALIZA
    // =========================================================
     // Remove o sort, pois a inversão (reversed.toList()) é suficiente se a ordem de adição estiver correta.
     steps.removeWhere((step) => step.from == null || step.to == null);
     
     final finalSteps = steps.reversed.toList();
     
     // Cálculo de conexões
     int connectionsCount = 0;
    
    for (int i = 0; i < finalSteps.length; i++) {
        final currentStep = finalSteps[i];
        
        if (currentStep.line != null) { // É um passo de ônibus
            if (i == 0) continue; // O primeiro passo de ônibus não é transbordo
            
            final previousStep = finalSteps[i - 1];
            
            // É um transbordo se o passo anterior era caminhada ou uma linha diferente
            if (previousStep.line == null || previousStep.line!.id != currentStep.line!.id) {
                connectionsCount++;
            }
        }
    }

     // A descrição deve ser criada aqui
     final description = finalSteps.map((s) => s.line?.numeroNome ?? 'Caminhada').join(' → ');

     return RouteSuggestion(
          description: description,
          connections: connectionsCount,
          steps: finalSteps,
          // Usa o custo acumulado do Dijkstra (finalNode.cost) + o custo da última caminhada (finalWalkCostMinutes)
          totalCostMinutes: finalNode.cost + finalWalkCostMinutes,
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

  Future<Map<String, Itinerary>> fetchItinerary(int id) async {
    final result = await _fetchItineraryCached(id);
    _currentItinerary = result;
    notifyListeners();
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
    if (itinerary.isEmpty) return false;

    // Prioriza verificação por ID do logradouro (mais confiável)
    for (final it in itinerary.values) {
      for (final p in it.points) {
        // 1) Mesmo ID
        if (p.logId == log.id) return true;

        // 2) Se tivermos coordenadas, checar proximidade (50m)
        if (p.latitude != 0.0 && p.longitude != 0.0 && log.latitude != 0.0 && log.longitude != 0.0) {
          final distKm = HaversineCalculator.calculateDistance(p.latitude, p.longitude, log.latitude, log.longitude);
          if (distKm <= 0.05) return true; // <= 50 metros
        }

        // 3) Fallback por nome (normalizado) after cleaning parenthesis/extra info
        if (_normalize(_cleanLogradouroName(p.name)) == _normalize(_cleanLogradouroName(log.nome))) return true;
      }
    }

    return false;
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
  }

  /// Remove parenthesis content and trailing neighborhood/extra info from a
  /// logradouro name to produce a cleaner query suitable for geocoding.
  String _cleanLogradouroName(String text) {
    var s = text;
    // Remove parenthesis and their contents: "Name (Neighborhood)" -> "Name"
    s = s.replaceAll(RegExp(r'\(.*?\)'), '');
    // If there is a comma or hyphen, keep only the part before it
    if (s.contains(',')) s = s.split(',')[0];
    if (s.contains('-')) s = s.split('-')[0];
    return s.trim();
  }
}