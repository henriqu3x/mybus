import 'dart:math';

/// Representa um ponto no espaço 2D (Latitude, Longitude) para a Árvore K-d.
/// O logId é o identificador da parada de ônibus.
class KdNode {
  final double latitude;
  final double longitude;
  final int logId;
  KdNode? left;
  KdNode? right;

  KdNode({
    required this.latitude,
    required this.longitude,
    required this.logId,
    this.left,
    this.right,
  });
}

/// Implementação de uma Árvore K-d (2D) otimizada para buscas por raio em coordenadas Lat/Lon.
/// Esta estrutura é o "Geo Cache" que acelera o algoritmo de Dijkstra.
class KdTree {
  KdNode? root;

  /// Converte graus para radianos. Essencial para o cálculo Haversine.
  double _degreesToRadians(double degrees) => degrees * pi / 180;

  /// Calcula a distância Haversine (em km) entre dois pontos Lat/Lon.
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Raio da Terra em km
    
    // Converter TODAS as coordenadas de graus para radianos
    double rLat1 = _degreesToRadians(lat1);
    double rLon1 = _degreesToRadians(lon1);
    double rLat2 = _degreesToRadians(lat2);
    double rLon2 = _degreesToRadians(lon2);
    
    double dLat = rLat2 - rLat1;
    double dLon = rLon2 - rLon1;
    
    // Fórmula Haversine
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(rLat1) * cos(rLat2) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Constrói a Árvore K-d a partir de uma lista de nós.
  void build(List<KdNode> points) {
    root = _buildTree(points, 0);
  }

  /// Função recursiva para construir a árvore, dividindo o conjunto de pontos
  /// alternadamente pela latitude (eixo 0) e longitude (eixo 1).
  KdNode? _buildTree(List<KdNode> points, int depth) {
    if (points.isEmpty) return null;

    int axis = depth % 2; // 0 para latitude, 1 para longitude

    // Ordena os pontos com base no eixo de divisão
    points.sort((a, b) => axis == 0
        ? a.latitude.compareTo(b.latitude)
        : a.longitude.compareTo(b.longitude));

    int medianIndex = points.length ~/ 2;
    KdNode node = points[medianIndex];

    // Recursão: Cria sub-árvores esquerda e direita
    node.left = _buildTree(points.sublist(0, medianIndex), depth + 1);
    node.right = _buildTree(points.sublist(medianIndex + 1), depth + 1);

    return node;
  }

  /// Executa uma consulta por raio (Range Query) a partir de um ponto (lat, lon)
  /// e um raio (radiusKm), retornando os IDs dos logradouros dentro do raio.
  List<int> rangeQuery(double lat, double lon, double radiusKm) {
    List<int> result = [];
    _rangeQuery(root, lat, lon, radiusKm, 0, result);
    return result;
  }

  /// Função recursiva para a consulta de raio.
  void _rangeQuery(KdNode? node, double lat, double lon, double radiusKm, int depth, List<int> result) {
    if (node == null) return;

    // 1. Verificar se o ponto do nó está dentro do raio
    double distance = _haversineDistance(lat, lon, node.latitude, node.longitude);
    if (distance <= radiusKm) {
      result.add(node.logId);
    }

    int axis = depth % 2;
    
    // 2. Determinar qual sub-árvore buscar primeiro
    double splitValue = axis == 0 ? node.latitude : node.longitude;
    double searchCoordinate = axis == 0 ? lat : lon;
    
    KdNode? nearSubtree = searchCoordinate < splitValue ? node.left : node.right;
    KdNode? farSubtree = searchCoordinate < splitValue ? node.right : node.left;

    // 3. Buscar a sub-árvore "próxima"
    _rangeQuery(nearSubtree, lat, lon, radiusKm, depth + 1, result);

    // 4. OTIMIZAÇÃO CRÍTICA (PODA): Verificar se a região de busca (círculo)
    // cruza o plano de divisão do nó. Se não cruzar, não há necessidade de
    // buscar a sub-árvore "distante".
    
    // Para Lat/Lon, é mais preciso calcular a distância Haversine do ponto de busca
    // até o plano de divisão (onde uma das coordenadas é a do nó e a outra a do ponto de busca).
    double planeDistance;
    
    if (axis == 0) {
      // Distância (em km) do ponto de busca até a linha de latitude do nó
      planeDistance = _haversineDistance(lat, lon, splitValue, lon);
    } else {
      // Distância (em km) do ponto de busca até a linha de longitude do nó
      planeDistance = _haversineDistance(lat, lon, lat, splitValue);
    }

    // Se a distância até o plano de divisão for menor ou igual ao raio,
    // o círculo de busca toca ou cruza o plano, e a sub-árvore "distante"
    // deve ser checada.
    if (planeDistance <= radiusKm) {
      _rangeQuery(farSubtree, lat, lon, radiusKm, depth + 1, result);
    }
  }
}